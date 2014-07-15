module optprop_LUT
  use helper_functions, only : approx
  use data_parameters, only : ireals, iintegers, one,zero,i0,i1,i3,mpiint,nil,inil,imp_int,imp_real
  use optprop_parameters, only: &
      Ndz_1_2,Nkabs_1_2,Nksca_1_2,Ng_1_2,Nphi_1_2,Ntheta_1_2,interp_mode_1_2,   &
      Ndz_8_10,Nkabs_8_10,Nksca_8_10,Ng_8_10,Nphi_8_10,Ntheta_8_10,interp_mode_8_10, &
      delta_scale,delta_scale_truncate,stddev_rtol
  use boxmc, only: t_boxmc,t_boxmc_8_10,t_boxmc_1_2
  use tenstream_interpolation, only: interp_4d,interp_6d,interp_6d_recursive,interp_4p2d
  use arrayio

  use mpi!, only: MPI_Comm_rank,MPI_DOUBLE_PRECISION,MPI_INTEGER,MPI_Bcast


  implicit none

  private
  public :: t_optprop_LUT, t_optprop_LUT_8_10,t_optprop_LUT_1_2
  ! This module loads and generates the LUT-tables for Tenstream Radiation
  ! computations.
  ! It also holds functions for interpolation on the regular LUT grid.

  integer(iintegers) :: iierr
  integer(mpiint) :: myid,comm_size,ierr

  type parameter_space
    real(ireals),allocatable ,dimension(:) :: dz
    real(ireals),allocatable ,dimension(:) :: kabs
    real(ireals),allocatable ,dimension(:) :: ksca
    real(ireals),allocatable ,dimension(:) :: g
    real(ireals),allocatable ,dimension(:) :: phi
    real(ireals),allocatable ,dimension(:) :: theta
    real(ireals) :: dz_exponent,kabs_exponent,ksca_exponent,g_exponent
    real(ireals) , dimension(2)      :: range_dz      = [ 50._ireals , 5001._ireals ]
    real(ireals) , dimension(2)      :: range_kabs    = [ nil        , 10._ireals    ] !lower limit for kabs , ksca is set in set_parameter_space
    real(ireals) , dimension(2)      :: range_ksca    = [ nil        , one           ] !lower limit for kabs , ksca is set in set_parameter_space
    real(ireals) , dimension(2)      :: range_g       = [ zero       , .999_ireals   ]
    real(ireals) , dimension(2)      :: range_phi     = [ zero       , 90._ireals    ]
    real(ireals) , dimension(2)      :: range_theta   = [ zero       , 90._ireals    ]
  end type

  type table
    real(ireals),allocatable :: c(:,:,:,:,:)
    real(ireals),allocatable :: stddev_rtol(:,:,:,:)
  end type

  type diffuseTable
    real(ireals) :: dx,dy
    character(len=300) :: fname
    type(table) :: S
    type(parameter_space) :: pspace
  end type

  type directTable
    real(ireals) :: dx,dy
    character(len=300) :: fname
    type(table),allocatable :: S(:,:) !dim=(phi,theta)
    type(table),allocatable :: T(:,:) !dim=(phi,theta)
    type(parameter_space) :: pspace
  end type

  type,abstract :: t_optprop_LUT
    class(t_boxmc),allocatable :: bmc
    type(directTable) :: dirLUT
    type(diffuseTable) :: diffLUT

    integer(iintegers) :: Ndz,Nkabs,Nksca,Ng,Nphi,Ntheta,interp_mode
    integer(iintegers) :: dir_streams=inil,diff_streams=inil
    logical :: LUT_initiliazed=.False.,optprop_LUT_debug=.True.
    character(len=300) :: lutbasename 

    contains
      procedure :: init
      procedure :: LUT_get_dir2dir,LUT_get_dir2diff,LUT_get_diff2diff
      procedure :: bmc_wrapper, scatter_LUTtables
      procedure :: createLUT_dir, createLUT_diff
      procedure :: loadLUT_dir, loadLUT_diff
      procedure :: set_parameter_space
  end type

  type,extends(t_optprop_LUT) :: t_optprop_LUT_1_2
  end type
  type,extends(t_optprop_LUT) :: t_optprop_LUT_8_10
  end type

contains
  subroutine init(OPP, dx,dy, azis,szas, comm)
      class(t_optprop_LUT) :: OPP
      real(ireals),intent(in) :: dx,dy
      real(ireals),intent(in) :: szas(:),azis(:) ! all solar zenith angles that happen in this scene
      integer(mpiint) ,intent(in) :: comm

      character(len=300) :: descr
      integer(iintegers) :: idx,idy

      call MPI_Comm_rank(comm, myid, ierr)
      call MPI_Comm_size(comm, comm_size, ierr)
      idx = nint( dx/10  ) * 10
      idy = nint( dy/10  ) * 10

      select type (OPP)
        class is (t_optprop_LUT_1_2)
          OPP%dir_streams  =  1
          OPP%diff_streams =  2
          OPP%lutbasename='/home/opt/cosmo_tica_lib/tenstream/optpropLUT/LUT_1_2.'
          allocate(t_boxmc_1_2::OPP%bmc)

        class is (t_optprop_LUT_8_10)
          OPP%dir_streams  =  8
          OPP%diff_streams = 10
          OPP%lutbasename='/home/opt/cosmo_tica_lib/tenstream/optpropLUT/LUT_8_10.'
          allocate(t_boxmc_8_10::OPP%bmc)

        class default
          stop 'initialize LUT: unexpected type for optprop_LUT object!'
      end select

      call OPP%bmc%init(comm)

      call OPP%set_parameter_space(OPP%diffLUT%pspace,one*idx)
      call OPP%set_parameter_space(OPP%dirLUT%pspace ,one*idx)
      call OPP%set_parameter_space(OPP%diffLUT%pspace,one*idx)

      write(descr,FMT='("diffuse.dx",I0,".pspace.dz",I0,".kabs",I0,".ksca",I0,".g",I0,".delta_",L1,"_",F0.3)') idx,OPP%Ndz,OPP%Nkabs,OPP%Nksca,OPP%Ng,delta_scale,delta_scale_truncate
      if(myid.eq.0) print *,'Loading diffuse LUT from ',descr
      OPP%diffLUT%fname = trim(OPP%lutbasename)//trim(descr)//'.h5'
      OPP%diffLUT%dx    = idx
      OPP%diffLUT%dy    = idy

      if(any(szas.lt.0)) then
        ! Load diffuse LUT
        call OPP%loadLUT_diff(comm)
      else

        ! Load direct LUTS
        write(descr,FMT='("direct.dx",I0,".pspace.dz",I0,".kabs",I0,".ksca",I0,".g",I0,".phi",I0,".theta",I0,".delta_",L1,"_",F0.3)') idx,OPP%Ndz,OPP%Nkabs,OPP%Nksca,OPP%Ng,OPP%Nphi,OPP%Ntheta,delta_scale,delta_scale_truncate
        if(myid.eq.0) print *,'Loading direct LUT from ',descr
        OPP%dirLUT%fname = trim(OPP%lutbasename)//trim(descr)//'.h5'
        OPP%dirLUT%dx    = idx
        OPP%dirLUT%dy    = idy

        call OPP%loadLUT_dir(azis, szas, comm)

        ! Load diffuse LUT
        call OPP%loadLUT_diff(comm)
      endif

      if(comm_size.gt.1) call OPP%scatter_LUTtables(azis,szas,comm)

      OPP%LUT_initiliazed=.True.
      if(myid.eq.0) print *,'Done loading LUTs (shape diffLUT',shape(OPP%diffLUT%S%c),')'

  end subroutine
