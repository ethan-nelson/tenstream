include_directories ("${CMAKE_CURRENT_SOURCE_DIR}")

set( general_sources
  "plex_grid.F90"
  "plex_rt.F90"
  "icon_grid.F90"
  )

add_library( plexrt ${general_sources} )
target_link_libraries( plexrt pprts_base )


add_executable( gen_plex_from_icon gen_plex_from_icon.F90 )
target_link_libraries( gen_plex_from_icon plexrt pprts_base )
install(TARGETS gen_plex_from_icon DESTINATION bin)


add_executable( plex_ex1 plex_ex1.F90 )
target_link_libraries( plex_ex1 plexrt pprts_base )
install(TARGETS plex_ex1 DESTINATION bin)


add_executable( plex_ex2 plex_ex2.F90 )
target_link_libraries( plex_ex2 plexrt pprts_base )
install(TARGETS plex_ex2 DESTINATION bin)


add_executable( gen_fish_plex gen_fish_plex.F90 )
target_link_libraries( gen_fish_plex plexrt pprts_base)
install(TARGETS gen_fish_plex DESTINATION bin)

file( GLOB streams createLUT_*.f90 )
foreach ( stream ${streams} )
  GET_FILENAME_COMPONENT(basename "${stream}" NAME_WE )

  add_executable("${basename}" "${basename}.f90" )
  target_link_libraries( "${basename}" plexrt pprts_base )

  install(TARGETS ${basename} RUNTIME DESTINATION bin)
endforeach ()


install(TARGETS plexrt DESTINATION lib)
install(DIRECTORY ./ DESTINATION include/ FILES_MATCHING PATTERN "*.h")
