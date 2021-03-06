!-------------------------------------------------------------------------
! This file is part of the tenstream solver.
!
! This program is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.
!
! Copyright (C) 2010-2015  Fabian Jakub, <fabian@jakub.com>
!-------------------------------------------------------------------------

!> @brief Module contains Raytracer to compute Transfer Coefficients for different 'stream' realizations
!> @author Fabian Jakub LMU/MIM

module m_boxmc
#if defined(__INTEL_COMPILER)
  use ifport
#endif
#ifdef _XLF
  use ieee_arithmetic
#define isnan ieee_is_nan
#endif

  use m_helper_functions_dp, only : approx, mean, rmse, imp_reduce_sum, &
    norm, deg2rad, compute_normal_3d, spherical_2_cartesian, &
    hit_plane, square_intersection, triangle_intersection
  use m_helper_functions, only : CHKERR, get_arg
  use iso_c_binding
  use mpi
  use m_data_parameters, only: mpiint,iintegers,ireals,ireal_dp,i0,i1,i2,i3,i4,i5,i6,i7,i8,i9,i10, inil, pi_dp, &
    imp_iinteger, imp_real_dp, imp_logical

  use m_optprop_parameters, only : delta_scale_truncate,stddev_atol,stddev_rtol,ldebug_optprop

  use m_boxmc_geometry, only : setup_cube_coords_from_vertices, setup_wedge_coords_from_vertices, &
      intersect_cube, intersect_wedge

  implicit none

  private
  public :: t_boxmc, t_photon, &
    t_boxmc_8_10, t_boxmc_1_2, &
    t_boxmc_3_10, t_boxmc_3_6, &
    t_boxmc_wedge_5_5, t_boxmc_wedge_5_8, &
    scatter_photon, print_photon, roulette, R, &
    tau, distance, update_photon_loc, &
    imp_t_photon

  integer,parameter :: fg=1,bg=2,tot=3
  real(ireal_dp),parameter :: zero=0, one=1 ,nil=-9999

  integer(mpiint) :: mpierr

  logical :: lRNGseeded=.False.

  logical, parameter :: ldebug=.False.

  ! ******************** TYPE DEFINITIONS ************************
  type,abstract :: t_boxmc
    integer(iintegers) :: dir_streams=inil,diff_streams=inil
    logical :: initialized=.False.
  contains
    procedure :: init
    procedure :: get_coeff
    procedure :: move_photon
    procedure(intersect_distance),deferred :: intersect_distance

    procedure(init_dir_photon),deferred  :: init_dir_photon
    procedure(init_diff_photon),deferred :: init_diff_photon
    procedure(update_dir_stream),deferred  :: update_dir_stream
    procedure(update_diff_stream),deferred :: update_diff_stream
  end type

  type,extends(t_boxmc) :: t_boxmc_1_2
  contains
    procedure :: intersect_distance => intersect_distance_1_2
    procedure :: init_dir_photon    => init_dir_photon_1_2
    procedure :: init_diff_photon   => init_diff_photon_1_2
    procedure :: update_dir_stream  => update_dir_stream_1_2
    procedure :: update_diff_stream => update_diff_stream_1_2
  end type t_boxmc_1_2

  type,extends(t_boxmc) :: t_boxmc_8_10
  contains
    procedure :: intersect_distance => intersect_distance_8_10
    procedure :: init_dir_photon    => init_dir_photon_8_10
    procedure :: init_diff_photon   => init_diff_photon_8_10
    procedure :: update_dir_stream  => update_dir_stream_8_10
    procedure :: update_diff_stream => update_diff_stream_8_10
  end type t_boxmc_8_10

  type,extends(t_boxmc) :: t_boxmc_3_10
  contains
    procedure :: intersect_distance => intersect_distance_3_10
    procedure :: init_dir_photon    => init_dir_photon_3_10
    procedure :: init_diff_photon   => init_diff_photon_3_10
    procedure :: update_dir_stream  => update_dir_stream_3_10
    procedure :: update_diff_stream => update_diff_stream_3_10
  end type t_boxmc_3_10

  type,extends(t_boxmc) :: t_boxmc_3_6
  contains
    procedure :: intersect_distance => intersect_distance_3_6
    procedure :: init_dir_photon    => init_dir_photon_3_6
    procedure :: init_diff_photon   => init_diff_photon_3_6
    procedure :: update_dir_stream  => update_dir_stream_3_6
    procedure :: update_diff_stream => update_diff_stream_3_6
  end type t_boxmc_3_6

  type,extends(t_boxmc) :: t_boxmc_wedge_5_5
  contains
    procedure :: intersect_distance => intersect_distance_wedge_5_5
    procedure :: init_dir_photon    => init_dir_photon_wedge_5_5
    procedure :: init_diff_photon   => init_diff_photon_wedge_5_5
    procedure :: update_dir_stream  => update_dir_stream_wedge_5_5
    procedure :: update_diff_stream => update_diff_stream_wedge_5_5
  end type t_boxmc_wedge_5_5

  type,extends(t_boxmc) :: t_boxmc_wedge_5_8
  contains
    procedure :: intersect_distance => intersect_distance_wedge_5_8
    procedure :: init_dir_photon    => init_dir_photon_wedge_5_8
    procedure :: init_diff_photon   => init_diff_photon_wedge_5_8
    procedure :: update_dir_stream  => update_dir_stream_wedge_5_8
    procedure :: update_diff_stream => update_diff_stream_wedge_5_8
  end type t_boxmc_wedge_5_8

  type t_photon
    sequence
    real(ireal_dp) :: loc(3)=nil,dir(3)=nil,weight=nil,tau_travel=nil
    integer(iintegers) :: src_side=inil,side=inil,src=inil,scattercnt=0,cellid=inil
    integer(iintegers) :: i, j, k
    logical :: alive=.True.,direct=.False.
  end type

  integer(mpiint) :: imp_t_photon

  type stddev
    real(ireal_dp),allocatable,dimension(:) :: inc,delta,mean,mean2,var,relvar
    logical :: converged=.False.
    real(ireal_dp) :: atol=zero, rtol=zero
  end type
  ! ******************** TYPE DEFINITIONS ************************


  ! ***************** INTERFACES ************
  abstract interface
    subroutine init_diff_photon(bmc, p, src, vertices, ierr)
      import :: t_boxmc,t_photon,iintegers,ireal_dp,mpiint
      class(t_boxmc) :: bmc
      type(t_photon),intent(inout) :: p
      real(ireal_dp),intent(in) :: vertices(:)
      integer(iintegers),intent(in) :: src
      integer(mpiint), intent(out) :: ierr
    end subroutine
  end interface

  abstract interface
    subroutine init_dir_photon(bmc, p, src, ldirect, initial_dir, vertices, ierr)
      import :: t_boxmc, t_photon, iintegers, ireal_dp, mpiint
      class(t_boxmc) :: bmc
      type(t_photon),intent(inout) :: p
      real(ireal_dp),intent(in) :: vertices(:), initial_dir(:)
      integer(iintegers),intent(in) :: src
      logical,intent(in) :: ldirect
      integer(mpiint), intent(out) :: ierr
    end subroutine
  end interface

  abstract interface
    subroutine update_diff_stream(bmc,p,S)
      import :: t_boxmc,t_photon,iintegers,ireal_dp
      class(t_boxmc) :: bmc
      type(t_photon),intent(in) :: p
      real(ireal_dp),intent(inout) :: S(:)
    end subroutine
  end interface

  abstract interface
    subroutine update_dir_stream(bmc,vertices,p,T)
      import :: t_boxmc,t_photon,iintegers,ireal_dp
      class(t_boxmc) :: bmc
      real(ireal_dp),intent(in) :: vertices(:)
      type(t_photon),intent(in) :: p
      real(ireal_dp),intent(inout) :: T(:)
    end subroutine
  end interface

  abstract interface
    subroutine intersect_distance(bmc,vertices,p,max_dist)
      import :: t_boxmc,t_photon,ireal_dp
      class(t_boxmc) :: bmc
      real(ireal_dp),intent(in) :: vertices(:)
      type(t_photon),intent(inout) :: p
      real(ireal_dp),intent(out) :: max_dist
    end subroutine
  end interface