subroutine loadLUT_diff(OPP, comm)
    class(t_optprop_LUT) :: OPP
    integer(mpiint),intent(in) :: comm
    integer(iintegers) :: errcnt
    character(300) :: str(2)
    logical :: lstddev_inbounds

    if(myid.eq.0) print *,'... loading diffuse OPP%diffLUT',myid
    if(allocated(OPP%diffLUT%S%c)) then
      print *,'OPP%diffLUT already loaded! is this a second call?',myid
      return
    endif

    write(str(1),FMT='("dx",I0)')   int(OPP%diffLUT%dx)
    write(str(2),FMT='("dy",I0)')   int(OPP%diffLUT%dy)

    errcnt=0
    if(myid.eq.0) then
      call h5load([OPP%diffLUT%fname,'diffuse',str(1),str(2),"S"],OPP%diffLUT%S%c,iierr) ; errcnt = errcnt+iierr
      if(allocated(OPP%diffLUT%S%c) ) then
        if( any(OPP%diffLUT%S%c.gt.one) .or. any(OPP%diffLUT%S%c.lt.zero) ) errcnt=100
        call check_diffLUT_matches_pspace(OPP%diffLUT)
      endif

      lstddev_inbounds=.False.
      call h5load([OPP%diffLUT%fname,'diffuse',str(1),str(2),"S_rtol"],OPP%diffLUT%S%stddev_rtol,iierr) ; errcnt = errcnt+iierr
      lstddev_inbounds = iierr.eq.i0
      if(lstddev_inbounds) lstddev_inbounds = all(OPP%diffLUT%S%stddev_rtol.le.stddev_rtol)

    endif
    call mpi_bcast(errcnt           , 1 , imp_int , 0 , comm , ierr)
    call mpi_bcast(lstddev_inbounds , 1 , MPI_LOGICAL , 0 , comm , ierr)

    if(errcnt.ne.0 .or. .not.lstddev_inbounds ) then
      if(myid.eq.0) then
        print *,'Loading of diffuse tables failed for',trim(OPP%diffLUT%fname),'  diffuse ',trim(str(1)),' ',trim(str(2)),'::',errcnt
        call h5write([OPP%diffLUT%fname,'diffuse',str(1),str(2),"pspace","range_dz   "],OPP%diffLUT%pspace%range_dz   ,iierr)
        call h5write([OPP%diffLUT%fname,'diffuse',str(1),str(2),"pspace","range_kabs   "],OPP%diffLUT%pspace%range_kabs   ,iierr)
        call h5write([OPP%diffLUT%fname,'diffuse',str(1),str(2),"pspace","range_ksca    "],OPP%diffLUT%pspace%range_ksca    ,iierr)
        call h5write([OPP%diffLUT%fname,'diffuse',str(1),str(2),"pspace","range_g    "],OPP%diffLUT%pspace%range_g    ,iierr)

        call h5write([OPP%diffLUT%fname,'diffuse',str(1),str(2),"pspace","dz   "],OPP%diffLUT%pspace%dz   ,iierr)
        call h5write([OPP%diffLUT%fname,'diffuse',str(1),str(2),"pspace","kabs   "],OPP%diffLUT%pspace%kabs   ,iierr)
        call h5write([OPP%diffLUT%fname,'diffuse',str(1),str(2),"pspace","ksca    "],OPP%diffLUT%pspace%ksca    ,iierr)
        call h5write([OPP%diffLUT%fname,'diffuse',str(1),str(2),"pspace","g    "],OPP%diffLUT%pspace%g    ,iierr)
      endif

      call OPP%createLUT_diff([OPP%diffLUT%fname,'diffuse',str(1),str(2),"S"],[OPP%diffLUT%fname,'diffuse',str(1),str(2),"S_rtol"],comm)

      if(myid.eq.0) then
        call h5write([OPP%diffLUT%fname,'diffuse',str(1),str(2),"S"],OPP%diffLUT%S%c,iierr)
        call h5write([OPP%diffLUT%fname,'diffuse',str(1),str(2),"S_rtol"],OPP%diffLUT%S%stddev_rtol,iierr)
      endif

      call mpi_barrier(comm,ierr)
!      call exit() !> \todo: We exit here in order to split the jobs for shorter runtime.
    endif

    if(myid.eq.0) deallocate(OPP%diffLUT%S%stddev_rtol)
    if(myid.eq.0) print *,'Done loading diffuse OPP%diffLUTs'
end subroutine
subroutine loadLUT_dir(OPP, azis,szas, comm)
    class(t_optprop_LUT) :: OPP
    real(ireals),intent(in) :: szas(:),azis(:) ! all solar zenith angles that happen in this scene
    integer(mpiint),intent(in) :: comm
    integer(iintegers) :: errcnt,iphi,itheta
    character(300) :: str(4)
    logical :: angle_mask(OPP%Nphi,OPP%Ntheta),lstddev_inbounds

    if(myid.eq.0) print *,'... loading direct OPP%dirLUT'
    if(allocated(OPP%dirLUT%S).and.allocated(OPP%dirLUT%T)) then
      print *,'OPP%dirLUTs already loaded!',myid
      return
    endif
    allocate( OPP%dirLUT%S(OPP%Nphi,OPP%Ntheta) )
    allocate( OPP%dirLUT%T(OPP%Nphi,OPP%Ntheta) )

    write(str(1),FMT='("dx",I0)') nint(OPP%dirLUT%dx)
    write(str(2),FMT='("dy",I0)') nint(OPP%dirLUT%dy)

    call determine_angles_to_load(OPP%dirLUT, azis, szas, angle_mask)
    do itheta=1,OPP%Ntheta
      do iphi  =1,OPP%Nphi
        errcnt=0
        if(.not.angle_mask(iphi,itheta) ) cycle

        write(str(3),FMT='("phi",I0)')  int(OPP%dirLUT%pspace%phi(iphi)    )
        write(str(4),FMT='("theta",I0)')int(OPP%dirLUT%pspace%theta(itheta))

        if(myid.eq.0) then
            print *,'Trying to load the LUT from file...'
            call h5load([OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"S"],OPP%dirLUT%S(iphi,itheta)%c,iierr) ; errcnt = errcnt+iierr
            if(allocated(OPP%dirLUT%S(iphi,itheta)%c) ) then
              if(any( OPP%dirLUT%S(iphi,itheta)%c.gt.one ).or.any(OPP%dirLUT%S(iphi,itheta)%c.lt.zero) ) errcnt=errcnt+100
            endif

            call h5load([OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"T"],OPP%dirLUT%T(iphi,itheta)%c,iierr) ; errcnt = errcnt+iierr
            if(allocated(OPP%dirLUT%T(iphi,itheta)%c) ) then
              if(any( OPP%dirLUT%T(iphi,itheta)%c.gt.one ).or.any(OPP%dirLUT%T(iphi,itheta)%c.lt.zero) ) errcnt=errcnt+100
              call check_dirLUT_matches_pspace(OPP%dirLUT)
            endif

            ! Check if the precision requirements are all met and if we can load the %stddev_rtol array
            lstddev_inbounds = .True. ! first assume that precision is met and then check if this is still the case...
            call h5load([OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"S_rtol"],OPP%dirLUT%S(iphi,itheta)%stddev_rtol,iierr) 
            if(lstddev_inbounds) lstddev_inbounds = iierr.eq.i0 
            if(lstddev_inbounds) lstddev_inbounds = all(OPP%dirLUT%S(iphi,itheta)%stddev_rtol.le.stddev_rtol)

            call h5load([OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"T_rtol"],OPP%dirLUT%T(iphi,itheta)%stddev_rtol,iierr)
            if(lstddev_inbounds) lstddev_inbounds = iierr.eq.i0
            if(lstddev_inbounds) lstddev_inbounds = all(OPP%dirLUT%S(iphi,itheta)%stddev_rtol.le.stddev_rtol)

            print *,'Tried to load the LUT from file... result is errcnt:',errcnt,'lstddev_inbounds',lstddev_inbounds
        endif

        call mpi_bcast(errcnt           , 1 , imp_int , 0 , comm , ierr)
        call mpi_bcast(lstddev_inbounds , 1 , MPI_LOGICAL , 0 , comm , ierr)

        if(errcnt.ne.0 .or. .not.lstddev_inbounds ) then
          if(myid.eq.0) then
            print *,'Loading of direct tables failed for',trim(OPP%dirLUT%fname),'  direct ',trim(str(1)),' ',trim(str(2)),' ',trim(str(3)),' ',trim(str(4)),'::',errcnt,'lstddev_inbounds',lstddev_inbounds
            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "range_dz   "] , OPP%dirLUT%pspace%range_dz    , iierr)
            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "range_kabs "] , OPP%dirLUT%pspace%range_kabs  , iierr)
            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "range_ksca "] , OPP%dirLUT%pspace%range_ksca  , iierr)
            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "range_g    "] , OPP%dirLUT%pspace%range_g     , iierr)
            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "range_phi  "] , OPP%dirLUT%pspace%range_phi   , iierr)
            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "range_theta"] , OPP%dirLUT%pspace%range_theta , iierr)

            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "dz   "]       , OPP%dirLUT%pspace%dz          , iierr)
            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "kabs "]       , OPP%dirLUT%pspace%kabs        , iierr)
            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "ksca "]       , OPP%dirLUT%pspace%ksca        , iierr)
            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "g    "]       , OPP%dirLUT%pspace%g           , iierr)
            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "phi  "]       , OPP%dirLUT%pspace%phi         , iierr)
            call h5write([OPP%dirLUT%fname , 'direct' , str(1) , str(2) , "pspace" , "theta"]       , OPP%dirLUT%pspace%theta       , iierr)
          endif

          call OPP%createLUT_dir([OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"T"], &
                                 [OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"S"], &
                                 [OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"T_rtol"],&
                                 [OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"S_rtol"],&
                                  comm,iphi,itheta)

          if(myid.eq.0) then
            print *,'Final dump of LUT for phi/theta',iphi,itheta
            call h5write([OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"S"],OPP%dirLUT%S(iphi,itheta)%c,iierr)
            call h5write([OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"T"],OPP%dirLUT%T(iphi,itheta)%c,iierr)

            call h5write([OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"S_rtol"],OPP%dirLUT%S(iphi,itheta)%stddev_rtol,iierr)
            call h5write([OPP%dirLUT%fname,'direct',str(1),str(2),str(3),str(4),"T_rtol"],OPP%dirLUT%T(iphi,itheta)%stddev_rtol,iierr)
            print *,'Final dump of LUT for phi/theta',iphi,itheta,'... done'
          endif

          call mpi_barrier(comm,ierr)
