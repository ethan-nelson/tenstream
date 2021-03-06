# Default GCC
#
# Config script for the linux environment at the Meteorological Institute Munich 08.Jan.2015
#
# There may be a maintained(Fabian Jakub) petsc library available through
#
#  module load petsc
#
# if so, you might get away with copying the following into your .bashrc:
# and use this config file here with `cmake <tenstream_root_dir> -DSYST:STRING=lmu_mim`

set(CMAKE_C_COMPILER   "mpicc")
set(CMAKE_Fortran_COMPILER   "mpif90")
set(Fortran_COMPILER_WRAPPER "mpif90")

set(USER_C_FLAGS               "-cpp -W -std=c99")
set(USER_Fortran_FLAGS         "-cpp -ffree-line-length-none")
set(USER_Fortran_FLAGS_RELEASE "-fno-range-check -O3 -mtune=native")
set(USER_Fortran_FLAGS_DEBUG   "-fbacktrace -finit-real=nan -Werror -Wall -pedantic -g -pg -fcheck=all -fbounds-check")

set(NETCDF_DIR      "$ENV{NETCDF}")
set(NETCDF_DIR_F90  "$ENV{NETCDF}")
