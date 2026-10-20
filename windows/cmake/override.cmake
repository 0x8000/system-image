# clang-cl treats absolute paths beginning with /U as macro undefines. Keep
# source paths separated from compiler options so those paths stay paths.
string(REPLACE "-c <SOURCE>" "-c -- <SOURCE>" CMAKE_C_COMPILE_OBJECT "${CMAKE_C_COMPILE_OBJECT}")
string(REPLACE "-c <SOURCE>" "-c -- <SOURCE>" CMAKE_CXX_COMPILE_OBJECT "${CMAKE_CXX_COMPILE_OBJECT}")
string(REPLACE "/D" "-D" CMAKE_RC_FLAGS "${CMAKE_RC_FLAGS_INIT}")
string(REPLACE "/D" "-D" CMAKE_RC_FLAGS_DEBUG "${CMAKE_RC_FLAGS_DEBUG_INIT}")
if(NOT CMAKE_HOST_WIN32)
  set(CMAKE_NINJA_CMCLDEPS_RC 0)
endif()