!          call exit() !> \todo: We exit here in order to split the jobs for shorter runtime.
        endif

        if(myid.eq.0) deallocate(OPP%dirLUT%S(iphi,itheta)%stddev_rtol)
        if(myid.eq.0) deallocate(OPP%dirLUT%T(iphi,itheta)%stddev_rtol)

        if(myid.eq.0) print *,'Done loading direct LUT, for phi/theta:',int(OPP%dirLUT%pspace%phi(iphi)),int(OPP%dirLUT%pspace%theta(itheta)),':: shape(T)',shape(OPP%dirLUT%T(iphi,itheta)%c),':: shape(S)',shape(OPP%dirLUT%S(iphi,itheta)%c)
      enddo !iphi
    enddo! itheta

    if(myid.eq.0) print *,'Done loading direct OPP%dirLUTs'
end subroutine
  subroutine scatter_LUTtables(OPP, azis,szas,comm)
      class(t_optprop_LUT) :: OPP
      real(ireals),intent(in) :: szas(:),azis(:) 
      integer(mpiint) ,intent(in) :: comm
      integer(iintegers) :: Ntot,Ncoeff
      integer(iintegers) :: iphi,itheta
      logical :: angle_mask(OPP%Nphi,OPP%Ntheta)

      call determine_angles_to_load(OPP%dirLUT, azis, szas, angle_mask)

      do itheta=1,OPP%Ntheta
        do iphi  =1,OPP%Nphi
          if(.not.angle_mask(iphi,itheta) ) cycle

          ! DIRECT 2 DIRECT
          if(myid.eq.0) then
            Ncoeff = size(OPP%dirLUT%T(iphi,itheta)%c, 1)
            Ntot   = size(OPP%dirLUT%T(iphi,itheta)%c) 
            print *,myid,'Scattering LUT tables....',Ncoeff,Ntot,' iphi,itheta',iphi,itheta 
          endif
          call mpi_bcast(Ncoeff, 1, imp_int, 0, comm, ierr)
          call mpi_bcast(Ntot  , 1, imp_int, 0, comm, ierr)

          if(myid.gt.0) allocate(OPP%dirLUT%T(iphi,itheta)%c(Ncoeff, OPP%Ndz, OPP%Nkabs, OPP%Nksca, OPP%Ng) )
          call mpi_bcast(OPP%dirLUT%T(iphi,itheta)%c, Ntot, imp_real, 0, comm, ierr)

          ! DIRECT 2 DIFFUSE
          if(myid.eq.0) then
            Ncoeff = size(OPP%dirLUT%S(iphi,itheta)%c, 1)
            Ntot   = size(OPP%dirLUT%S(iphi,itheta)%c) 
            !          print *,'Scattering LUT tables....',Ncoeff,Ntot
          endif
          call mpi_bcast(Ncoeff, 1, imp_int, 0, comm, ierr)
          call mpi_bcast(Ntot  , 1, imp_int, 0, comm, ierr)

          if(myid.gt.0) allocate(OPP%dirLUT%S(iphi,itheta)%c(Ncoeff, OPP%Ndz, OPP%Nkabs, OPP%Nksca, OPP%Ng) )
          call mpi_bcast(OPP%dirLUT%S(iphi,itheta)%c, Ntot, imp_real, 0, comm, ierr)

        enddo
      enddo

      ! DIFFUSE 2 DIFFUSE
      if(myid.eq.0) then
        Ncoeff = size(OPP%diffLUT%S%c, 1)
        Ntot   = size(OPP%diffLUT%S%c) 
        !          print *,'Scattering LUT tables....',Ncoeff,Ntot
      endif
      call mpi_bcast(Ncoeff, 1, imp_int, 0, comm, ierr)
      call mpi_bcast(Ntot  , 1, imp_int, 0, comm, ierr)

      if(myid.gt.0) allocate(OPP%diffLUT%S%c(Ncoeff, OPP%Ndz, OPP%Nkabs, OPP%Nksca, OPP%Ng) )
      call mpi_bcast(OPP%diffLUT%S%c, Ntot, imp_real, 0, comm, ierr)

!      print *,myid,' :: Scatter LUT -- sum of diff LUT-> S= ',sum(OPP%diffLUT%S%c)
  end subroutine

