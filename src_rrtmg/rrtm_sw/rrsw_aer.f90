      module m_tenstr_rrsw_aer

      use m_tenstr_parkind, only : im => kind_im, rb => kind_rb
      use m_tenstr_parrrsw, only : nbndsw, naerec

      implicit none
      save

!------------------------------------------------------------------
! rrtmg_sw aerosol optical properties
!
!  Data derived from six ECMWF aerosol types and defined for
!  the rrtmg_sw spectral intervals
!
! Initial: J.-J. Morcrette, ECMWF, mar2003
! Revised: MJIacono, AER, jul2006
! Revised: MJIacono, AER, aug2008
!------------------------------------------------------------------
!
!-- The six ECMWF aerosol types are respectively:
!
!  1/ continental average                 2/ maritime
!  3/ desert                              4/ urban
!  5/ volcanic active                     6/ stratospheric background
!
! computed from Hess and Koepke (con, mar, des, urb)
!          from Bonnel et al.   (vol, str)
!
! rrtmg_sw 14 spectral intervals (microns):
!  3.846 -  3.077
!  3.077 -  2.500
!  2.500 -  2.150
!  2.150 -  1.942
!  1.942 -  1.626
!  1.626 -  1.299
!  1.299 -  1.242
!  1.242 -  0.7782
!  0.7782-  0.6250
!  0.6250-  0.4415
!  0.4415-  0.3448
!  0.3448-  0.2632
!  0.2632-  0.2000
! 12.195 -  3.846
!
!------------------------------------------------------------------
!
!  name     type     purpose
! -----   : ----   : ----------------------------------------------
! rsrtaua : real   : ratio of average optical thickness in 
!                    spectral band to that at 0.55 micron
! rsrpiza : real   : average single scattering albedo (unitless)
! rsrasya : real   : average asymmetry parameter (unitless)
!------------------------------------------------------------------

      real(kind=rb) :: rsrtaua(nbndsw,naerec)
      real(kind=rb) :: rsrpiza(nbndsw,naerec)
      real(kind=rb) :: rsrasya(nbndsw,naerec)

      end module m_tenstr_rrsw_aer

