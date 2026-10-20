#!/usr/bin/env bash
set -euo pipefail

target=x86_64-pc-windows-msvc
suffix=x86_64_pc_windows_msvc
upper=X86_64_PC_WINDOWS_MSVC

test -d /opt/xwin/crt/include
test -d /opt/xwin/sdk/include/ucrt
test -d /opt/xwin/sdk/include/um
test -d /opt/xwin/sdk/include/shared
test -d /opt/xwin/sdk/include/winrt
test -d /opt/xwin/crt/lib/x86_64
test -d /opt/xwin/sdk/lib/um/x86_64
test -d /opt/xwin/sdk/lib/ucrt/x86_64

test "$(command -v clang-cl)" = "/usr/local/bin/clang-cl"
test "$(command -v lld-link)" = "/usr/local/bin/lld-link"
test "$(command -v llvm-lib)" = "/usr/local/bin/llvm-lib"
test "$(command -v llvm-rc)" = "/usr/local/bin/llvm-rc"
test "$(command -v wine)" = "/usr/bin/wine"
test "$(printenv "CC_${suffix}")" = "clang-cl"
test "$(printenv "CXX_${suffix}")" = "clang-cl"
test "$(printenv "AR_${suffix}")" = "llvm-lib"
test "$(printenv "RC_${suffix}")" = "llvm-rc"
test "$(printenv "CARGO_TARGET_${upper}_LINKER")" = "lld-link"
test "$(printenv "CARGO_TARGET_${upper}_AR")" = "llvm-lib"
test "$(printenv "CARGO_TARGET_${upper}_RUNNER")" = "wine"
test -f "$CMAKE_TOOLCHAIN_FILE_x86_64_pc_windows_msvc"

clang-cl --version | head -n 1 | grep -q 'clang version 19\.'
lld-link --version | head -n 1 | grep -q 'LLD 19\.'
wine --version | head -n 1 | grep -q '^wine-'

# Rust invokes the MSVC linker as `lld-link -flavor link`.
lld-link -flavor link /? >/dev/null 2>&1

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

cat > hello.c <<'EOF'
#include <stdio.h>

int main(void) {
  puts("system-image");
  return 0;
}
EOF

clang-cl $CL_FLAGS hello.c /Fe:hello.exe
file hello.exe | grep -q 'PE32+ executable (console) x86-64'
test "$(wine hello.exe 2>/dev/null | tr -d '\r')" = "system-image"

clang-cl $CL_FLAGS /c hello.c /Fo:hello.obj
llvm-lib /out:hello.lib hello.obj
test -s hello.lib

cat > hello.cpp <<'EOF'
#include <cstdio>
#include <vector>
#include <windows.h>

int main() {
  std::vector<int> values{1, 2, 3};
  std::printf("system-image %zu\n", values.size());
  return 0;
}
EOF

clang-cl $CL_FLAGS /EHsc hello.cpp /Fe:hello-cpp.exe
file hello-cpp.exe | grep -q 'PE32+ executable (console) x86-64'

mkdir cmake-src
cat > cmake-src/CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.20)
project(system_image_verify LANGUAGES C CXX)

add_executable(cmake-c main.c)
add_executable(cmake-cpp main.cpp)
EOF
cat > cmake-src/main.c <<'EOF'
#include <stdio.h>

int main(void) {
  puts("system-image cmake");
  return 0;
}
EOF
cat > cmake-src/main.cpp <<'EOF'
#include <cstdio>
#include <vector>

int main() {
  std::vector<int> values{1, 2, 3};
  std::printf("system-image cmake %zu\n", values.size());
  return 0;
}
EOF

cmake \
  -S cmake-src \
  -B cmake-build \
  -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE_x86_64_pc_windows_msvc" \
  -DCMAKE_BUILD_TYPE=Release
cmake --build cmake-build
file cmake-build/cmake-c.exe | grep -q 'PE32+ executable (console) x86-64'
file cmake-build/cmake-cpp.exe | grep -q 'PE32+ executable (console) x86-64'
test "$(wine cmake-build/cmake-c.exe 2>/dev/null | tr -d '\r')" = "system-image cmake"

echo "system-image Windows verification passed"