subroutine createLUT_diff(OPP, coeff_table_name, stddev_rtol_table_name, comm)
    class(t_optprop_LUT) :: OPP
    integer(mpiint),intent(in) :: comm
    character(len=*),intent(in) :: coeff_table_name(:)
    character(len=*),intent(in) :: stddev_rtol_table_name(:)

    integer(iintegers) :: idz,ikabs ,iksca,ig,total_size,cnt
    real(ireals) :: S_diff(OPP%diff_streams),T_dir(OPP%dir_streams)
    logical :: ldone,lstarted_calculations=.False.

    if(myid.eq.0.and. .not. allocated(OPP%diffLUT%S%stddev_rtol) ) then
      allocate(OPP%diffLUT%S%stddev_rtol(OPP%Ndz,OPP%Nkabs ,OPP%Nksca,OPP%Ng))
      OPP%diffLUT%S%stddev_rtol = one
      call h5write(stddev_rtol_table_name,OPP%diffLUT%S%stddev_rtol,iierr)
    endif

    if(myid.eq.0.and. .not. allocated(OPP%diffLUT%S%c) ) then

      select type(OPP)
        class is (t_optprop_LUT_8_10)
          allocate(OPP%diffLUT%S%c(12, OPP%Ndz,OPP%Nkabs ,OPP%Nksca,OPP%Ng))

        class is (t_optprop_LUT_1_2)
          allocate(OPP%diffLUT%S%c(2, OPP%Ndz,OPP%Nkabs ,OPP%Nksca,OPP%Ng))

        class default
          stop 'createLUT_diff: unexpected type for optprop_LUT object!'

      end select

      OPP%diffLUT%S%c = nil
      call h5write(coeff_table_name,OPP%diffLUT%S%c,iierr)
    endif

    total_size = OPP%Ng*OPP%Nksca*OPP%Nkabs *OPP%Ndz
    cnt=0
    do ig    =1,OPP%Ng
      do iksca    =1,OPP%Nksca    
        do ikabs    =1,OPP%Nkabs    
          do idz   =1,OPP%Ndz   
            cnt=cnt+1
            ! Check if we already calculated the coefficients and inform the other nodes
            ldone=.False.
            if(myid.eq.0) then
              if  ( all( OPP%diffLUT%S%c( :, idz,ikabs ,iksca,ig).ge.zero) &
               .and.all( OPP%diffLUT%S%c( :, idz,ikabs ,iksca,ig).le.one ) &
               .and. OPP%diffLUT%S%stddev_rtol(idz,ikabs ,iksca,ig).le.stddev_rtol &
               ) ldone = .True.
            endif
            call mpi_bcast(ldone,1 , MPI_LOGICAL, 0, comm, ierr)
            if(ldone) then
              cycle
            else
              lstarted_calculations = .True.
            endif

            if(myid.eq.0) print *,'diff dx',OPP%diffLUT%dx,'dz',OPP%diffLUT%pspace%dz(idz),' :: ',OPP%diffLUT%pspace%kabs (ikabs ),OPP%diffLUT%pspace%ksca(iksca),OPP%diffLUT%pspace%g(ig),'(',100*cnt/total_size,'%)'

            select type(OPP)
              class is (t_optprop_LUT_8_10)
                  ! src=1
                  call OPP%bmc_wrapper(i1,OPP%diffLUT%dx,OPP%diffLUT%dy,OPP%diffLUT%pspace%dz(idz),OPP%diffLUT%pspace%kabs (ikabs ),OPP%diffLUT%pspace%ksca(iksca),OPP%diffLUT%pspace%g(ig),.False.,delta_scale,zero,zero,comm,S_diff,T_dir)
                  if(myid.eq.0) OPP%diffLUT%S%c( 1, idz,ikabs ,iksca,ig) = S_diff(1)
                  if(myid.eq.0) OPP%diffLUT%S%c( 2, idz,ikabs ,iksca,ig) = S_diff(2)
                  if(myid.eq.0) OPP%diffLUT%S%c( 3, idz,ikabs ,iksca,ig) = sum(S_diff([3,4,7, 8]) )/4
                  if(myid.eq.0) OPP%diffLUT%S%c( 4, idz,ikabs ,iksca,ig) = sum(S_diff([5,6,9,10]) )/4
                  ! src=3
                  call OPP%bmc_wrapper(i3,OPP%diffLUT%dx,OPP%diffLUT%dy,OPP%diffLUT%pspace%dz(idz),OPP%diffLUT%pspace%kabs (ikabs ),OPP%diffLUT%pspace%ksca(iksca),OPP%diffLUT%pspace%g(ig),.False.,delta_scale,zero,zero,comm,S_diff,T_dir)
                  if(myid.eq.0) OPP%diffLUT%S%c( 5:10, idz,ikabs ,iksca,ig) = S_diff(1:6)
                  if(myid.eq.0) OPP%diffLUT%S%c( 11  , idz,ikabs ,iksca,ig) = sum(S_diff(7: 8))/2
                  if(myid.eq.0) OPP%diffLUT%S%c( 12  , idz,ikabs ,iksca,ig) = sum(S_diff(9:10))/2
              class is (t_optprop_LUT_1_2)
                  ! src=1
                  call OPP%bmc_wrapper(i1,OPP%diffLUT%dx,OPP%diffLUT%dy,OPP%diffLUT%pspace%dz(idz),OPP%diffLUT%pspace%kabs (ikabs ),OPP%diffLUT%pspace%ksca(iksca),OPP%diffLUT%pspace%g(ig),.False.,delta_scale,zero,zero,comm,S_diff,T_dir)
                  if(myid.eq.0) OPP%diffLUT%S%c( :, idz,ikabs ,iksca,ig) = S_diff
            end select
            if(myid.eq.0) OPP%diffLUT%S%stddev_rtol(idz,ikabs ,iksca,ig) = stddev_rtol

          enddo !dz
        enddo !kabs

        if(myid.eq.0) print *,'Checkpointing diffuse table ... (',100*cnt/total_size,'%)','started?',lstarted_calculations
        if(myid.eq.0 .and. lstarted_calculations) then
          print *,'Writing diffuse table to file...'
          call h5write(coeff_table_name,OPP%diffLUT%S%c,iierr)
          call h5write(stddev_rtol_table_name,OPP%diffLUT%S%stddev_rtol,iierr)
          print *,'done writing!',iierr
        endif

      enddo !ksca
    enddo !g
    if(myid.eq.0) print *,'done calculating diffuse coefficients'
