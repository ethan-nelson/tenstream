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

module m_helper_functions
  use m_data_parameters,only : iintegers, mpiint, ireals, ireal_dp, &
    i1, pi, zero, one, imp_real, imp_int, imp_logical

  use mpi

  implicit none

  private
  public imp_bcast,norm,cross_2d, cross_3d,rad2deg,deg2rad,rmse,mean,approx,rel_approx,delta_scale_optprop,delta_scale,cumsum,    &
    inc, mpi_logical_and,mpi_logical_or,imp_allreduce_min,imp_allreduce_max,imp_reduce_sum, search_sorted_bisection, &
    gradient, read_ascii_file_2d, meanvec, swap, imp_allgather_int_inplace, reorder_mpi_comm, CHKERR,                &
    compute_normal_3d, determine_normal_direction, spherical_2_cartesian, angle_between_two_vec, hit_plane,          &
    pnt_in_triangle, distance_to_edge, rotation_matrix_world_to_local_basis, rotation_matrix_local_basis_to_world,   &
    vec_proj_on_plane, get_arg, unique, itoa, triangle_intersection, square_intersection

  interface mean
    module procedure mean_1d, mean_2d
  end interface
  interface imp_bcast
    module procedure imp_bcast_real_1d, imp_bcast_real_2d, imp_bcast_real_3d, imp_bcast_real_5d, &
        imp_bcast_int_1d, imp_bcast_int_2d, imp_bcast_int4, imp_bcast_int8, imp_bcast_real, imp_bcast_logical
  end interface
  interface get_arg
    module procedure get_arg_logical, get_arg_iintegers, get_arg_ireals
  end interface
  interface swap
    module procedure swap_iintegers, swap_ireals
  end interface
  interface cumsum
    module procedure cumsum_iintegers, cumsum_ireals
  end interface

  integer(mpiint) :: mpierr

  contains
    pure elemental subroutine swap_ireals(x,y)
      real(ireals),intent(inout) :: x,y
      real(ireals) :: tmp
      tmp = x
      x = y
      y = tmp
    end subroutine
    pure elemental subroutine swap_iintegers(x,y)
      integer(iintegers),intent(inout) :: x,y
      integer(iintegers) :: tmp
      tmp = x
      x = y
      y = tmp
    end subroutine
    pure elemental subroutine inc(x,i)
      real(ireals),intent(inout) :: x
      real(ireals),intent(in) :: i
      x=x+i
    end subroutine

    subroutine CHKERR(ierr)
      integer(mpiint),intent(in) :: ierr
      if(ierr.ne.0) call mpi_abort(mpi_comm_world, ierr, mpierr)
    end subroutine

    function itoa(i) result(res)
      character(:),allocatable :: res
      integer(iintegers),intent(in) :: i
      character(range(i)+2) :: tmp
      write(tmp,'(i0)') i
      res = trim(tmp)
    end function

    pure function gradient(v)
      real(ireals),intent(in) :: v(:)
      real(ireals) :: gradient(size(v)-1)
      gradient = v(2:size(v))-v(1:size(v)-1)
    end function

    pure function meanvec(v)
      real(ireals),intent(in) :: v(:)
      real(ireals) :: meanvec(size(v)-1)
      meanvec = (v(2:size(v))+v(1:size(v)-1))*.5_ireals
    end function

    pure function norm(v)
      real(ireals) :: norm
      real(ireals),intent(in) :: v(:)
      norm = sqrt(dot_product(v,v))
    end function

    pure function cross_3d(a, b)
      real(ireals), dimension(3), intent(in) :: a, b
      real(ireals), dimension(3) :: cross_3d

      cross_3d(1) = a(2) * b(3) - a(3) * b(2)
      cross_3d(2) = a(3) * b(1) - a(1) * b(3)
      cross_3d(3) = a(1) * b(2) - a(2) * b(1)
    end function cross_3d

    pure function cross_2d(a, b)
      real(ireals), dimension(2), intent(in) :: a, b
      real(ireals) :: cross_2d

      cross_2d = a(1) * b(2) - a(2) * b(1)
    end function cross_2d


    elemental function deg2rad(deg)
      real(ireals) :: deg2rad
      real(ireals),intent(in) :: deg
      deg2rad = deg * pi / 180
    end function
    elemental function rad2deg(rad)
      real(ireals) :: rad2deg
      real(ireals),intent(in) :: rad
      rad2deg = rad / pi * 180
    end function

    pure function rmse(a,b)
      real(ireals) :: rmse(2)
      real(ireals),intent(in) :: a(:),b(:)
      rmse(1) = sqrt( mean( (a-b)**2 ) )
      rmse(2) = rmse(1)/max( mean(b), epsilon(rmse) )
    end function

    pure function mean_1d(arr)
      real(ireals) :: mean_1d
      real(ireals),intent(in) :: arr(:)
      mean_1d = sum(arr)/size(arr)
    end function
    pure function mean_2d(arr)
      real(ireals) :: mean_2d
      real(ireals),intent(in) :: arr(:,:)
      mean_2d = sum(arr)/size(arr)
    end function

    elemental logical function approx(a,b,precision)
      real(ireals),intent(in) :: a,b
      real(ireals),intent(in),optional :: precision
      real(ireals) :: factor
      if(present(precision) ) then
        factor = precision
      else
        factor = 10._ireals*epsilon(b)
      endif
      if( a.le.b+factor .and. a.ge.b-factor ) then
        approx = .True.
      else
        approx = .False.
      endif
    end function
    elemental logical function rel_approx(a,b,precision)
      real(ireals),intent(in) :: a,b
      real(ireals),intent(in),optional :: precision
      real(ireals) :: factor,rel_error
      if(present(precision) ) then
        factor = precision
      else
        factor = 10*epsilon(b)
      endif
      rel_error = abs( (a-b)/ max(epsilon(a), ( (a+b)*.5_ireals ) ) )

      if( rel_error .lt. precision ) then
        rel_approx = .True.
      else
        rel_approx = .False.
      endif
    end function

    function mpi_logical_and(comm,lval)
      integer(mpiint),intent(in) :: comm
      logical :: mpi_logical_and
      logical,intent(in) :: lval
      call mpi_allreduce(lval, mpi_logical_and, 1_mpiint, imp_logical, MPI_LAND, comm, mpierr); call CHKERR(mpierr)
    end function
    function mpi_logical_or(comm,lval)
      integer(mpiint),intent(in) :: comm
      logical :: mpi_logical_or
      logical,intent(in) :: lval
      call mpi_allreduce(lval, mpi_logical_or, 1_mpiint, imp_logical, MPI_LOR, comm, mpierr); call CHKERR(mpierr)
    end function

    subroutine imp_allreduce_min(comm,v,r)
      integer(mpiint),intent(in) :: comm
      real(ireals),intent(in) :: v
      real(ireals),intent(out) :: r
      call mpi_allreduce(v,r,1_mpiint,imp_real, MPI_MIN,comm, mpierr); call CHKERR(mpierr)
    end subroutine
    subroutine imp_allreduce_max(comm,v,r)
      integer(mpiint),intent(in) :: comm
      real(ireals),intent(in) :: v
      real(ireals),intent(out) :: r
      call mpi_allreduce(v,r,1_mpiint,imp_real, MPI_MAX,comm, mpierr); call CHKERR(mpierr)
    end subroutine
    subroutine imp_reduce_sum(comm,v)
      real(ireals),intent(inout) :: v
      integer(mpiint),intent(in) :: comm
      integer(mpiint) :: commsize, myid
      call MPI_Comm_size( comm, commsize, mpierr); call CHKERR(mpierr)
      if(commsize.le.1) return
      call MPI_Comm_rank( comm, myid, mpierr); call CHKERR(mpierr)

      if(myid.eq.0) then
        call mpi_reduce(MPI_IN_PLACE, v, 1_mpiint, imp_real, MPI_SUM, 0_mpiint, comm, mpierr); call CHKERR(mpierr)
      else
        call mpi_reduce(v, MPI_IN_PLACE, 1_mpiint, imp_real, MPI_SUM, 0_mpiint, comm, mpierr); call CHKERR(mpierr)
      endif
    end subroutine

    subroutine imp_allgather_int_inplace(comm,v)
      integer(mpiint),intent(in) :: comm
      integer(iintegers),intent(inout) :: v(:)
      call mpi_allgather(MPI_IN_PLACE, 0_mpiint, MPI_DATATYPE_NULL, v, 1_mpiint, imp_int, comm, mpierr); call CHKERR(mpierr)
    end subroutine

    subroutine  imp_bcast_logical(comm,val,sendid)
      integer(mpiint),intent(in) :: comm
      logical,intent(inout) :: val
      integer(mpiint),intent(in) :: sendid
      integer(mpiint) :: commsize
      call MPI_Comm_size( comm, commsize, mpierr); call CHKERR(mpierr)
      if(commsize.le.1) return

      call mpi_bcast(val, 1_mpiint, imp_logical, sendid, comm, mpierr); call CHKERR(mpierr)
    end subroutine
    subroutine  imp_bcast_int4(comm,val,sendid)
      integer(mpiint),intent(in) :: comm
      integer(kind=4),intent(inout) :: val
      integer(mpiint),intent(in) :: sendid
      integer(mpiint) :: commsize
      call MPI_Comm_size( comm, commsize, mpierr); call CHKERR(mpierr)
      if(commsize.le.1) return

      call mpi_bcast(val,1_mpiint,imp_int,sendid,comm,mpierr); call CHKERR(mpierr)
    end subroutine
    subroutine  imp_bcast_int8(comm,val,sendid)
      integer(mpiint),intent(in) :: comm
      integer(kind=8),intent(inout) :: val
      integer(mpiint),intent(in) :: sendid
      integer(mpiint) :: commsize
      call MPI_Comm_size( comm, commsize, mpierr); call CHKERR(mpierr)
      if(commsize.le.1) return

      call mpi_bcast(val,1_mpiint,imp_int,sendid,comm,mpierr); call CHKERR(mpierr)
    end subroutine
    subroutine  imp_bcast_int_1d(comm,arr,sendid)
      integer(mpiint),intent(in) :: comm
      integer(iintegers),allocatable,intent(inout) :: arr(:)
      integer(mpiint),intent(in) :: sendid
      integer(mpiint) :: myid

      integer(iintegers) :: Ntot
      integer(mpiint) :: commsize
      call MPI_Comm_size( comm, commsize, mpierr); call CHKERR(mpierr)
      if(commsize.le.1) return
      call MPI_Comm_rank( comm, myid, mpierr); call CHKERR(mpierr)

      if(sendid.eq.myid) Ntot = size(arr)
      call mpi_bcast(Ntot,1_mpiint,imp_int,sendid,comm,mpierr); call CHKERR(mpierr)

      if(myid.ne.sendid) allocate( arr(Ntot) )
      call mpi_bcast(arr,size(arr),imp_int,sendid,comm,mpierr); call CHKERR(mpierr)
    end subroutine
    subroutine  imp_bcast_int_2d(comm,arr,sendid)!
      integer(mpiint),intent(in) :: comm
      integer(iintegers),allocatable,intent(inout) :: arr(:,:)
      integer(mpiint),intent(in) :: sendid
      integer(mpiint) :: myid

      integer(iintegers) :: Ntot(2)
      integer(mpiint) :: commsize
      call MPI_Comm_size( comm, commsize, mpierr); call CHKERR(mpierr)
      call MPI_Comm_rank( comm, myid, mpierr); call CHKERR(mpierr)
      if(commsize.le.1) return

      if(sendid.eq.myid) Ntot = shape(arr)
      call mpi_bcast(Ntot,2_mpiint,imp_int,sendid,comm,mpierr); call CHKERR(mpierr)

      if(myid.ne.sendid) allocate( arr(Ntot(1), Ntot(2)) )
      call mpi_bcast(arr,size(arr),imp_int,sendid,comm,mpierr); call CHKERR(mpierr)
    end subroutine
    subroutine  imp_bcast_real(comm,val,sendid)
      integer(mpiint),intent(in) :: comm
      real(ireals),intent(inout) :: val
      integer(mpiint),intent(in) :: sendid
      integer(mpiint) :: commsize
      call MPI_Comm_size( comm, commsize, mpierr); call CHKERR(mpierr)
      if(commsize.le.1) return

      call mpi_bcast(val,1_mpiint,imp_real,sendid,comm,mpierr); call CHKERR(mpierr)
    end subroutine
    subroutine  imp_bcast_real_1d(comm,arr,sendid)
      integer(mpiint),intent(in) :: comm
      real(ireals),allocatable,intent(inout) :: arr(:)
      integer(mpiint),intent(in) :: sendid
      integer(mpiint) :: myid

      integer(iintegers) :: Ntot
      integer(mpiint) :: commsize
      call MPI_Comm_size( comm, commsize, mpierr); call CHKERR(mpierr)
      if(commsize.le.1) return
      call MPI_Comm_rank( comm, myid, mpierr); call CHKERR(mpierr)

      if(sendid.eq.myid) Ntot = size(arr)
      call mpi_bcast(Ntot,1_mpiint,imp_int,sendid,comm,mpierr); call CHKERR(mpierr)

      if(myid.ne.sendid) allocate( arr(Ntot) )
      call mpi_bcast(arr,size(arr),imp_real,sendid,comm,mpierr); call CHKERR(mpierr)
    end subroutine

    subroutine  imp_bcast_real_2d(comm,arr,sendid)
      integer(mpiint),intent(in) :: comm
      real(ireals),allocatable,intent(inout) :: arr(:,:)
      integer(mpiint),intent(in) :: sendid
      integer(mpiint) :: myid

      integer(iintegers) :: Ntot(2)
      integer(mpiint) :: commsize
      call MPI_Comm_size( comm, commsize, mpierr); call CHKERR(mpierr)
      if(commsize.le.1) return
      call MPI_Comm_rank( comm, myid, mpierr); call CHKERR(mpierr)

      if(sendid.eq.myid) Ntot = shape(arr)
      call mpi_bcast(Ntot,2_mpiint,imp_int,sendid,comm,mpierr); call CHKERR(mpierr)

      if(myid.ne.sendid) allocate( arr(Ntot(1), Ntot(2)) )
      call mpi_bcast(arr,size(arr),imp_real,sendid,comm,mpierr); call CHKERR(mpierr)
    end subroutine
    subroutine  imp_bcast_real_3d(comm,arr,sendid)
      integer(mpiint),intent(in) :: comm
      real(ireals),allocatable,intent(inout) :: arr(:,:,:)
      integer(mpiint),intent(in) :: sendid
      integer(mpiint) :: myid

      integer(iintegers) :: Ntot(3)
      integer(mpiint) :: commsize
      call MPI_Comm_size( comm, commsize, mpierr); call CHKERR(mpierr)
      if(commsize.le.1) return
      call MPI_Comm_rank( comm, myid, mpierr); call CHKERR(mpierr)

      if(sendid.eq.myid) Ntot = shape(arr)
      call mpi_bcast(Ntot,3_mpiint,imp_int,sendid,comm,mpierr); call CHKERR(mpierr)

      if(myid.ne.sendid) allocate( arr(Ntot(1), Ntot(2), Ntot(3) ) )
      call mpi_bcast(arr,size(arr),imp_real,sendid,comm,mpierr); call CHKERR(mpierr)
    end subroutine
    subroutine  imp_bcast_real_5d(comm,arr,sendid)
      integer(mpiint),intent(in) :: comm
      real(ireals),allocatable,intent(inout) :: arr(:,:,:,:,:)
      integer(mpiint),intent(in) :: sendid
      integer(mpiint) :: myid

      integer(iintegers) :: Ntot(5)
      integer(mpiint) :: commsize
      call MPI_Comm_size(comm, commsize, mpierr); call CHKERR(mpierr)
      if(commsize.le.1) return
      call MPI_Comm_rank( comm, myid, mpierr); call CHKERR(mpierr)

      if(sendid.eq.myid) Ntot = shape(arr)
      call mpi_bcast(Ntot,5_mpiint,imp_int,sendid,comm,mpierr); call CHKERR(mpierr)

      if(myid.ne.sendid) allocate( arr(Ntot(1), Ntot(2), Ntot(3), Ntot(4), Ntot(5) ) )
      call mpi_bcast(arr,size(arr),imp_real,sendid,comm,mpierr); call CHKERR(mpierr)
    end subroutine

    elemental subroutine delta_scale( kabs,ksca,g,factor ) 
      real(ireals),intent(inout) :: kabs,ksca,g ! kabs, ksca, g
      real(ireals),intent(in),optional :: factor
      real(ireals) :: dtau, w0
      dtau = max( kabs+ksca, epsilon(dtau) )
      w0   = ksca/dtau
      g    = g

      if(present(factor)) then
        call delta_scale_optprop( dtau, w0, g, factor)
      else
        call delta_scale_optprop( dtau, w0, g)
      endif

      kabs= dtau * (one-w0)
      ksca= dtau * w0
    end subroutine
    elemental subroutine delta_scale_optprop( dtau, w0, g,factor) 
      real(ireals),intent(inout) :: dtau,w0,g
      real(ireals),intent(in),optional :: factor
      real(ireals) :: f

      g = min( g, one-epsilon(g)*10)
      if(present(factor)) then
        f = factor
      else
        f = g**2
      endif
      dtau = dtau * ( one - w0 * f )
      g    = ( g - f ) / ( one - f )
      w0   = w0 * ( one - f ) / ( one - f * w0 )
    end subroutine

    function cumsum_ireals(arr) result(cumsum)
      real(ireals),intent(in) :: arr(:)
      real(ireals) :: cumsum(size(arr))
      integer :: i
      cumsum(1) = arr(1)
      do i=2,size(arr)
        cumsum(i) = cumsum(i-1) + arr(i)
      enddo
    end function
    function cumsum_iintegers(arr) result(cumsum)
      integer(iintegers),intent(in) :: arr(:)
      integer(iintegers) :: cumsum(size(arr))
      integer :: i
      cumsum(1) = arr(1)
      do i=2,size(arr)
        cumsum(i) = cumsum(i-1) + arr(i)
      enddo
    end function

    subroutine read_ascii_file_2d(filename, arr, ncolumns, skiplines, ierr)
      character(len=*),intent(in) :: filename
      integer(iintegers),intent(in) :: ncolumns
      integer(iintegers),intent(in),optional :: skiplines

      real(ireals),allocatable,intent(out) :: arr(:,:)

      integer(mpiint) :: ierr

      real :: line(ncolumns)

      integer(iintegers) :: unit, nlines, i, io
      logical :: file_exists=.False.

      ierr=0
      inquire(file=filename, exist=file_exists)

      if(.not.file_exists) then
        print *,'File ',trim(filename), 'does not exist!'
        ierr=1
        return
      endif

      open(newunit=unit, file=filename)
      if(present(skiplines)) then
        do i=1,skiplines
          read(unit,*)
        enddo
      endif

      nlines = 0
      do
        read(unit, *, iostat=io) line
        !print *,'line',line
        if (io/=0) exit
        nlines = nlines + 1
      end do

      rewind(unit)
      if(present(skiplines)) then
        do i=1,skiplines
          read(unit,*)
        enddo
      endif

      allocate(arr(nlines,ncolumns))

      do i=1,nlines
        read(unit, *, iostat=io) line
        arr(i,:) = line
      end do

      close(unit)
      print *,'I read ',nlines,'lines'
    end subroutine

    function search_sorted_bisection(arr,val) ! return index+residula i where val is between arr(i) and arr(i+1)
      real(ireals) :: search_sorted_bisection
      real(ireals),intent(in) :: arr(:)
      real(ireals),intent(in) :: val
      real(ireals) :: loc_increment
      integer(iintegers) :: i,j,k

      i=lbound(arr,1)
      j=ubound(arr,1)

      if(arr(i).le.arr(j)) then ! ascending order
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
            return
          endif
        end do
      else !descending order

        do
          k=(i+j)/2
          if (val > arr(k)) then
            j=k
          else
            i=k
          endif
          if (i+1 >= j) then ! only single or tuple left
            ! i is left bound and j is right bound index
            if(i.eq.j) then
              loc_increment = zero
            else
              loc_increment = (val - arr(j)) / ( arr(i) - arr(j) )
            endif
            search_sorted_bisection= min(max(one*lbound(arr,1), j - loc_increment), one*ubound(arr,1)) ! return `real-numbered` location of val
            return
          endif
        end do
      endif
    end function

    subroutine reorder_mpi_comm(icomm, Nrank_x, Nrank_y, new_comm)
      integer(mpiint), intent(in) :: icomm
      integer(mpiint), intent(out) :: new_comm
      integer(mpiint) :: Nrank_x, Nrank_y

      ! This is the code snippet from Petsc FAQ to change from PETSC (C) domain splitting to MPI(Fortran) domain splitting
      ! the numbers of processors per direction are (int) x_procs, y_procs, z_procs respectively
      ! (no parallelization in direction 'dir' means dir_procs = 1)

      integer(mpiint) :: x,y
      integer(mpiint) :: orig_id, petsc_id ! id according to fortran decomposition

      call MPI_COMM_RANK( icomm, orig_id, mpierr ); call CHKERR(mpierr)

      ! calculate coordinates of cpus in MPI ordering:
      x = int(orig_id) / Nrank_y
      y = modulo(orig_id ,Nrank_y)

      ! set new rank according to PETSc ordering:
      petsc_id = y*Nrank_x + x

      ! create communicator with new ranks according to PETSc ordering:
      call MPI_Comm_split(icomm, 1_mpiint, petsc_id, new_comm, mpierr)

      !print *,'Reordering communicator'
      !print *,'setup_petsc_comm: MPI_COMM_WORLD',orig_id,'calc_id',petsc_id
    end subroutine

    pure function compute_normal_3d(p1,p2,p3)
      ! for a triangle p1, p2, p3, if the vector U = p2 - p1 and the vector V = p3 - p1 then the normal
      ! N = U X V and can be calculated by:
      real(ireals), intent(in) :: p1(3), p2(3), p3(3)
      real(ireals) :: compute_normal_3d(3)
      real(ireals) :: U(3), V(3)

      U = p2-p1
      V = p3-p1

      compute_normal_3d = cross_3d(U,V)

      compute_normal_3d = compute_normal_3d / norm(compute_normal_3d)
    end function

    pure function determine_normal_direction(normal, center_face, center_cell)
      ! return 1 if normal is pointing towards cell_center, -1 if its pointing
      ! away from it
      real(ireals), intent(in) :: normal(3), center_face(3), center_cell(3)
      integer(iintegers) :: determine_normal_direction
      real(ireals) :: dot
      dot = dot_product(normal, center_cell - center_face)
      determine_normal_direction = int(sign(one, dot), kind=iintegers)
    end function

    !> @brief For local azimuth and zenith angles, return the local cartesian vectors phi azimuth, theta zenith angles, angles are input in degrees.
    !> @details theta == 0 :: z = -1, i.e. downward
    !> @details azimuth == 0 :: vector going toward minus y, i.e. sun shines from the north
    !> @details azimuth == 90 :: vector going toward minus x, i.e. sun shines from the east
    pure function spherical_2_cartesian(phi, theta, r)
      real(ireals), intent(in) :: phi, theta
      real(ireals), intent(in), optional :: r

      real(ireals) :: spherical_2_cartesian(3)

      spherical_2_cartesian(1) = -sin(deg2rad(theta)) * sin(deg2rad(phi))
      spherical_2_cartesian(2) = -sin(deg2rad(theta)) * cos(deg2rad(phi))
      spherical_2_cartesian(3) = -cos(deg2rad(theta))

      if(present(r)) spherical_2_cartesian = spherical_2_cartesian*r
    end function

    function angle_between_two_vec(p1, p2)
      real(ireals),intent(in) :: p1(:), p2(:)
      real(ireals) :: angle_between_two_vec
      real(ireals) :: n1, n2
      if(all(approx(p1,p2))) then ! if p1 and p2 are the same, just return
        angle_between_two_vec = 0
        return
      endif
      n1 = norm(p1)
      n2 = norm(p2)
      if(any([n1,n2].eq.0)) then
        print *,'FPE exception angle_between_two_vec :: ',p1,':',p2
      endif
      angle_between_two_vec = acos(dot_product(p1/norm(p1), p2/norm(p2)))
    end function

    !> @brief determine distance where a photon p intersects with a plane
    !> @details inputs are the location and direction of a photon aswell as the origin and surface normal of the plane
    pure function hit_plane(p_loc, p_dir, po, pn)
      real(ireals) :: hit_plane
      real(ireals),intent(in) :: p_loc(3), p_dir(3)
      real(ireals),intent(in) :: po(3), pn(3)
      real(ireals) :: discr
      discr = dot_product(p_dir,pn)
      if( ( discr.le. epsilon(discr) ) .and. ( discr.gt.-epsilon(discr)  ) ) then
        hit_plane = huge(hit_plane)
      else
        hit_plane = dot_product(po-p_loc, pn) / discr
      endif
    end function

    !> @brief determine if point is inside a triangle p1,p2,p3
    function pnt_in_triangle(p1,p2,p3, p)
      real(ireals), intent(in), dimension(2) :: p1,p2,p3, p
      logical :: pnt_in_triangle
      real(ireals),parameter :: eps = epsilon(eps), eps2 = 100*eps
      real(ireals) :: a, b, c, edge_dist
      logical, parameter :: ldebug=.False.

      ! First check on rectangular bounding box
      if ( p(1).lt.minval([p1(1),p2(1),p3(1)])-eps2 .or. p(1).gt.maxval([p1(1),p2(1),p3(1)])+eps2 ) then ! outside of xrange
        pnt_in_triangle=.False.
        if(ldebug) print *,'pnt_in_triangle, bounding box check failed:', p
        return
      endif
      if ( p(2).lt.minval([p1(2),p2(2),p3(2)])-eps2 .or. p(2).gt.maxval([p1(2),p2(2),p3(2)])+eps2 ) then ! outside of yrange
        pnt_in_triangle=.False.
        if(ldebug) print *,'pnt_in_triangle, bounding box check failed:', p
        return
      endif

      ! Then check for sides
      a = ((p2(2)- p3(2))*(p(1) - p3(1)) + (p3(1) - p2(1))*(p(2) - p3(2))) / ((p2(2) - p3(2))*(p1(1) - p3(1)) + (p3(1) - p2(1))*(p1(2) - p3(2)))
      b = ((p3(2) - p1(2))*(p(1) - p3(1)) + (p1(1) - p3(1))*(p(2) - p3(2))) / ((p2(2) - p3(2))*(p1(1) - p3(1)) + (p3(1) - p2(1))*(p1(2) - p3(2)))
      c = one - (a + b)

      pnt_in_triangle = all([a,b,c].ge.zero)

      if(.not.pnt_in_triangle) then ! Compute distances to each edge and allow the check to be positive if the distance is small
        edge_dist = distance_to_triangle_edges(p1,p2,p3,p)
        if(edge_dist.le.sqrt(eps)) pnt_in_triangle=.True.
      endif
      if(ldebug) print *,'pnt_in_triangle final:', pnt_in_triangle,'::',a,b,c,':',p,'edgedist',distance_to_triangle_edges(p1,p2,p3,p),distance_to_triangle_edges(p1,p2,p3,p).le.eps
    end function

    pure function distance_to_triangle_edges(p1,p2,p3,p)
      real(ireals), intent(in), dimension(2) :: p1,p2,p3, p
      real(ireals) :: distance_to_triangle_edges
      distance_to_triangle_edges = distance_to_edge(p1,p2,p)
      distance_to_triangle_edges = min(distance_to_triangle_edges, distance_to_edge(p2,p3,p))
      distance_to_triangle_edges = min(distance_to_triangle_edges, distance_to_edge(p1,p3,p))
    end function

    pure function distance_to_edge(p1,p2,p)
      real(ireals), intent(in), dimension(2) :: p1,p2, p
      real(ireals) :: distance_to_edge

      distance_to_edge = abs( (p2(2)-p1(2))*p(1) - (p2(1)-p1(1))*p(2) + p2(1)*p1(2) - p2(2)*p1(1) ) / norm(p2-p1)
    end function

    subroutine square_intersection(origin, direction, tA, tB, tC, tD, lhit, hit)
      real(ireals), intent(in) :: origin(:), direction(:), tA(:), tB(:), tC(:), tD(:)
      logical, intent(out) :: lhit
      real(ireals), intent(out) :: hit(:)

      lhit = .False.
      hit = huge(hit)

      ! 2 Triangles incorporating, cut along (AC)
      call triangle_intersection(origin, direction, tA, tC, tB, lhit, hit)
      if(lhit) return
      call triangle_intersection(origin, direction, tA, tC, tD, lhit, hit)
      if(lhit) return
    end subroutine

    ! Watertight ray -> triangle intersection code from http://jcgt.org/published/0002/01/05/
    subroutine triangle_intersection(origin, direction, tA, tB, tC, lhit, hit)
      real(ireals), intent(in) :: origin(:), direction(:), tA(:), tB(:), tC(:)
      logical, intent(out) :: lhit
      real(ireals), intent(out) :: hit(:)

      logical, parameter :: ldebug = .False. , BACKFACE_CULLING=.False., HIT_EDGE=.True.

      real(ireals) :: org(0:2), dir(0:2), A(0:2), B(0:2), C(0:2)
      integer(iintegers) :: kx, ky, kz
      real(ireals) :: Sx, Sy, Sz
      real(ireals) :: Ax, Ay, Bx, By, Cx, Cy
      real(ireals) :: Az, Bz, Cz, T
      real(ireals) :: U, V, W
      real(ireals) :: b0, b1, b2
      real(ireal_dp) :: CxBy, CyBx, AxCy, AyCx, BxAy, ByAx
      real(ireals) :: det, rcpDet

      lhit = .False.
      hit = huge(hit)

      org = origin
      dir = direction

      if(ldebug) print *,'initial direction:', dir
      if(ldebug) print *,'initial origin   :', origin
      if(ldebug) print *,'Triangle coord   :', tA
      if(ldebug) print *,'Triangle coord   :', tB
      if(ldebug) print *,'Triangle coord   :', tC
      ! calculate dimension where the ray direction is maximal (C indexing)
      kz = maxloc(abs(dir), dim=1)-1
      kx = kz+1; if (kx == 3) kx = 0
      ky = kx+1; if (ky == 3) ky = 0
      if(ldebug) print *,'max direction:', kx, ky, kz

      ! swap kx and ky dimension to preserve winding direction of triangles
      if (dir(kz) < zero) call swap(kx, ky)
      if(ldebug) print *,'max direction after swap:', kx, ky, kz
      if(ldebug) print *,'principal direction:', dir(kx), dir(ky), dir(kz)

      ! calculate shear constants
      Sx = dir(kx) / dir(kz)
      Sy = dir(ky) / dir(kz)
      Sz = one / dir(kz)
      if(ldebug) print *,'Shear constants:', Sx, Sy, Sz

      ! calculate vertices relative to ray origin
      A = tA-origin
      B = tB-origin
      C = tC-origin
      if(ldebug) print *,'relative Triangle coords A:', A
      if(ldebug) print *,'relative Triangle coords B:', B
      if(ldebug) print *,'relative Triangle coords C:', C


      ! perform shear and scale of vertices
      Ax = A(kx) - Sx*A(kz)
      Ay = A(ky) - Sy*A(kz)
      Bx = B(kx) - Sx*B(kz)
      By = B(ky) - Sy*B(kz)
      Cx = C(kx) - Sx*C(kz)
      Cy = C(ky) - Sy*C(kz)
      if(ldebug) print *,'local Triangle coords A:', Ax, Ay
      if(ldebug) print *,'local Triangle coords B:', Bx, By
      if(ldebug) print *,'local Triangle coords C:', Cx, Cy

      ! calculate scaled barycentric coordinates
      U = Cx*By - Cy*Bx;
      V = Ax*Cy - Ay*Cx;
      W = Bx*Ay - By*Ax;

      if(ldebug) print *,'Barycentric coords:', U, V, W

      ! fall back to test against edges using double precision
      if(ireals.lt.ireal_dp) then
        if (U.eq.zero .or. V.eq.zero .or. W.eq.zero) then
          CxBy = real(Cx, kind=ireal_dp) * real(By, kind=ireal_dp)
          CyBx = real(Cy, kind=ireal_dp) * real(Bx, kind=ireal_dp)
          U = real(CxBy - CyBx, kind=ireals)
          AxCy = real(Ax, kind=ireal_dp) * real(Cy, kind=ireal_dp)
          AyCx = real(Ay, kind=ireal_dp) * real(Cx, kind=ireal_dp)
          V = real(AxCy - AyCx, kind=ireals)
          BxAy = real(Bx, kind=ireal_dp) * real(Ay, kind=ireal_dp)
          ByAx = real(By, kind=ireal_dp) * real(Ax, kind=ireal_dp)
          W = real(BxAy - ByAx, kind=ireals)
        endif
      endif

      !Perform edge tests. Moving this test before and at the end of the previous conditional gives higher performance.
      if(BACKFACE_CULLING) then
        if (U < zero .or. V < zero .or. W < zero) return
      else
        if ((U < zero .or. V < zero .or. W < zero) .and. &
          (U > zero .or. V > zero .or. W > zero)) return
      endif

      ! calculate determinant
      det = U + V + W
      if (.not.HIT_EDGE .and. det.eq.zero) return

      !Calculate scaled z−coordinates of vertices and use them to calculate the hit distance.
      Az = Sz * A(kz)
      Bz = Sz * B(kz)
      Cz = Sz * C(kz)
      T = U * Az + V * Bz + W * Cz

      if(BACKFACE_CULLING) then
        if (T < zero .or. T > hit(4) * det) then
          if(ldebug) print *,'BACKFACE_CULLING T<0', T
          return
        endif
      else
        if(det < zero .and. (T >= zero .or. T < hit(4)*det)) then
          if(ldebug) print *,'det<0 && T>0', det, T
          return
        else if(det > zero .and. (T <= zero .or. T > hit(4) * det)) then
          if(ldebug) print *,'det>0 && T<0', det, T
          return
        endif
      endif

      ! normalize U, V, W, and T
      rcpDet = one / det
      b0 = U * rcpDet
      b1 = V * rcpDet
      b2 = W * rcpDet

      hit(1:3) = b0*tA + b1*tB + b2*tC
      hit(4) = T * rcpDet
      lhit = .True.
      if(ldebug) print *,'Hit triangle', lhit, '::', hit
    end subroutine

    pure function rotation_matrix_world_to_local_basis(ex, ey, ez)
      real(ireals), dimension(3), intent(in) :: ex, ey, ez
      real(ireals), dimension(3), parameter :: kx=[1,0,0], ky=[0,1,0], kz=[0,0,1]
      real(ireals), dimension(3,3) :: rotation_matrix_world_to_local_basis
      rotation_matrix_world_to_local_basis(1,1) = dot_product(ex, kx)
      rotation_matrix_world_to_local_basis(1,2) = dot_product(ex, ky)
      rotation_matrix_world_to_local_basis(1,3) = dot_product(ex, kz)
      rotation_matrix_world_to_local_basis(2,1) = dot_product(ey, kx)
      rotation_matrix_world_to_local_basis(2,2) = dot_product(ey, ky)
      rotation_matrix_world_to_local_basis(2,3) = dot_product(ey, kz)
      rotation_matrix_world_to_local_basis(3,1) = dot_product(ez, kx)
      rotation_matrix_world_to_local_basis(3,2) = dot_product(ez, ky)
      rotation_matrix_world_to_local_basis(3,3) = dot_product(ez, kz)
    end function
    pure function rotation_matrix_local_basis_to_world(ex, ey, ez)
      real(ireals), dimension(3), intent(in) :: ex, ey, ez
      real(ireals), dimension(3), parameter :: kx=[1,0,0], ky=[0,1,0], kz=[0,0,1]
      real(ireals), dimension(3,3) :: rotation_matrix_local_basis_to_world
      rotation_matrix_local_basis_to_world(1,1) = dot_product(kx, ex)
      rotation_matrix_local_basis_to_world(1,2) = dot_product(kx, ey)
      rotation_matrix_local_basis_to_world(1,3) = dot_product(kx, ez)
      rotation_matrix_local_basis_to_world(2,1) = dot_product(ky, ex)
      rotation_matrix_local_basis_to_world(2,2) = dot_product(ky, ey)
      rotation_matrix_local_basis_to_world(2,3) = dot_product(ky, ez)
      rotation_matrix_local_basis_to_world(3,1) = dot_product(kz, ex)
      rotation_matrix_local_basis_to_world(3,2) = dot_product(kz, ey)
      rotation_matrix_local_basis_to_world(3,3) = dot_product(kz, ez)
    end function

    ! https://www.maplesoft.com/support/help/maple/view.aspx?path=MathApps%2FProjectionOfVectorOntoPlane
    pure function vec_proj_on_plane(v, plane_normal)
      real(ireals), dimension(3), intent(in) :: v, plane_normal
      real(ireals) :: vec_proj_on_plane(3)
      vec_proj_on_plane = v - dot_product(v, plane_normal) * plane_normal  / norm(plane_normal)**2
    end function

    function get_arg_logical(default_value, opt_arg) result(arg)
      logical :: arg
      logical, intent(in) :: default_value
      logical, intent(in), optional :: opt_arg
      if(present(opt_arg)) then
        arg = opt_arg
      else
        arg = default_value
      endif
    end function
    function get_arg_iintegers(default_value, opt_arg) result(arg)
      integer(iintegers) :: arg
      integer(iintegers), intent(in) :: default_value
      integer(iintegers), intent(in), optional :: opt_arg
      if(present(opt_arg)) then
        arg = opt_arg
      else
        arg = default_value
      endif
    end function
    function get_arg_ireals(default_value, opt_arg) result(arg)
      real(ireals) :: arg
      real(ireals), intent(in) :: default_value
      real(ireals), intent(in), optional :: opt_arg
      if(present(opt_arg)) then
        arg = opt_arg
      else
        arg = default_value
      endif
    end function


    ! https://gist.github.com/t-nissie/479f0f16966925fa29ea
    recursive subroutine quicksort(a, first, last)
      integer(iintegers), intent(inout) :: a(:)
      integer(iintegers), intent(in) :: first, last
      integer(iintegers) :: i, j, x, t

      x = a( (first+last) / 2 )
      i = first
      j = last
      do
        do while (a(i) < x)
          i=i+1
        end do
        do while (x < a(j))
          j=j-1
        end do
        if (i >= j) exit
        t = a(i);  a(i) = a(j);  a(j) = t
        i=i+1
        j=j-1
      end do
      if (first < i-1) call quicksort(a, first, i-1)
      if (j+1 < last)  call quicksort(a, j+1, last)
    end subroutine quicksort

    ! https://stackoverflow.com/questions/44198212/a-fortran-equivalent-to-unique
    function unique(inp)
      !! usage sortedlist = unique(list)
      !! or reshape it first to 1D: sortedlist = unique(reshape(list, [size(list)]))
      integer(iintegers), intent(in) :: inp(:)
      integer(iintegers) :: list(size(inp))
      integer(iintegers), allocatable :: unique(:)
      integer(iintegers) :: n
      logical :: mask(size(inp))

      list = inp
      n=size(list)
      call quicksort(list, i1, n)

      ! cull duplicate indices
      mask = .False.
      mask(1:n-1) = list(1:n-1) == list(2:n)
      allocate(unique(count(.not.mask)))
      unique = pack(list, .not.mask)
    end function unique

  end module
