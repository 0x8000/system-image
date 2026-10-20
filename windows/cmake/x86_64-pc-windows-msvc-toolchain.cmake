set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

set(CMAKE_C_COMPILER clang-cl CACHE FILEPATH "")
set(CMAKE_CXX_COMPILER clang-cl CACHE FILEPATH "")
set(CMAKE_AR llvm-lib)
set(CMAKE_LINKER lld-link CACHE FILEPATH "")
set(CMAKE_RC_COMPILER llvm-rc CACHE FILEPATH "")
set(CMAKE_MSVC_RUNTIME_LIBRARY CACHE STRING "MultiThreadedDLL")

set(COMPILE_FLAGS
    --target=x86_64-pc-windows-msvc
    -Wno-unused-command-line-argument
    -fuse-ld=lld-link

    /imsvc /opt/xwin/crt/include
    /imsvc /opt/xwin/sdk/include/ucrt
    /imsvc /opt/xwin/sdk/include/um
    /imsvc /opt/xwin/sdk/include/shared
    /imsvc /opt/xwin/sdk/include/winrt)

set(LINK_FLAGS
    /manifest:no

    -libpath:"/opt/xwin/crt/lib/x86_64"
    -libpath:"/opt/xwin/sdk/lib/um/x86_64"
    -libpath:"/opt/xwin/sdk/lib/ucrt/x86_64")

string(REPLACE ";" " " COMPILE_FLAGS "${COMPILE_FLAGS}")

set(_CMAKE_C_FLAGS_INITIAL "${CMAKE_C_FLAGS}" CACHE STRING "")
set(CMAKE_C_FLAGS "${_CMAKE_C_FLAGS_INITIAL} ${COMPILE_FLAGS}" CACHE STRING "" FORCE)

set(_CMAKE_CXX_FLAGS_INITIAL "${CMAKE_CXX_FLAGS}" CACHE STRING "")
set(CMAKE_CXX_FLAGS "${_CMAKE_CXX_FLAGS_INITIAL} ${COMPILE_FLAGS} /EHsc" CACHE STRING "" FORCE)

string(REPLACE ";" " " LINK_FLAGS "${LINK_FLAGS}")

set(_CMAKE_EXE_LINKER_FLAGS_INITIAL "${CMAKE_EXE_LINKER_FLAGS}" CACHE STRING "")
set(CMAKE_EXE_LINKER_FLAGS "${_CMAKE_EXE_LINKER_FLAGS_INITIAL} ${LINK_FLAGS}" CACHE STRING "" FORCE)

set(_CMAKE_MODULE_LINKER_FLAGS_INITIAL "${CMAKE_MODULE_LINKER_FLAGS}" CACHE STRING "")
set(CMAKE_MODULE_LINKER_FLAGS "${_CMAKE_MODULE_LINKER_FLAGS_INITIAL} ${LINK_FLAGS}" CACHE STRING "" FORCE)

set(_CMAKE_SHARED_LINKER_FLAGS_INITIAL "${CMAKE_SHARED_LINKER_FLAGS}" CACHE STRING "")
set(CMAKE_SHARED_LINKER_FLAGS "${_CMAKE_SHARED_LINKER_FLAGS_INITIAL} ${LINK_FLAGS}" CACHE STRING "" FORCE)

# Let projects explicitly control which system libraries they need.
set(CMAKE_C_STANDARD_LIBRARIES "" CACHE STRING "" FORCE)
set(CMAKE_CXX_STANDARD_LIBRARIES "" CACHE STRING "" FORCE)

set(CMAKE_TRY_COMPILE_CONFIGURATION Release)
set(CMAKE_USER_MAKE_RULES_OVERRIDE "${CMAKE_CURRENT_LIST_DIR}/override.cmake")