end subroutine
subroutine createLUT_dir(OPP, dir_coeff_table_name, diff_coeff_table_name, dir_stddev_rtol_table_name,diff_stddev_rtol_table_name, comm, iphi,itheta)
    class(t_optprop_LUT) :: OPP
    character(len=*),intent(in) :: dir_coeff_table_name(:),diff_coeff_table_name(:)
    character(len=*),intent(in) :: dir_stddev_rtol_table_name(:),diff_stddev_rtol_table_name(:)
    integer(mpiint),intent(in) :: comm
    integer(iintegers),intent(in) :: iphi,itheta

    integer(iintegers) :: idz,ikabs ,iksca,ig,src,total_size,cnt
    real(ireals) :: S_diff(OPP%diff_streams),T_dir(OPP%dir_streams)
    logical :: ldone,lstarted_calculations=.False.

    if(myid.eq.0) then
      if(.not.allocated(OPP%dirLUT%S(iphi,itheta)%stddev_rtol) ) then
        allocate(OPP%dirLUT%S(iphi,itheta)%stddev_rtol(OPP%Ndz,OPP%Nkabs ,OPP%Nksca,OPP%Ng))
        OPP%dirLUT%S(iphi,itheta)%stddev_rtol = one
        call h5write(diff_stddev_rtol_table_name,OPP%dirLUT%S(iphi,itheta)%stddev_rtol,iierr)
      endif

      if(.not.allocated(OPP%dirLUT%T(iphi,itheta)%stddev_rtol) ) then
        allocate(OPP%dirLUT%T(iphi,itheta)%stddev_rtol( OPP%Ndz,OPP%Nkabs ,OPP%Nksca,OPP%Ng))
        OPP%dirLUT%T(iphi,itheta)%stddev_rtol = one
        call h5write(dir_stddev_rtol_table_name ,OPP%dirLUT%T(iphi,itheta)%stddev_rtol,iierr)
      endif
    endif

    if(myid.eq.0) then
      print *,'calculating direct coefficients for ',iphi,itheta

      if(.not. allocated(OPP%dirLUT%S(iphi,itheta)%c) ) then
        allocate(OPP%dirLUT%S(iphi,itheta)%c(OPP%dir_streams*OPP%diff_streams, OPP%Ndz,OPP%Nkabs ,OPP%Nksca,OPP%Ng))
        OPP%dirLUT%S(iphi,itheta)%c = nil
        call h5write(diff_coeff_table_name,OPP%dirLUT%S(iphi,itheta)%c,iierr) ; ierr = ierr+int(iierr)
      endif

      if(.not. allocated(OPP%dirLUT%T(iphi,itheta)%c) ) then
        allocate(OPP%dirLUT%T(iphi,itheta)%c(OPP%dir_streams*OPP%dir_streams, OPP%Ndz,OPP%Nkabs ,OPP%Nksca,OPP%Ng))
        OPP%dirLUT%T(iphi,itheta)%c = nil
        call h5write(dir_coeff_table_name ,OPP%dirLUT%T(iphi,itheta)%c,iierr) ; ierr = ierr+int(iierr)
      endif

    endif

    total_size = OPP%Ng*OPP%Nksca*OPP%Nkabs *OPP%Ndz
    cnt=0
    do ig    =1,OPP%Ng
      do iksca    =1,OPP%Nksca    
        do ikabs   =1,OPP%Nkabs    
          do idz   =1,OPP%Ndz   
            cnt=cnt+1
            ! Check if we already calculated the coefficients and inform the other nodes
            ldone=.False.
            if(myid.eq.0) then
              if(      all( OPP%dirLUT%S(iphi,itheta)%c( :, idz,ikabs ,iksca,ig).ge.zero) &
                 .and. all( OPP%dirLUT%S(iphi,itheta)%c( :, idz,ikabs ,iksca,ig).le.one)  &
                 .and. all( OPP%dirLUT%T(iphi,itheta)%c( :, idz,ikabs ,iksca,ig).ge.zero) &
                 .and. all( OPP%dirLUT%T(iphi,itheta)%c( :, idz,ikabs ,iksca,ig).le.one)  &
                 .and. OPP%dirLUT%S(iphi,itheta)%stddev_rtol(idz,ikabs ,iksca,ig).le.stddev_rtol  &
                 .and. OPP%dirLUT%T(iphi,itheta)%stddev_rtol(idz,ikabs ,iksca,ig).le.stddev_rtol  &
                       ) ldone = .True.
            endif
            call mpi_bcast(ldone,1 , MPI_LOGICAL, 0, comm, ierr)
            if(ldone) then
              cycle
            else
              lstarted_calculations = .True.
            endif

            if(myid.eq.0) print *,'direct dx',OPP%dirLUT%dx,'dz',OPP%dirLUT%pspace%dz(idz),'phi0,theta0',OPP%dirLUT%pspace%phi(iphi),OPP%dirLUT%pspace%theta(itheta),' :: '&
                ,OPP%dirLUT%pspace%kabs (ikabs ),OPP%dirLUT%pspace%ksca(iksca),OPP%dirLUT%pspace%g(ig),'(',100*cnt/total_size,'%)'

            do src=1,OPP%dir_streams

              call OPP%bmc_wrapper(src                             ,                                                               & 
                                   OPP%dirLUT%dx                   , OPP%dirLUT%dy                   , OPP%dirLUT%pspace%dz(idz) , &
                                   OPP%dirLUT%pspace%kabs (ikabs ) , OPP%dirLUT%pspace%ksca(iksca)   , OPP%dirLUT%pspace%g(ig)   , &
                                   .True.                          , delta_scale                     ,                             & ! direct(y/n), delta_scale(y/n)
                                   OPP%dirLUT%pspace%phi(iphi)     , OPP%dirLUT%pspace%theta(itheta) ,                             &
                                   comm                            , S_diff                          , T_dir)

              if(myid.eq.0) OPP%dirLUT%T(iphi,itheta)%c( (src-1)*OPP%dir_streams+1:src*OPP%dir_streams, idz,ikabs ,iksca,ig) = T_dir
              if(myid.eq.0) OPP%dirLUT%S(iphi,itheta)%c( (src-1)*OPP%diff_streams+1:(src)*OPP%diff_streams, idz,ikabs ,iksca,ig) = S_diff
            enddo
            if(myid.eq.0) OPP%dirLUT%S(iphi,itheta)%stddev_rtol( idz,ikabs,iksca,ig) = stddev_rtol
            if(myid.eq.0) OPP%dirLUT%T(iphi,itheta)%stddev_rtol( idz,ikabs,iksca,ig) = stddev_rtol
          enddo !dz
        enddo !kabs
      enddo !ksca

      if(myid.eq.0) print *,'Checkpointing direct table ... (',100*cnt/total_size,'%)','started?',lstarted_calculations
      if(myid.eq.0 .and. lstarted_calculations) then
        print *,'Writing direct table to file... (',100*cnt/total_size,'%)','started?',lstarted_calculations
        call h5write(diff_coeff_table_name,OPP%dirLUT%S(iphi,itheta)%c,iierr) ; ierr = ierr+int(iierr)
        call h5write(dir_coeff_table_name ,OPP%dirLUT%T(iphi,itheta)%c,iierr) ; ierr = ierr+int(iierr)
        call h5write(diff_stddev_rtol_table_name,OPP%dirLUT%S(iphi,itheta)%stddev_rtol,iierr)
        call h5write(dir_stddev_rtol_table_name, OPP%dirLUT%T(iphi,itheta)%stddev_rtol,iierr)
        print *,'done writing!',ierr
      endif

    enddo !g
    if(myid.eq.0) print *,'done calculating direct coefficients'
end subroutine
subroutine bmc_wrapper(OPP, src,dx,dy,dz,kabs ,ksca,g,dir,delta_scale,phi,theta,comm,S_diff,T_dir)
    class(t_optprop_LUT) :: OPP
    integer(iintegers),intent(in) :: src
    integer(mpiint),intent(in) :: comm
    logical,intent(in) :: dir,delta_scale
    real(ireals),intent(in) :: dx,dy,dz,kabs ,ksca,g,phi,theta

    real(ireals),intent(out) :: S_diff(OPP%diff_streams),T_dir(OPP%dir_streams)

    real(ireals) :: bg(3)

    bg(1) = kabs
    bg(2) = ksca
    bg(3) = g

    S_diff=nil
    T_dir=nil

!    print *,comm,'BMC :: calling bmc_get_coeff',bg,'src',src,'phi/theta',phi,theta,dz
    call OPP%bmc%get_coeff(comm,bg,src,S_diff,T_dir,dir,delta_scale,phi,theta,dx,dy,dz)
    !        print *,'BMC :: dir',T_dir,'diff',S_diff