! ***************** INTERFACES ************

contains

  subroutine gen_mpi_photon_type()
    type(t_photon) :: dummy
    integer(mpiint),parameter :: block_cnt=3  ! Number of blocks
    integer(mpiint) :: blocklengths(block_cnt) ! Number of elements in each block
    integer(mpiint) :: dtypes(block_cnt) ! Type of elements in each block (array of handles to data-type objects)
    integer(mpi_address_kind) :: displacements(block_cnt), base ! byte displacement of each block
    integer(mpiint) :: ierr

    blocklengths(1) = 8 ! doubles to begin with
    blocklengths(2) = 8 ! ints
    blocklengths(3) = 2 ! logicals

    dtypes = [imp_real_dp, imp_iinteger, imp_logical]

    call mpi_get_address(dummy%loc, displacements(1), ierr); call chkerr(ierr)
    call mpi_get_address(dummy%src_side, displacements(2), ierr); call chkerr(ierr)
    call mpi_get_address(dummy%alive, displacements(3), ierr); call chkerr(ierr)

    base = displacements(1)
    displacements = displacements - base

    call mpi_type_create_struct(block_cnt, blocklengths, displacements, dtypes, imp_t_photon, ierr); call chkerr(ierr)
    call mpi_type_commit(imp_t_photon, ierr); call chkerr(ierr)
  end subroutine


  !> @brief Calculate Transfer Coefficients using MonteCarlo integration
  !> @details All MPI Nodes start photons from src stream and ray trace it including scattering events through the box until it leaves the box through one of the exit streams.\n
  !> Scattering Absorption is accounted for by carrying on a photon weight and succinctly lower it by lambert Beers Law \f$ \omega_{abso}^{'} = \omega_{abso} \cdot e^{- \rm{d}s \cdot {\rm k}_{sca}   }   \f$ \n
  !> New Photons are started until we reach a stdvariance which is lower than the given stddev in function call init_stddev. Once this precision is reached, we exit the photon loop and build the average with all the other MPI Nodes.
  subroutine get_coeff(bmc, comm, op_bg, src, ldir, &
      phi0, theta0, vertices, &
      ret_S_out, ret_T_out, &
      ret_S_tol,ret_T_tol, &
      inp_atol, inp_rtol)
    class(t_boxmc)                :: bmc             !< @param[in] bmc Raytracer Type - determines number of streams
    real(ireals),intent(in)       :: op_bg(3)        !< @param[in] op_bg optical properties have to be given as [kabs,ksca,g]
    real(ireals),intent(in)       :: phi0            !< @param[in] phi0 solar azimuth angle
    real(ireals),intent(in)       :: theta0          !< @param[in] theta0 solar zenith angle
    integer(iintegers),intent(in) :: src             !< @param[in] src stream from which to start photons - see init_photon routines
    integer(mpiint),intent(in)    :: comm            !< @param[in] comm MPI Communicator
    logical,intent(in)            :: ldir            !< @param[in] ldir determines if photons should be started with a fixed incidence angle
    real(ireals),intent(in)       :: vertices(:)     !< @param[in] vertex coordinates of box with dimensions in [m]
    real(ireals),intent(out)      :: ret_S_out(:)    !< @param[out] S_out diffuse streams transfer coefficients
    real(ireals),intent(out)      :: ret_T_out(:)    !< @param[out] T_out direct streams transfer coefficients
    real(ireals),intent(out)      :: ret_S_tol(:)    !< @param[out] absolute tolerances of results
    real(ireals),intent(out)      :: ret_T_tol(:)    !< @param[out] absolute tolerances of results
    real(ireals),intent(in),optional :: inp_atol     !< @param[in] inp_atol if given, determines targeted absolute stddeviation
    real(ireals),intent(in),optional :: inp_rtol     !< @param[in] inp_rtol if given, determines targeted relative stddeviation

    real(ireal_dp) :: S_out(bmc%diff_streams)
    real(ireal_dp) :: T_out(bmc%dir_streams)
    real(ireal_dp) :: S_tol(bmc%diff_streams)
    real(ireal_dp) :: T_tol(bmc%dir_streams)

    real(ireal_dp) :: atol,rtol, coeffnorm

    type(stddev) :: std_Sdir, std_Sdiff, std_abso

    integer(iintegers) :: Nphotons, idst, iout
    integer(mpiint) :: numnodes

    if(.not. bmc%initialized ) stop 'Box Monte Carlo Ray Tracer is not initialized! - This should not happen!'

    call mpi_comm_size(comm, numnodes, mpierr); call chkerr(mpierr)

    if(present(inp_atol)) then
      atol = inp_atol
    else
      atol = stddev_atol
    endif
    if(present(inp_rtol)) then
      rtol = inp_rtol
    else
      rtol = stddev_rtol
    endif

    call init_stddev( std_Sdir , bmc%dir_streams  ,atol, rtol )
    call init_stddev( std_Sdiff, bmc%diff_streams ,atol, rtol )
    call init_stddev( std_abso , i1               ,atol, rtol )

    if(.not.ldir) std_Sdir%converged=.True.

    if( (any(op_bg.lt.zero)) .or. (any(isnan(op_bg))) ) then
      print *,'corrupt optical properties: bg:: ',op_bg
      call exit
    endif

    call run_photons(bmc, comm, src,               &
                     real(op_bg(1),kind=ireal_dp), &
                     real(op_bg(2),kind=ireal_dp), &
                     real(op_bg(3),kind=ireal_dp), &
                     real(vertices,kind=ireal_dp), &
                     ldir,                         &
                     real(phi0,   kind=ireal_dp),  &
                     real(theta0, kind=ireal_dp),  &
                     Nphotons,                     &
                     std_Sdir, std_Sdiff, std_abso)

    S_out = std_Sdiff%mean
    T_out = std_Sdir%mean

    ! tolerances that we achieved and report them back
    S_tol = std_Sdiff%var
    T_tol = std_Sdir%var

    if(numnodes.gt.1) then ! average reduce results from all ranks
      call reduce_output(Nphotons, comm, S_out, T_out, S_tol, T_tol)
    endif

    ! some debug output at the end...
    coeffnorm = sum(S_out)+sum(T_out)
    if( coeffnorm.gt.one ) then
      if(coeffnorm.ge.one+1e-5_ireal_dp) then
        print *,'ohoh something is wrong! - sum of streams is bigger 1, this cant be due to energy conservation',&
        sum(S_out),'+',sum(T_out),'=',sum(S_out)+sum(T_out),'.gt',one,':: op',op_bg,'eps',epsilon(one)
        call exit
      else
        S_out = S_out / (coeffnorm+epsilon(coeffnorm)*10)
        T_out = T_out / (coeffnorm+epsilon(coeffnorm)*10)
        if(ldebug_optprop) print *,'renormalizing coefficients :: ',coeffnorm,' => ',sum(S_out)+sum(T_out)
      endif
      if( (sum(S_out)+sum(T_out)).gt.one ) then
        print *,'norm still too big',sum(S_out)+sum(T_out)
        call exit
      endif
    endif
    if( (any(isnan(S_out) )) .or. (any(isnan(T_out)) ) ) then
      print *,'Found a NaN in output! this should not happen! dir',T_out,'diff',S_out
      print *,'Input:', op_bg, '::', phi0, theta0, src, ldir, '::', vertices
      call exit()
    endif

    iout = 0
    do idst = 1, size(T_out)
      if(idst.eq.src .and. size(ret_T_out).eq.size(T_out)-1) cycle
      iout = iout + 1
      ret_T_out(iout) = real(T_out(idst), kind=ireals)
      ret_T_tol(iout) = real(T_tol(idst), kind=ireals)
    enddo
    ret_S_out = real(S_out, kind=ireals)
    ret_S_tol = real(S_tol, kind=ireals)
    if(ldebug) print *,'S out', ret_S_out, 'T_out', ret_T_out
    !print *,'Input:', op_bg, '::', phi0, theta0, src, ldir, '::', vertices
    !print *,'S out', ret_S_out, 'T_out', ret_T_out
  end subroutine

  subroutine run_photons(bmc, comm, src, kabs, ksca, g, vertices, &
      ldir, phi0, theta0, Nphotons, &
      std_Sdir, std_Sdiff, std_abso)
      class(t_boxmc),intent(inout) :: bmc
      integer(mpiint), intent(in) :: comm
      integer(iintegers),intent(in) :: src
      real(ireal_dp),intent(in) :: kabs, ksca, g, vertices(:),phi0,theta0
      logical,intent(in) :: ldir
      integer(iintegers) :: Nphotons
      type(stddev),intent(inout)   :: std_Sdir, std_Sdiff, std_abso

      type(t_photon)       :: p
      real(ireal_dp)     :: theta, initial_dir(3)
      real(ireal_dp)     :: time(2)
      integer(iintegers) :: k,mycnt,mincnt
      integer(mpiint)    :: numnodes, ierr

      call mpi_comm_size(comm, numnodes, mpierr); call chkerr(mpierr)
      call cpu_time(time(1))

      ! dont use zero, really, this has issues if go along a face because it is not so clear where that energy should go.
      ! In an ideal world, this should never happen in the matrix anyway but due to delta scaling and such this can very well be
      theta = max(10*sqrt(epsilon(theta)), abs(theta0)) * sign(one, theta0)
      theta = min(180-10*sqrt(epsilon(theta)), abs(theta)) * sign(one, theta)

      ! we turn the initial direction in x and y, against the convention of sun angles...
      ! i.e. here we have azimuth phi = 0, beam going towards the north
      ! and phi = 90, beam going towards east
      initial_dir = spherical_2_cartesian(phi0, theta) * [-one, -one, one]

      mincnt= max( 100, int( 1e3 /numnodes ) )
      mycnt = int(1e7)/numnodes
      mycnt = min( max(mincnt, mycnt ), huge(k)-1 )
      do k=1, mycnt

          if(k.gt.mincnt .and. all([std_Sdir%converged, std_Sdiff%converged, std_abso%converged ]) ) exit

          if(ldir) then
              call bmc%init_dir_photon(p, src, ldir, initial_dir, vertices, ierr)
          else
              call bmc%init_diff_photon(p, src, vertices, ierr)
          endif
          if(ierr.ne.0) exit

          move: do
            call bmc%move_photon(vertices, kabs, ksca, p)
            call roulette(p)

            if(.not.p%alive) exit move
            call scatter_photon(p, g)
          enddo move

          if(ldir) call refill_direct_stream(p,initial_dir)

          std_abso%inc = one-p%weight
          std_Sdir%inc  = zero
          std_Sdiff%inc = zero

          if(p%direct) then
            call bmc%update_dir_stream(vertices, p,std_Sdir%inc)
          else
            call bmc%update_diff_stream(p,std_Sdiff%inc)
          endif

          if (ldir) call std_update( std_Sdir , k, i1*numnodes )
          call std_update( std_abso , k, i1*numnodes)
          call std_update( std_Sdiff, k, i1*numnodes )
      enddo ! k photons
      Nphotons = k

      call cpu_time(time(2))

      !if(Nphotons.gt.1)then ! .and. rand().gt..99_ireal_dp) then
      !  write(*,FMT='("src ",I0," op ",3(ES12.3),"(delta",3(ES12.3),") sun(",I0,",",I0,") N_phot ",I0 ,"=>",ES12.3,"phot/sec/node took",ES12.3,"sec")') &
      !    src,op,p%optprop,int(phi0),int(theta0),Nphotons, Nphotons/max(epsilon(time),time(2)-time(1))/numnodes,time(2)-time(1)
      !endif
  end subroutine

  !> @brief take weighted average over mpi processes
  subroutine reduce_output(Nlocal, comm, S_out, T_out, S_tol, T_tol)
    integer(iintegers),intent(in) :: Nlocal
    integer(mpiint),intent(in)    :: comm
    real(ireal_dp),intent(inout)      :: S_out(:)
    real(ireal_dp),intent(inout)      :: T_out(:)
    real(ireal_dp),intent(inout)      :: S_tol(:)
    real(ireal_dp),intent(inout)      :: T_tol(:)

    real(ireal_dp) :: Nglobal
    integer(mpiint) :: myid

    call mpi_comm_rank(comm, myid, mpierr); call chkerr(mpierr)

    ! weight mean by calculated photons and compare it with results from other nodes
    Nglobal = Nlocal
    call imp_reduce_sum(comm, Nglobal, myid)

    call reduce_var(comm, Nlocal, Nglobal, S_out)
    call reduce_var(comm, Nlocal, Nglobal, T_out)
    !TODO: combining stddeviation is probably not just the arithmetic mean?
    call reduce_var(comm, Nlocal, Nglobal, S_tol)
    call reduce_var(comm, Nlocal, Nglobal, T_tol)

  contains
    subroutine reduce_var(comm, Nlocal, Nglobal, arr)
      integer(iintegers),intent(in) :: Nlocal
      real(ireal_dp),intent(in) :: Nglobal
      real(ireal_dp),intent(inout) :: arr(:)
      integer(mpiint),intent(in) :: comm
      integer(iintegers) :: k

      arr = arr*Nlocal
      do k=1,size(arr)
        call imp_reduce_sum(comm, arr(k), myid)
      enddo
      arr = arr/Nglobal
    end subroutine
  end subroutine

  !> @brief russian roulette helps to reduce computations with not much weight
  subroutine roulette(p)
    type(t_photon),intent(inout) :: p
    real(ireal_dp),parameter :: m=1e-2_ireal_dp,s=1e-3_ireal_dp*m

    if(p%weight.lt.s) then
      if(R().ge.p%weight/m) then
        p%weight=zero
        p%alive=.False.
      else
        p%weight=m
      endif
    endif
  end subroutine

  !> @brief in a ``postprocessing`` step put scattered direct radiation back into dir2dir streams
  subroutine refill_direct_stream(p,initial_dir)
    type(t_photon),intent(inout) :: p
    real(ireal_dp),intent(in) :: initial_dir(3)

    real(ireal_dp) :: angle

    angle = dot_product(initial_dir, p%dir)

    if(angle.gt.delta_scale_truncate) then
      p%direct = .True.
      !          print *,'delta scaling photon initial', initial_dir,'dir',p%dir,'angle',angle,'cos', (acos(angle))*180/pi_dp
    endif
  end subroutine

  !> @brief return equally distributed random number in [-1,1]
  function s()
    real(ireal_dp) :: s
    s = -one + 2*R()
  end function
  !> @brief return cosine of deg(in degrees)
  function deg2mu(deg)
    real(ireal_dp),intent(in) :: deg
    real(ireal_dp) :: deg2mu
    deg2mu = cos(deg2rad(deg))
  end function
  !> @brief return uniform random number between a and b
  function interv_R(a,b)
    real(ireal_dp),intent(in) :: a,b
    real(ireal_dp) :: interv_R
    real(ireal_dp) :: lb,ub

    lb=min(a,b)
    ub=max(a,b)
    interv_R = lb + R()*(ub-lb)
  end function
  !> @brief return uniform random number between [0,v] with a certain cutoff at the edges to make sure that photons are started ``inside`` a box
  function L(v)
    real(ireal_dp) :: L
    real(ireal_dp),intent(in) ::v
    real(ireal_dp),parameter :: eps=epsilon(L)*1e3_ireal_dp
    L = ( eps + R()*(one-2*eps) ) *v
  end function

  !> @brief main function for a single photon
  !> @details this routine will incrementally move a photon until it is either out of the domain or it is time for a interaction with the medium
  subroutine move_photon(bmc, vertices, kabs, ksca, p)
    class(t_boxmc) :: bmc
    real(ireal_dp), intent(in) :: vertices(:), kabs, ksca
    type(t_photon),intent(inout) :: p
    real(ireal_dp) :: dist,intersec_dist

    call bmc%intersect_distance(vertices, p, intersec_dist)

    p%tau_travel = tau(R())
    dist = distance(p%tau_travel, ksca)

    if(intersec_dist .le. dist) then
      p%alive=.False.
      call update_photon_loc(p, intersec_dist, kabs, ksca)
    else
      call update_photon_loc(p, dist, kabs, ksca)
    endif

    if(p%scattercnt.gt.1e9) then
      print *,'Scattercnt:',p%scattercnt,' -- maybe this photon got stuck? -- I will move this one out of the box but keep in mind, that this is a dirty hack i.e. absorption will be wrong!'
      call print_photon(p)
      p%alive=.False.
      call update_photon_loc(p, intersec_dist, kabs, ksca)
      call print_photon(p)
    endif

  end subroutine move_photon

  !> @brief compute physical distance according to travel_tau
  elemental function distance(tau, beta)
    real(ireal_dp),intent(in) :: tau, beta
    real(ireal_dp) :: distance
    if(approx(beta,zero) ) then
      distance = huge(distance)
    else
      distance = tau/beta
    endif
  end function

  !> @brief throw the dice for a random optical thickness -- after the corresponding dtau it is time to do some interaction
  elemental function tau(r)
    real(ireal_dp),intent(in) :: r
    real(ireal_dp) :: tau,arg
    arg = max( epsilon(arg), one-r )
    tau = -log(arg)
  end function

  !> @brief update physical location of photon and consider absorption
  subroutine update_photon_loc(p, dist, kabs, ksca)
    type(t_photon),intent(inout) :: p
    real(ireal_dp),intent(in) :: dist, kabs, ksca
    call absorb_photon(p, dist, kabs)
    p%loc = p%loc + (dist*p%dir)
    p%tau_travel = p%tau_travel - dist * ksca
    if(any(isnan(p%loc))) then
      print *,'loc is now a NAN! ',p%loc,'dist',dist
      call print_photon(p)
      call exit
    endif
  end subroutine

  !> @brief cumulative sum of henyey greenstein phase function
  elemental function hengreen(r,g)
    real(ireal_dp),intent(in) :: r,g
    real(ireal_dp) :: hengreen
    real(ireal_dp),parameter :: two=2*one
    if( approx(g,zero) ) then
      hengreen = two*r-one
    else
      hengreen = one/(two*g) * (one+g**two - ( (one-g**two) / ( two*g*r + one-g) )**two )
    endif
    hengreen = min(max(hengreen,-one), one)
  end function

  !> @brief remove photon weight due to absorption
  pure subroutine absorb_photon(p, dist, kabs)
    type(t_photon),intent(inout) :: p
    real(ireal_dp),intent(in) :: dist, kabs
    real(ireal_dp) :: new_weight,tau

    tau = kabs*dist
    if(tau.gt.30) then
      p%weight = zero
    else
      new_weight = p%weight * exp(- tau)
      p%weight = new_weight
    endif
  end subroutine

  !> @brief compute new direction of photon after scattering event
  subroutine scatter_photon(p, g)
    type(t_photon),intent(inout) :: p
    real(ireal_dp), intent(in) :: g
    real(ireal_dp) :: muxs,muys,muzs,muxd,muyd,muzd
    real(ireal_dp) :: mutheta,fi,costheta,sintheta,sinfi,cosfi,denom,muzcosfi

    mutheta = hengreen(R(), g)

    p%scattercnt = p%scattercnt+1
    p%direct=.False.

    muxs = p%dir(1)
    muys = p%dir(2)
    muzs = p%dir(3)

    fi = R()*pi_dp*2

    costheta = (mutheta)
    sintheta = sqrt(one-costheta**2)
    sinfi = sin(fi)
    cosfi = cos(fi)

    if( approx(muzs , one) ) then
      muxd = sintheta*cosfi
      muyd = sintheta*sinfi
      muzd = costheta
    else if ( approx( muzs ,-one) ) then
      muxd =  sintheta*cosfi
      muyd = -sintheta*sinfi
      muzd = -costheta
    else
      denom = sqrt(one-muzs**2)
      muzcosfi = muzs*cosfi

      muxd = sintheta*(muxs*muzcosfi-muys*sinfi)/denom + muxs*costheta
      muyd = sintheta*(muys*muzcosfi+muxs*sinfi)/denom + muys*costheta
      muzd = -denom*sintheta*cosfi + muzs*costheta
    endif

    !        if(isnan(muxd).or.isnan(muyd).or.isnan(muzd) ) print *,'new direction is NAN :( --',muxs,muys,muzs,mutheta,fi,'::',muxd,muyd,muzd

    p%dir(1) = muxd
    p%dir(2) = muyd
    p%dir(3) = muzd

  end subroutine

