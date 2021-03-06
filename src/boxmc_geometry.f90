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

module m_boxmc_geometry

  use m_data_parameters, only : mpiint, iintegers, ireals, ireal_dp, one, zero
  use m_helper_functions, only : CHKERR, itoa
  use m_helper_functions_dp, only: pnt_in_triangle, distance_to_edge, &
    determine_normal_direction, angle_between_two_vec, &
    distances_to_triangle_edges, norm, mean, approx, &
    triangle_intersection, square_intersection

  implicit none

  contains
    ! Defining related geometric variables given the following vertex coordinates
    !
    !          G________________H
    !          /|              /|
    !         / |             / |
    !       E/__|___________F/  |
    !        |  |            |  |
    !        |  |            |  |
    !        |  |____________|__|
    !        |  /C           |  /D
    !        | /             | /
    !        |/______________|/
    !        A               B

    subroutine setup_cube_coords_from_vertices(vertices, dx, dy, dz)
      real(ireal_dp), intent(in) :: vertices(:)
      real(ireal_dp), intent(out) :: dx, dy, dz
      real(ireal_dp), dimension(3) :: A, B, C, D, E, F, G, H
      logical :: ladvanced=.False.

      if(ladvanced) then
        if(size(vertices).eq.4*2) then ! given are vertices on the top of a cube(x,y)
          A(1:2) = vertices(1:2); A(3) = 0
          B(1:2) = vertices(3:4); B(3) = 0
          C(1:2) = vertices(5:6); C(3) = 0
          D(1:2) = vertices(7:8); D(3) = 0

          dx = mean([norm(B-A), norm(D-C)])
          dy = mean([norm(C-A), norm(D-B)])
          dz = one
        elseif(size(vertices).eq.2*4*3) then ! 3D coords
          A = vertices( 1: 3)
          B = vertices( 4: 6)
          C = vertices( 7: 9)
          D = vertices(10:12)
          E = vertices(13:15)
          F = vertices(16:18)
          G = vertices(19:21)
          H = vertices(22:24)

          dx = mean([norm(B-A), norm(D-C), norm(F-E), norm(H-G)])
          dy = mean([norm(C-A), norm(D-B), norm(G-E), norm(H-F)])
          dz = mean([norm(E-A), norm(F-B), norm(H-D), norm(G-C)])
        else
          call CHKERR(1_mpiint, 'dont know how to handle coords with '//itoa(size(vertices, kind=iintegers))//' vertex entries')
        endif
      else
        if(size(vertices).eq.4*2) then ! given are vertices on the top of a cube(x,y)
          dx = vertices(3) - vertices(1)
          dy = vertices(6) - vertices(2)
          dz = one
        elseif(size(vertices).eq.2*4*3) then ! 3D coords
          dx = vertices(4) - vertices(1)
          dy = vertices(8) - vertices(2)
          dz = vertices(15) - vertices(3)
        else
          call CHKERR(1_mpiint, 'dont know how to handle coords with '//itoa(size(vertices, kind=iintegers))//' vertex entries')
        endif
      endif
    end subroutine

    pure subroutine setup_default_cube_geometry(A, B, C, D, dz, vertices)
      real(ireals), intent(in) :: A(2), B(2), C(2), D(2), dz
      real(ireals), allocatable, intent(inout) :: vertices(:)

      if(allocated(vertices)) deallocate(vertices)
      allocate(vertices(2*4*3))
      vertices( 1: 2) = A
      vertices( 4: 5) = B
      vertices( 7: 8) = C
      vertices(10:11) = D
      vertices([3,6,9,12]) = zero

      vertices(13:14) = A
      vertices(16:17) = B
      vertices(19:20) = C
      vertices(22:23) = D
      vertices([15,18,21,24]) = dz
    end subroutine
    pure subroutine setup_default_unit_cube_geometry(dx, dy, dz, vertices)
      real(ireals), intent(in) :: dx, dy, dz
      real(ireals), allocatable, intent(inout) :: vertices(:)

      if(allocated(vertices)) then
        if(size(vertices).ne.2*4*3) then
          deallocate(vertices)
          allocate(vertices(2*4*3))
        endif
      else
        allocate(vertices(2*4*3))
      endif
      vertices( 1: 2) = [zero,zero]

      vertices( 4: 5) = [  dx,zero]
      vertices( 7: 8) = [zero,  dy]
      vertices(10:11) = [  dx,  dy]
      vertices([3,6,9,12]) = zero

      vertices(13:14) = [zero,zero]
      vertices(16:17) = [  dx,zero]
      vertices(19:20) = [zero,  dy]
      vertices(22:23) = [  dx,  dy]
      vertices([15,18,21,24]) = dz
    end subroutine


    ! Distribution Code for Wedges:
    !
    !        F
    !       / \
    !    dy/   \
    !     /     \
    !    /   dx  \
    !   D________ E
    !   |         |
    !   |    |    |
    !   |    |    |
    !   |    |    |
    !   |         |
    !   |    C    |
    !   |   / \   |
    !   |  /   \  |
    !   | /     \ |
    !   |/       \|
    !   A _______ B

    ! We always assume the triangle to have dx edge length along y=0 (A,B) and dy is the edge length between (A,C)
    ! Distribute Photons on triangles: https://doi.org/10.1145/571647.571648

    subroutine setup_wedge_coords_from_vertices(vertices, A, B, C, nAB, nBC, nCA, dx, dy, dz)
      real(ireal_dp), intent(in) :: vertices(:) ! should be the vertex coordinates for A, B, C in 3D
      real(ireal_dp), dimension(:), intent(out) :: A, B, C ! points on triangle [A,B,C]
      real(ireal_dp), dimension(:), intent(out) :: nAB, nBC, nCA ! normals on triangle [A,B,C], pointing towards center
      real(ireal_dp), intent(out) :: dx, dy, dz

      real(ireal_dp), dimension(size(A)) :: D, E, F ! points on triangle above [A,B,C]
      integer :: i

      if(size(A).ne.2.or.size(B).ne.2.or.size(C).ne.2) call CHKERR(1_mpiint, 'Coordinates have to be 2D coordinates')
      if(size(nAB).ne.2.or.size(nBC).ne.2.or.size(nCA).ne.2) call CHKERR(1_mpiint, 'Normals have to be 2D coordinates')
      if(size(vertices).ne.2*3*3) call CHKERR(1_mpiint, 'Size of vertices have to be 3D coordinates for 6 points')

      A = vertices(1:2)
      B = vertices(4:5)
      C = vertices(7:8)

      D = vertices(10:11)
      E = vertices(13:14)
      F = vertices(16:17)

      nAB = (A-B); nAB = nAB([2,1]); nAB = nAB *[one, -one] / norm(nAB)
      nBC = (B-C); nBC = nBC([2,1]); nBC = nBC *[one, -one] / norm(nBC)
      nCA = (C-A); nCA = nCA([2,1]); nCA = nCA *[one, -one] / norm(nCA)

      dx = norm(B-A)
      dy = norm(C-A)
      dz = vertices(12)-vertices(3)
      if(any(approx([dx,dy,dz], 0._ireal_dp))) then
        do i=1,6
          print *,'vertices', i, vertices((i-1)*3+1:i*3)
        enddo
        print *,'A',A
        print *,'B',B
        print *,'C',C
        print *,'D',D
        print *,'E',E
        print *,'F',F
        print *,'nA',nAB
        print *,'nB',nBC
        print *,'nC',nCA
        print *,'dx/dy/dz', dx, dy, dz
        call CHKERR(1_mpiint, 'bad differential box lengths')
      endif
    end subroutine

    subroutine setup_default_wedge_geometry(A, B, C, dz, vertices)
      real(ireals), intent(in) :: A(2), B(2), C(2), dz
      real(ireals), allocatable, intent(inout) :: vertices(:)

      if(allocated(vertices)) deallocate(vertices)
      allocate(vertices(2*3*3))
      vertices(1:2) = A
      vertices(4:5) = B
      vertices(7:8) = C
      vertices([3,6,9]) = zero

      vertices(10:11) = A
      vertices(13:14) = B
      vertices(16:17) = C
      vertices([12,15,18]) = dz
    end subroutine
    subroutine setup_default_unit_wedge_geometry(dx, dy, dz, vertices)
      real(ireals), intent(in) :: dx, dy, dz
      real(ireals), allocatable, intent(inout) :: vertices(:)

      if(allocated(vertices)) deallocate(vertices)
      allocate(vertices(2*3*3))
      vertices(1:2) = [zero,zero]
      vertices(4:5) = [  dx,zero]
      vertices(7:8) = [dx/2,sqrt(dy**2 - (dx/2)**2)]
      vertices([3,6,9]) = zero

      vertices(10:11) = [zero,zero]
      vertices(13:14) = [  dx,zero]
      vertices(16:17) = [dx/2,sqrt(dy**2 - (dx/2)**2)]
      vertices([12,15,18]) = dz
    end subroutine


    subroutine intersect_cube(vertices, ploc, pdir, pscattercnt, psrc_side, &
        pside, max_dist)
      use m_helper_functions_dp, only: hit_plane
      real(ireal_dp),intent(in) :: vertices(:)
      real(ireal_dp),intent(in) :: pdir(:), ploc(:)
      integer(iintegers),intent(in) :: pscattercnt, psrc_side
      integer(iintegers),intent(inout) :: pside
      real(ireal_dp),intent(out) :: max_dist

      real(ireal_dp) :: x, y, z, dx, dy, dz
      integer(iintegers) :: i,sides(3)

      real(ireal_dp) :: dist(3)
      real(ireal_dp), parameter :: zero=0, one=1

      call setup_cube_coords_from_vertices(vertices, dx, dy, dz)

      !crossing with bottom and top plane:
      if(pdir(3).ge.zero) then
        max_dist = hit_plane(ploc, pdir,[zero,zero,dz ],[zero,zero,one])
        pside=1
        x = ploc(1)+pdir(1)*max_dist
        y = ploc(2)+pdir(2)*max_dist
        if( ( x.gt.zero .and. x.lt.dx) .and. ( y.gt.zero .and. y.lt.dy) ) return
        dist(1) = max_dist; sides(1) = 1
      endif
      if(pdir(3).le.zero) then
        max_dist = hit_plane(ploc, pdir,[zero,zero,zero ],[zero,zero,one])
        pside=2
        x = ploc(1)+pdir(1)*max_dist
        y = ploc(2)+pdir(2)*max_dist
        if( ( x.gt.zero .and. x.lt.dx) .and. ( y.gt.zero .and. y.lt.dy) ) return
        dist(1) = max_dist; sides(1) = 2
      endif

      !crossing with left and right plane:
      if(pdir(1).le.zero) then
        max_dist = hit_plane(ploc, pdir,[ zero ,zero,zero],[one,zero,zero])
        pside=3
        y = ploc(2)+pdir(2)*max_dist
        z = ploc(3)+pdir(3)*max_dist
        if( ( y.gt.zero .and. y.lt.dy) .and. ( z.gt.zero .and. z.lt.dz) ) return
        dist(2) = max_dist; sides(2) = 3
      endif
      if(pdir(1).ge.zero) then
        max_dist = hit_plane(ploc, pdir,[ dx ,zero,zero],[one,zero,zero])
        pside=4
        y = ploc(2)+pdir(2)*max_dist
        z = ploc(3)+pdir(3)*max_dist
        if( ( y.gt.zero .and. y.lt.dy) .and. ( z.gt.zero .and. z.lt.dz) ) return
        dist(2) = max_dist; sides(2) = 4
      endif

      !crossing with back and forward plane:
      if(pdir(2).le.zero) then
        max_dist = hit_plane(ploc, pdir,[zero, zero ,zero],[zero,one,zero])
        pside=5
        x = ploc(1)+pdir(1)*max_dist
        z = ploc(3)+pdir(3)*max_dist
        if( ( x.gt.zero .and. x.lt.dx) .and. ( z.gt.zero .and. z.lt.dz) ) return
        dist(3) = max_dist; sides(3) = 5
      endif
      if(pdir(2).ge.zero) then
        max_dist = hit_plane(ploc, pdir,[zero, dy ,zero],[zero,one,zero])
        pside=6
        x = ploc(1)+pdir(1)*max_dist
        z = ploc(3)+pdir(3)*max_dist
        if( ( x.gt.zero .and. x.lt.dx) .and. ( z.gt.zero .and. z.lt.dz) ) return
        dist(3) = max_dist; sides(3) = 6
      endif

      !Ohhh there was a problem.. maybe with numerics, seems that it may happen that we dont find a solution if norm of pdir is not equal to one....
      max_dist=huge(max_dist)
      do i=1,3
        if(.not. approx(pdir(i),zero) ) then
          if(pscattercnt.eq.0 .and. pside.eq.psrc_side) cycle
          if( dist(i).le.max_dist ) then
            pside = sides(i)
            max_dist = dist(i)
          endif
        endif
      enddo

      if(max_dist.gt.norm([dx,dy,dz])) then
        print *,'should actually not be here at the end of crossings in intersect distance! - however, please check if distance makes sense?:', &
        max_dist, '::', dist, ':', vertices
      endif

    end subroutine

    subroutine intersect_wedge(vertices, ploc, pdir, pscattercnt, psrc_side, &
        pside, pweight, max_dist)
      real(ireal_dp),intent(in) :: vertices(:)
      real(ireal_dp),intent(in) :: pdir(:), ploc(:)
      integer(iintegers),intent(in) :: pscattercnt, psrc_side
      integer(iintegers),intent(inout) :: pside
      real(ireal_dp),intent(inout) :: pweight
      real(ireal_dp),intent(out) :: max_dist

      logical :: l_in_triangle
      logical :: lhit(5)
      real(ireal_dp) :: hit(5,4)
      integer(iintegers) :: i

      associate( &
          A  => vertices( 1: 2), &
          B  => vertices( 4: 5), &
          C  => vertices( 7: 8), &
          Ab => vertices( 1: 3), &
          Bb => vertices( 4: 6), &
          Cb => vertices( 7: 9), &
          At => vertices(10:12), &
          Bt => vertices(13:15), &
          Ct => vertices(16:18))

        lhit = .False.
        hit = huge(hit)
        !crossing with bottom and top plane:
        if(pdir(3).ge.zero) then
          call triangle_intersection(ploc, pdir, At, Bt, Ct, lhit(1), hit(1,:))
          lhit(5) = .False.
        endif
        if(pdir(3).le.zero) then
          call triangle_intersection(ploc, pdir, Ab, Bb, Cb, lhit(5), hit(5,:))
          lhit(1) = .False.
        endif

        !crossing with side planes:
        ! plane 2, along y=0
        call square_intersection(ploc, pdir, Ab, Bb, Bt, At, lhit(2), hit(2,:))
        call square_intersection(ploc, pdir, Ab, Cb, Ct, At, lhit(3), hit(3,:))
        call square_intersection(ploc, pdir, Bb, Cb, Ct, Bt, lhit(4), hit(4,:))

        pside=0
        max_dist = huge(max_dist)
        do i=1,5
          if(hit(i,4).lt.zero) cycle
          if(pscattercnt.eq.0 .and. pside.eq.psrc_side) cycle
          if(hit(i,4).lt.max_dist) then
            max_dist = hit(i,4)
            pside   = i
          endif
        enddo

        ! If we did not hit anything else, I assume that we point towards the src side.
        ! We collect it there but set energy to 0
        if(pscattercnt.eq.0 .and. pside.eq.0 .and. lhit(psrc_side) ) then
          max_dist = hit(psrc_side,4)
          pside = psrc_side
          pweight = zero ! we dont allow energy to hit the src face, at least not right after it started!
        endif

        if(count(lhit).eq.0) then
          print *,'should actually not be here at the end of crossings in intersect distance!'
          print *,'max dist, pside', max_dist, pside, 'src_side', psrc_side
          print *,'ploc', ploc
          print *,'At', At
          print *,'Bt', Bt
          print *,'Ct', Ct
          print *,'Ab', Ab
          print *,'Bb', Bb
          print *,'Cb', Cb
          print *,'lhit', lhit
          print *,'hit1', hit(1,:)
          print *,'hit2', hit(2,:)
          print *,'hit3', hit(3,:)
          print *,'hit4', hit(4,:)
          print *,'hit5', hit(5,:)
          call CHKERR(1_mpiint, 'ERROR in Raytracer, didnt hit anything!')
        endif

        l_in_triangle = pnt_in_triangle(A,B,C, hit(pside,1:2))
        if(.not.l_in_triangle) then
          print *,'max dist, pside', max_dist, pside, 'src_side', psrc_side
          print *,'lhit', lhit
          print *,'hit1', hit(1,:)
          print *,'hit2', hit(2,:)
          print *,'hit3', hit(3,:)
          print *,'hit4', hit(4,:)
          print *,'hit5', hit(5,:)
          print *,'distance to edges:', distances_to_triangle_edges(A,B,C, hit(pside,1:2)), ':: dists to faces',hit(pside,4)
          print *,'called pnt_in_triangle(', A, B, C, hit(pside,1:2), ')'
          print *,'target point not in triangle', hit, 'side', pside, 'dist', hit(pside,4)
          call CHKERR(1_mpiint, 'Photon not inside the triangle')
        endif
      end associate
    end subroutine
  end module