end subroutine

  subroutine check_diffLUT_matches_pspace(LUT)
      type(diffuseTable),intent(in) :: LUT
      real(ireals),allocatable :: buf(:)
      character(300) :: str(2)
      integer(iintegers) align(4);
      write(str(1),FMT='("dx",I0)')   int(LUT%dx)
      write(str(2),FMT='("dy",I0)')   int(LUT%dy)
      align=0
      call h5load([LUT%fname,'diffuse',str(1 ) ,str(2 ) ,"pspace","dz      "],buf,iierr ) ; if(.not.compare_same( buf, LUT%pspace%dz   )  ) align(1 ) =1 ; deallocate(buf )
      call h5load([LUT%fname,'diffuse',str(1 ) ,str(2 ) ,"pspace","kabs    "],buf,iierr ) ; if(.not.compare_same( buf, LUT%pspace%kabs )  ) align(2 ) =1 ; deallocate(buf )
      call h5load([LUT%fname,'diffuse',str(1 ) ,str(2 ) ,"pspace","ksca    "],buf,iierr ) ; if(.not.compare_same( buf, LUT%pspace%ksca )  ) align(3 ) =1 ; deallocate(buf )
      call h5load([LUT%fname,'diffuse',str(1 ) ,str(2 ) ,"pspace","g       "],buf,iierr ) ; if(.not.compare_same( buf, LUT%pspace%g    )  ) align(4 ) =1 ; deallocate(buf )

      if(any(align.ne.0)) stop 'parameter space of direct LUT coefficients is not aligned!'
  end subroutine                                   
  subroutine check_dirLUT_matches_pspace(LUT)
      type(directTable),intent(in) :: LUT
      real(ireals),allocatable :: buf(:)
      character(300) :: str(2)
      integer(iintegers) align(6);
      write(str(1),FMT='("dx",I0)')   int(LUT%dx)
      write(str(2),FMT='("dy",I0)')   int(LUT%dy)
      align=0
      call h5load([LUT%fname,'direct',str(1 ) ,str(2 ) ,"pspace","dz      "],buf,iierr ) ; if(.not.compare_same( buf,LUT%pspace%dz    )  ) align(1 ) =1 ; deallocate(buf )
      call h5load([LUT%fname,'direct',str(1 ) ,str(2 ) ,"pspace","kabs    "],buf,iierr ) ; if(.not.compare_same( buf,LUT%pspace%kabs  )  ) align(2 ) =1 ; deallocate(buf )
      call h5load([LUT%fname,'direct',str(1 ) ,str(2 ) ,"pspace","ksca    "],buf,iierr ) ; if(.not.compare_same( buf,LUT%pspace%ksca  )  ) align(3 ) =1 ; deallocate(buf )
      call h5load([LUT%fname,'direct',str(1 ) ,str(2 ) ,"pspace","g       "],buf,iierr ) ; if(.not.compare_same( buf,LUT%pspace%g     )  ) align(4 ) =1 ; deallocate(buf )
      call h5load([LUT%fname,'direct',str(1 ) ,str(2 ) ,"pspace","phi     "],buf,iierr ) ; if(.not.compare_same( buf,LUT%pspace%phi   )  ) align(5 ) =1 ; deallocate(buf )
      call h5load([LUT%fname,'direct',str(1 ) ,str(2 ) ,"pspace","theta   "],buf,iierr ) ; if(.not.compare_same( buf,LUT%pspace%theta )  ) align(6 ) =1 ; deallocate(buf )

      if(any(align.ne.0)) stop 'parameter space of direct LUT coefficients is not aligned!'
    end subroutine                                   
  function compare_same(a,b)
    !> @brief compare 2 arrays that they are approximatly the same and
    !if not print them next to each other
    logical :: compare_same
    real(ireals),intent(in) :: a(:),b(:)
    integer(iintegers) :: k
    if( all( shape(a).ne.shape(b) ) ) then
      print *,'compare_same : was called with differing shapes!'
      compare_same = .False.
      return
    endif
    compare_same = all( approx( a,b,1e-3_ireals ) )
    if(.not. compare_same ) then
      print *,'Compare_Same :: Arrays are not the same:'
      do k=1,size(a)
        print *,'k=',k,'a',a(k),'b',b(k),'diff',a(k)-b(k)
      enddo
    endif
end function
    
subroutine determine_angles_to_load(LUT,azis,szas, mask)
    type(directTable) :: LUT
    real(ireals),intent(in) :: szas(:),azis(:) ! all solar zenith angles that happen in this scene
    logical,intent(out) :: mask(size(LUT%pspace%phi),size(LUT%pspace%theta)) ! boolean array, which LUT entries should be loaded

    integer(iintegers) :: itheta, iphi
    logical :: lneed_azi(2), lneed_sza(2)
    real(ireals) :: theta(2),phi(2) ! sza and azimuth angle
!    integer(iintegers) :: iszas(:),iazis(:) ! all solar zenith angles rounded to nearest integer value

    mask = .False.
    ! Check if really need to load it... i.e. we only want to load angles which are necessary for this run.
    do itheta=1,size(LUT%pspace%theta)-1
      do iphi  =1,size(LUT%pspace%phi)-1
        phi   = LUT%pspace%phi( [ iphi, iphi+1 ] )
        theta = LUT%pspace%theta( [ itheta, itheta+1 ]  )

        lneed_azi(1) = any( azis .ge. phi(1)       .and. azis .lt. sum(phi)/2 )
        lneed_azi(2) = any( azis .ge. sum(phi)/2   .and. azis .lt. phi(2) )

        lneed_sza(1) = any( szas .ge. theta(1)     .and. szas .lt. sum(theta)/2 )
        lneed_sza(2) = any( szas .ge. sum(theta)/2 .and. szas .lt. theta(2) )

        !print *,'determine_angles_to_load: occuring azimuths',azis,'/ szas',szas,': phi,theta',phi,theta,'need_azi',lneed_azi,'lneed_sza',lneed_sza

        if( lneed_azi(1) .and. lneed_sza(1) ) mask(iphi   , itheta)   = .True.
        if( lneed_azi(1) .and. lneed_sza(2) ) mask(iphi   , itheta+1) = .True.
        if( lneed_azi(2) .and. lneed_sza(1) ) mask(iphi+1 , itheta)   = .True.
        if( lneed_azi(2) .and. lneed_sza(2) ) mask(iphi+1 , itheta+1) = .True.

        !if (all( lneed_azi .and. lneed_sza )) mask([iphi,iphi+1],[itheta,itheta+1]) = .True. !todo breaks if we need either theta+1 or phi+1 i.e. uneven sza or phi=90
        !if (all( lneed_azi .and. lneed_sza )) mask([iphi],[itheta]) = .True. !todo breaks if we need either theta+1 or phi+1 i.e. uneven sza or phi=90
      enddo
    enddo
    if(myid.eq.0) then
      print *,'       phis',LUT%pspace%range_phi
      do itheta=1,size(LUT%pspace%theta)
        print *,'theta=',LUT%pspace%theta(itheta),' :: ',mask(:,itheta)
      enddo
    endif
end subroutine

function search_sorted_bisection(arr,val) ! return index+residula i where arr(i) .gt. val
  real(ireals) :: search_sorted_bisection
  real(ireals),intent(in) :: arr(:)
  real(ireals),intent(in) :: val
  real(ireals) :: loc_increment
  integer(iintegers) :: i,j,k

  i=lbound(arr,1)
  j=ubound(arr,1)

  do
    k=(i+j)/2
    if (val < arr(k)) then
      j=k
    else
      i=k
    endif
    if (i+1 >= j) then ! only single or tuple left
      ! i is left bound and j is right bound index
      if(i.eq.j) then
        loc_increment = zero
      else
        loc_increment = (val - arr(i)) / ( arr(j) - arr(i) )
      endif
      search_sorted_bisection= min(max(one*lbound(arr,1), i + loc_increment), one*ubound(arr,1)) ! return `real-numbered` location of val
      exit
    endif
  end do
end function

