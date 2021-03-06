module m_mmap
use iso_c_binding

use m_data_parameters, only : iintegers, ireals, mpiint
use m_helper_functions, only : CHKERR, imp_bcast, itoa

implicit none
! Definitions from mman-linux.h

integer, parameter :: &
  PROT_READWRITE = 3, &
  PROT_READ = 1,      &
  MAP_SHARED = 1,     &
  MAP_PRIVATE = 2,    &
  MAP_NORESERVE = 16384, & ! X'04000'
  O_RDONLY = 0

interface
  type(c_ptr) function c_mmap(addr, length, prot, &
      flags, filedes, off) result(result) bind(c, name='mmap')
    use iso_c_binding
    integer(c_int), value :: addr
    integer(c_size_t), value :: length
    integer(c_int), value :: prot
    integer(c_int), value :: flags
    integer(c_int), value :: filedes
    integer(c_size_t), value :: off
  end function
end interface
interface
  integer(c_int) function c_munmap(addr, length) bind(c,name='munmap')
    use iso_c_binding
    type(c_ptr), value :: addr
    integer(c_size_t), value :: length
  end function
end interface
interface
  integer(c_int) function c_open(pathname, flags) bind(c,name='open')
    use iso_c_binding
    character(kind=c_char, len=1) :: pathname(*)
    integer(c_int), value :: flags
  end function
end interface
interface
  integer(c_int) function c_close(fd) bind(c,name='close')
    use iso_c_binding
    integer(c_int), value :: fd
  end function
end interface

interface arr_to_binary_datafile
  module procedure arr_to_binary_datafile_2d
end interface

contains

  subroutine arr_to_binary_datafile_2d(arr, fname, ierr)
    real(ireals), dimension(:,:), intent(in) :: arr
    character(len=*), intent(in) :: fname
    integer(mpiint), intent(out) :: ierr

    integer :: funit
    logical :: lexists

    inquire(file=trim(fname), exist=lexists)
    if(lexists) then
      open(newunit=funit, file=trim(fname), form='unformatted', access='stream', status='replace')
    else
      open(newunit=funit, file=trim(fname), form='unformatted', access='stream', status='new')
    endif
    write (unit=funit) arr
    close(funit)
    ierr = 0
  end subroutine

  subroutine binary_file_to_mmap(fname, bytesize, mmap_c_ptr)
    character(len=*), intent(in) :: fname
    integer(c_size_t), intent(in) :: bytesize
    type(c_ptr), intent(out) :: mmap_c_ptr
    integer(c_size_t),parameter :: offset=0

    integer(c_int) :: c_fd

    logical :: lexists

    inquire(file=trim(fname), exist=lexists)
    if(.not.lexists) call CHKERR(1_mpiint, 'Tried to create a mmap from a file that does not exist: '//fname)

    c_fd = c_open(trim(fname)//C_NULL_CHAR, O_RDONLY)
    if(c_fd.le.0) call CHKERR(c_fd, 'Could not open mmap file')
    mmap_c_ptr = c_mmap(0_c_int, bytesize, PROT_READ, IOR(MAP_PRIVATE, MAP_NORESERVE), c_fd, offset)
    c_fd = c_close(c_fd)
    if(c_fd.le.0) call CHKERR(c_fd, 'Could not close file descriptor to mmap file')
  end subroutine

  subroutine arr_to_mmap(comm, fname, mmap_ptr, ierr, inp_arr)
    integer(mpiint), intent(in) :: comm
    character(len=*), intent(in) :: fname
    real(ireals), dimension(:,:), intent(in), optional :: inp_arr
    real(ireals), pointer, intent(out) :: mmap_ptr(:,:)
    integer(mpiint), intent(out) :: ierr

    integer(iintegers), allocatable :: arrshape(:)
    type(c_ptr) :: mmap_c_ptr
    integer(mpiint) :: myid
    integer(c_size_t) :: size_of_inp_arr
    integer(c_size_t) :: dtype_size
    integer(c_size_t) :: bytesize

    call mpi_comm_rank(comm, myid, ierr); call CHKERR(ierr)

    if(myid.eq.0) then
      if(.not.present(inp_arr)) call CHKERR(1_mpiint, 'rank 0 has to provide an input array!')
      call arr_to_binary_datafile(inp_arr, fname, ierr)
      if(ierr.ne.0) print *,'arr_to_mmap::binary file already exists, I did not overwrite it... YOU have to make sure that the file is as expected or delete it...'
      dtype_size = c_sizeof(inp_arr(1,1))
      size_of_inp_arr = size(inp_arr, kind=c_size_t)
      bytesize = dtype_size * size_of_inp_arr
      if(size_of_inp_arr.ge.huge(size_of_inp_arr)/dtype_size) then
        print *,'dtype_size', dtype_size
        print *,'size_of_inp_arr', size_of_inp_arr
        print *,'bytesize', bytesize
        call CHKERR(1_mpiint, 'size_of_inp_arr too large for c_size_t')
      endif
      allocate(arrshape(size(shape(inp_arr))), source=shape(inp_arr, kind=iintegers))
    endif
    call mpi_barrier(comm, ierr)

    call imp_bcast(comm, arrshape, 0_mpiint)
    call imp_bcast(comm, bytesize, 0_mpiint)

    if(bytesize.le.0_c_size_t) then
      if(myid.eq.0) print *,'huge(c_size_t)', huge(size_of_inp_arr), 'shape inp_arr', shape(inp_arr)
      call mpi_barrier(comm, ierr)
      call CHKERR(1_mpiint, 'bytesize of mmap is wrong!'//itoa(int(bytesize,iintegers)))
    endif

    call binary_file_to_mmap(fname, bytesize, mmap_c_ptr)

    call c_f_pointer(mmap_c_ptr, mmap_ptr, arrshape)
  end subroutine

  subroutine munmap_mmap_ptr(mmap_ptr, ierr)
    real(ireals), pointer, intent(inout) :: mmap_ptr(:,:)

    type(c_ptr) :: mmap_c_ptr
    integer(c_int) :: cerr
    integer(c_size_t) :: bytesize

    integer(mpiint) :: ierr


    bytesize = int(sizeof(mmap_ptr), kind=c_size_t)
    mmap_c_ptr = c_loc(mmap_ptr(1,1))

    mmap_ptr=>NULL()

    cerr = c_munmap(mmap_c_ptr, bytesize)
    ierr = cerr
    call CHKERR(ierr, 'Error Unmapping the memory map')
  end subroutine

end module