!  pure function get_kabs(p)
!    real(ireal_dp) :: get_kabs
!    type(t_photon),intent(in) :: p
!    get_kabs = p%optprop(1)
!  end function
!  pure function get_ksca(p)
!    real(ireal_dp) :: get_ksca
!    type(t_photon),intent(in) :: p
!    get_ksca = p%optprop(2)
!  end function
!  pure function get_g(p)
!    real(ireal_dp) :: get_g
!    type(t_photon),intent(in) :: p
!    get_g = p%optprop(3)
!  end function

  subroutine print_photon(p)
    type(t_photon),intent(in) :: p
    print *,'S---------------------------'
    print *,'Location  of Photon:',p%loc
    print *,'Direction of Photon:',p%dir
    print *,'weight',p%weight,'alive,direct',p%alive,p%direct,'scatter count',p%scattercnt
    print *,'src_side',p%src_side,'side',p%side,'src',p%src
    print *,'cellid', p%cellid, 'tau_travel', p%tau_travel
    print *,'i,j,k', p%i, p%j, p%k
    print *,'E---------------------------'
  end subroutine

  function R()
    real(ireal_dp) :: R
    real :: rvec(1)
    ! call random_number(R)
    call RANLUX(rvec,1)  ! use Luxury Pseudorandom Numbers from M. Luscher
    R = real(rvec(1), kind=ireal_dp)
  end function

  subroutine init_random_seed(myid, luse_random_seed)
    integer,intent(in) :: myid
    logical, intent(in), optional :: luse_random_seed
    INTEGER :: i, n, clock, s
    INTEGER, DIMENSION(:), ALLOCATABLE :: seed
    real :: rn
    logical :: lrand_seed

    lrand_seed = get_arg(.True., luse_random_seed)

    if(lrand_seed) then
      CALL RANDOM_SEED(size = n)
      ALLOCATE(seed(n))

      CALL SYSTEM_CLOCK(COUNT=clock)

      seed = myid*3*7*11*13*17 + clock + 37 * (/ (i - 1, i = 1, n) /)
      CALL RANDOM_SEED(PUT = seed)

      DEALLOCATE(seed)

      call random_number(rn)
      s = int(rn*1000)*(myid+1)

      call RLUXGO(4, int(s), 0, 0) ! seed ranlux rng
    else
      call RLUXGO(4, int(myid), 0, 0) ! seed ranlux rng
    endif
    lRNGseeded=.True.
  end subroutine
  subroutine init_stddev( std, N, atol, rtol)
    type(stddev),intent(inout) :: std
    real(ireal_dp),intent(in) :: atol,rtol
    integer(iintegers) :: N
    if( allocated(std%inc     ) ) deallocate( std%inc  )
    if( allocated(std%delta   ) ) deallocate( std%delta)
    if( allocated(std%mean    ) ) deallocate( std%mean )
    if( allocated(std%mean2   ) ) deallocate( std%mean2)
    if( allocated(std%var     ) ) deallocate( std%var  )
    if( allocated(std%relvar  ) ) deallocate( std%relvar)
    allocate( std%inc   (N)) ; std%inc   = zero
    allocate( std%delta (N)) ; std%delta = zero
    allocate( std%mean  (N)) ; std%mean  = zero
    allocate( std%mean2 (N)) ; std%mean2 = zero
    allocate( std%var   (N)) ; std%var   = zero
    allocate( std%relvar(N)) ; std%relvar= zero
    std%atol = atol
    std%rtol = rtol
    std%converged = .False.
  end subroutine

  pure subroutine std_update(std, N, numnodes)
    type(stddev),intent(inout) :: std
    integer(iintegers),intent(in) :: N, numnodes
    real(ireal_dp),parameter :: relvar_limit=1e-4_ireal_dp

    std%delta = std%inc   - std%mean
    std%mean  = std%mean  + std%delta/N
    std%mean2 = std%mean2 + std%delta * ( std%inc - std%mean )
    std%var = sqrt( std%mean2/N ) / sqrt( one*N*numnodes )
    where(std%mean.gt.max(std%atol, relvar_limit))
      std%relvar = std%var / std%mean
    elsewhere
      std%relvar = zero ! .1_ireal_dp/sqrt(one*N) ! consider adding a photon weight of .1 as worst case that could happen for the next update...
    end where

    if( all( (std%var .lt. std%atol) .and. (std%relvar .lt. std%rtol) ) ) then
      std%converged = .True.
    else
      std%converged = .False.
    endif
  end subroutine

  subroutine init(bmc, comm, rngseed, luse_random_seed)
    class(t_boxmc) :: bmc
    integer(mpiint),intent(in) :: comm
    integer(mpiint),intent(in), optional :: rngseed
    logical, intent(in), optional :: luse_random_seed
    integer(mpiint) :: myid, seed

    if(comm.eq.-1) then
      myid = -1
    else
      call MPI_Comm_rank(comm, myid, mpierr); call CHKERR(mpierr)
    endif

    seed = get_arg(myid+2, rngseed)

    if(.not.lRNGseeded) call init_random_seed(seed, luse_random_seed)

    select type (bmc)
    type is (t_boxmc_8_10)
    bmc%dir_streams  =  8
    bmc%diff_streams = 10
    type is (t_boxmc_3_10)
    bmc%dir_streams  =  3
    bmc%diff_streams = 10
    type is (t_boxmc_1_2)
    bmc%dir_streams  =  1
    bmc%diff_streams =  2
    type is (t_boxmc_3_6)
    bmc%dir_streams = 3
    bmc%diff_streams = 6
    type is (t_boxmc_wedge_5_5)
    bmc%dir_streams  =  5
    bmc%diff_streams =  5
    type is (t_boxmc_wedge_5_8)
    bmc%dir_streams  =  5
    bmc%diff_streams =  8
    class default
    stop 'initialize: unexpected type for boxmc object!'
  end select

  call gen_mpi_photon_type()

  bmc%initialized = .True.
end subroutine


include 'boxmc_8_10.inc'
include 'boxmc_3_10.inc'
include 'boxmc_1_2.inc'
include 'boxmc_3_6.inc'
include 'boxmc_wedge_5_5.inc'
include 'boxmc_wedge_5_8.inc'

end module