!function exp_param_to_index(val,range,N,expn)
!    real(ireals) :: exp_param_to_index
!    real(ireals),intent(in) :: val,range(2),expn
!    integer(iintegers),intent(in) :: N
!    real(ireals) :: expn1,k
!    expn1=one/expn
!    k=range(1)**expn1
!    if(.not.valid_input(val,range)) continue
!    exp_param_to_index = min(one*N, max(   one, one+ (N-1)*(val**expn1-k)/(range(2)**expn1-k)   ))
!end function
function exp_index_to_param(index,range,N,expn)
    real(ireals) :: exp_index_to_param
    real(ireals),intent(in) :: index,range(2),expn
    integer(iintegers),intent(in) :: N
    real(ireals) :: expn1
    expn1=one/expn
    exp_index_to_param = lin_index_to_param( index, range**expn1, N) ** expn
end function
!function lin_param_to_index(val,range,N)
!    real(ireals) :: lin_param_to_index
!    real(ireals),intent(in) :: val,range(2)
!    integer(iintegers),intent(in) :: N
!    if(.not.valid_input(val,range)) continue
!    lin_param_to_index = min(one*N, max(   one, one+ (N-one) * (val-range(1) )/( range(2)-range(1) )   ))
!end function
function lin_index_to_param(index,range,N)
    real(ireals) :: lin_index_to_param
    real(ireals),intent(in) :: index,range(2)
    integer(iintegers),intent(in) :: N
    lin_index_to_param = range(1) + (index-one) * ( range(2)-range(1) ) / (N-1)
end function

subroutine set_parameter_space(OPP,ps,dx)
    class(t_optprop_LUT) :: OPP
    type(parameter_space),intent(inout) :: ps
    real(ireals),intent(in) :: dx
    real(ireals) :: diameter ! diameter of max. cube size
    real(ireals),parameter :: maximum_transmission=one-1e-5_ireals ! this parameter defines the lambert beer transmission we want the LUT to have given a pathlength of the box diameter
    integer(iintegers) :: k


    select type(OPP)
      class is (t_optprop_LUT_1_2)
          OPP%Ndz    = Ndz_1_2
          OPP%Nkabs  = Nkabs_1_2
          OPP%Nksca  = Nksca_1_2
          OPP%Ng     = Ng_1_2
          OPP%Nphi   = Nphi_1_2
          OPP%Ntheta = Ntheta_1_2
          OPP%interp_mode = interp_mode_1_2
      class is (t_optprop_LUT_8_10)
          OPP%Ndz    = Ndz_8_10
          OPP%Nkabs  = Nkabs_8_10
          OPP%Nksca  = Nksca_8_10
          OPP%Ng     = Ng_8_10
          OPP%Nphi   = Nphi_8_10
          OPP%Ntheta = Ntheta_8_10
          OPP%interp_mode = interp_mode_8_10
      class default 
        stop 'set_parameter space: unexpected type for optprop_LUT object!'
    end select
    if(.not. allocated(ps%dz   )) allocate(ps%dz    (OPP%Ndz    ))
    if(.not. allocated(ps%kabs )) allocate(ps%kabs  (OPP%Nkabs  ))
    if(.not. allocated(ps%ksca )) allocate(ps%ksca  (OPP%Nksca  ))
    if(.not. allocated(ps%g    )) allocate(ps%g     (OPP%Ng     ))
    if(.not. allocated(ps%phi  )) allocate(ps%phi   (OPP%Nphi   ))
    if(.not. allocated(ps%theta)) allocate(ps%theta (OPP%Ntheta ))

    ps%dz_exponent=1
    ps%kabs_exponent=10.
    ps%ksca_exponent=10.
    ps%g_exponent=.25

    select type(OPP)
      class is (t_optprop_LUT_1_2)
        ps%range_dz      = [ min(ps%range_dz(1), dx/10._ireals )  , max( ps%range_dz(2), dx ) ]
      class is (t_optprop_LUT_8_10)
        ps%range_dz      = [ min(ps%range_dz(1), dx/10._ireals )  , min( ps%range_dz(2), dx ) ]
      class default 
        stop 'set_parameter space: unexpected type for optprop_LUT object!'
    end select

    do k=1,OPP%Ndz
      ps%dz(k)    = exp_index_to_param(one*k,ps%range_dz,OPP%Ndz, ps%dz_exponent )
    enddo

    if(OPP%Ndz.eq.3) then
      if(approx(dx,40._ireals) ) then
        ps%dz(1) = 10._ireals/40._ireals *dx
        ps%dz(2) = 20._ireals/40._ireals *dx
        ps%dz(3) = 30._ireals/40._ireals *dx
      else
        ps%dz(3) = 100._ireals/500._ireals *dx
        ps%dz(1) = 40._ireals/70._ireals *dx
        ps%dz(2) = 200._ireals/250._ireals *dx
      endif
      ps%range_dz = [minval(ps%dz),maxval(ps%dz)]
    endif

    if(OPP%Ndz.eq.2) then
      ps%dz(1) = 40._ireals/70._ireals *dx
      ps%dz(2) = 200._ireals/250._ireals *dx
      ps%range_dz = [minval(ps%dz),maxval(ps%dz)]
    endif

    diameter = sqrt(2*dx**2 +  ps%range_dz(2)**2 )

    ps%range_kabs(1) = - log(maximum_transmission) / diameter
    ps%range_ksca(1) = - log(maximum_transmission) / diameter

    if( any([OPP%Ndz,OPP%Nkabs ,OPP%Nksca,OPP%Ng,OPP%Nphi,OPP%Ntheta].le.1) ) then
      print *,'Need at least 2 support points for LUT!'
      call exit()
    endif

    do k=1,OPP%Nkabs 
      ps%kabs (k) = exp_index_to_param(one*k,ps%range_kabs ,OPP%Nkabs,ps%kabs_exponent )
    enddo
    do k=1,OPP%Nksca
      ps%ksca (k) = exp_index_to_param(one*k,ps%range_ksca ,OPP%Nksca,ps%ksca_exponent )
    enddo
    do k=1,OPP%Ng
      ps%g(k)     = exp_index_to_param(one*k,ps%range_g,OPP%Ng, ps%g_exponent )
    enddo
    do k=1,OPP%Nphi
      ps%phi(k)   = lin_index_to_param(one*k,ps%range_phi,OPP%Nphi)
    enddo
    do k=1,OPP%Ntheta
      ps%theta(k) = lin_index_to_param(one*k,ps%range_theta,OPP%Ntheta)
    enddo
end subroutine

subroutine LUT_get_dir2dir(OPP, dz,in_kabs ,in_ksca,g,phi,theta,C)
    class(t_optprop_LUT) :: OPP
    real(ireals),intent(in) :: dz,in_kabs ,in_ksca,g,phi,theta
    real(ireals),intent(out):: C(OPP%dir_streams**2)
    real(ireals) :: kabs,ksca
    integer(iintegers) :: i

    real(ireals) :: pti(6),weights(6)

    kabs = in_kabs; ksca = in_ksca
    call catch_limits(OPP%dirLUT%pspace,dz,kabs,ksca,g)

    pti = get_indices_6d(dz,kabs ,ksca,g,phi,theta,OPP%dirLUT%pspace)

    select case(OPP%interp_mode)
    case(1)
      ! Nearest neighbour
      C = OPP%dirLUT%T(nint(pti(5)), nint(pti(6)) )%c(:,nint(pti(1)), nint(pti(2)), nint(pti(3)), nint(pti(4)) )
    case(2)
      weights = modulo(pti,one)

      call interp_4d(pti, weights, OPP%dirLUT%T(nint(pti(5)), nint(pti(6)) )%c, C)
    case default
      stop 'interpolation mode not implemented yet! please choose something else! '
    end select
    if(OPP%optprop_LUT_debug) then
      !Check for energy conservation:
      ierr=0
      do i=1,OPP%dir_streams
        if(sum(C( (i-1)*OPP%dir_streams+1:i*OPP%dir_streams)).gt.one) ierr=ierr+1
      enddo
      if(ierr.ne.0) then
        print *,'Error in dir2dir coeffs :: ierr',ierr
        do i=1,OPP%dir_streams
          print *,'SUM dir2dir coeff for src ',i,' :: sum ',sum(C( (i-1)*OPP%dir_streams+1:i*OPP%dir_streams)),' :: coeff',C( (i-1)*OPP%dir_streams+1:i*OPP%dir_streams)
        enddo
      endif
    endif
end subroutine 
subroutine LUT_get_dir2diff(OPP, dz,in_kabs ,in_ksca,g,phi,theta,C)
    class(t_optprop_LUT) :: OPP
    real(ireals),intent(in) :: dz,in_kabs ,in_ksca,g,phi,theta
    real(ireals),intent(out):: C(OPP%dir_streams*OPP%diff_streams)

    real(ireals) :: kabs,ksca
    real(ireals) :: pti(6),weights(6)
    integer(iintegers) :: i

    kabs = in_kabs; ksca = in_ksca
    call catch_limits(OPP%dirLUT%pspace,dz,kabs,ksca,g)

    pti = get_indices_6d(dz,kabs ,ksca,g,phi,theta,OPP%dirLUT%pspace)

    select case(OPP%interp_mode)
    case(1)
      ! Nearest neighbour
      C = OPP%dirLUT%S( nint(pti(5)), nint(pti(6)) )%c(:,nint(pti(1)), nint(pti(2)), nint(pti(3)), nint(pti(4)) )
    case(2)
      !                        print *,'linear interpolation not implemented yet!'
      weights = modulo(pti,one)
      call interp_4d(pti, weights, OPP%dirLUT%S( nint(pti(5)), nint(pti(6)) )%c, C)
    case default
      stop 'interpolation mode not implemented yet! please choose something else! '
    end select

    if(OPP%optprop_LUT_debug) then
      !Check for energy conservation:
      ierr=0
      do i=1,OPP%dir_streams
        if(sum(C( (i-1)*OPP%diff_streams+1:i*OPP%diff_streams)).gt.one) ierr=ierr+1
      enddo
      if(ierr.ne.0) then
        print *,'Error in dir2diff coeffs :: ierr',ierr
        do i=1,OPP%dir_streams
          print *,'SUM dir2dir coeff for src ',i,' :: sum ',sum(C( (i-1)*OPP%diff_streams+1:i*OPP%diff_streams)),' :: coeff',C( (i-1)*OPP%diff_streams+1:i*OPP%diff_streams)
        enddo
      endif
    endif
end subroutine
subroutine LUT_get_diff2diff(OPP, dz,in_kabs ,in_ksca,g,C)
    class(t_optprop_LUT) :: OPP
    real(ireals),intent(in) :: dz,in_kabs ,in_ksca,g
    real(ireals),allocatable,intent(out):: C(:)

    real(ireals) :: kabs,ksca
    real(ireals) :: pti(4),weights(4)

    kabs = in_kabs; ksca = in_ksca
    call catch_limits(OPP%diffLUT%pspace,dz,kabs,ksca,g)

    allocate( C(ubound(OPP%diffLUT%S%c,1) ) )
    pti = get_indices_4d(dz,kabs ,ksca,g,OPP%diffLUT%pspace)

    select case(OPP%interp_mode)
    case(1)
      ! Nearest neighbour
      C = OPP%diffLUT%S%c(:,nint(pti(1)), nint(pti(2)), nint(pti(3)), nint(pti(4)) )
    case(2)
      ! Linear interpolation
      weights = modulo(pti,one)
      call interp_4d(pti, weights, OPP%diffLUT%S%c, C)
    case default
      stop 'interpolation mode not implemented yet! please choose something else! '
    end select
end subroutine 

function get_indices_4d(dz,kabs ,ksca,g,ps)
    real(ireals) :: get_indices_4d(4)
    real(ireals),intent(in) :: dz,kabs ,ksca,g
    type(parameter_space),intent(in) :: ps

    get_indices_4d(1) = search_sorted_bisection(ps%dz   , dz)
    get_indices_4d(2) = search_sorted_bisection(ps%kabs , kabs)
    get_indices_4d(3) = search_sorted_bisection(ps%ksca , ksca)
    get_indices_4d(4) = search_sorted_bisection(ps%g    , g)
end function
function get_indices_6d(dz,kabs ,ksca,g,phi,theta,ps)
    real(ireals) :: get_indices_6d(6)
    real(ireals),intent(in) :: dz,kabs ,ksca,g,phi,theta
    type(parameter_space),intent(in) :: ps

    get_indices_6d(1:4) = get_indices_4d(dz,kabs ,ksca,g,ps)

    get_indices_6d(5) = search_sorted_bisection(ps%phi  ,phi )
    get_indices_6d(6) = search_sorted_bisection(ps%theta,theta)

end function

logical function valid_input(val,range)
    real(ireals),intent(in) :: val,range(2)
    if(val.lt.range(1) .or. val.gt.range(2) ) then 
      valid_input=.False.
      print *,'ohoh, this val is not in the optprop database range!',val,'not in',range
    else
      valid_input=.True.
    endif
end function
subroutine catch_limits(ps,dz,kabs,ksca,g)
    ! If we hit the upper limit of the LUT for kabs, we try to scale ksca down,
    ! so that single scatter albedo w stays constant ..... this is a hack for
    ! really big absorption optical depths, where we dampen the scattering
    ! strength
    type(parameter_space),intent(in) :: ps
    real(ireals),intent(inout) :: kabs,ksca
    real(ireals),intent(in) :: dz,g
    real(ireals) :: w,scaled_kabs,scaled_ksca
    
    if(kabs.gt.ps%range_kabs(2) ) then
      w = ksca/(kabs+ksca)
      scaled_kabs = ps%range_kabs(2)
      scaled_ksca = w*scaled_kabs / (one-w)
      print *,'rescaling kabs because it is too big kabs',kabs,'->',scaled_kabs,'ksca',ksca,'->',scaled_ksca
      ksca=scaled_ksca
      kabs=scaled_kabs
      stop 'catch_upper_limit_kabs happened -> but I dont know if this really helps!'
    endif

    kabs = max( ps%range_kabs(1), kabs ) ! Also use lower limit of LUT table....
    ksca = max( ps%range_ksca(1), ksca ) ! Lets hope that we have a meaningful lower bound, as we will not get a warning for this.
    ierr=0

    if( int(dz).lt.ps%range_dz(1) .or. int(dz).gt.ps%range_dz(2) ) then
      print *,'dz is not in LookUpTable Range',dz, 'LUT range',ps%range_dz
      ierr=ierr+1
    endif
    if( kabs.lt.ps%range_kabs(1) .or. kabs.gt.ps%range_kabs(2) ) then
      print *,'kabs is not in LookUpTable Range',kabs, 'LUT range',ps%range_kabs
      ierr=ierr+1
    endif
    if( ksca.lt.ps%range_ksca(1) .or. ksca.gt.ps%range_ksca(2) ) then
      print *,'ksca is not in LookUpTable Range',ksca, 'LUT range',ps%range_ksca
      ierr=ierr+1
    endif
    if( g.lt.ps%range_g(1) .or. g.gt.ps%range_g(2) ) then
      print *,'g is not in LookUpTable Range',g, 'LUT range',ps%range_g
      ierr=ierr+1
    endif
    if(ierr.ne.0) stop 'The LookUpTable was asked to give a coefficient, it was not defined for. Please specify a broader range.'
end subroutine



end module
