#!/usr/bin/env bash
set -euo pipefail

expected_sdk=/opt/osxcross/SDK/MacOSX15.5.sdk
expected_target=darwin24.5
expected_sdk_version=15.5
expected_minos=11.0
target=aarch64-apple-darwin
suffix=aarch64_apple_darwin
upper=AARCH64_APPLE_DARWIN
tool_suffix="${target}${expected_target#darwin}"
cc_name="${tool_suffix}-clang"
cxx_name="${tool_suffix}-clang++"
ar_name="${tool_suffix}-ar"
otool_name="${tool_suffix}-otool"

conf="$(osxcross-conf)"
target_dir="$(sed -n 's/^export OSXCROSS_TARGET_DIR="\(.*\)"$/\1/p' <<<"$conf")"
sdk_dir="$(sed -n 's/^export OSXCROSS_SDK="\(.*\)"$/\1/p' <<<"$conf")"
sdk_version="$(sed -n 's/^export OSXCROSS_SDK_VERSION="\(.*\)"$/\1/p' <<<"$conf")"
osx_target="$(sed -n 's/^export OSXCROSS_TARGET="\(.*\)"$/\1/p' <<<"$conf")"
osx_min="$(sed -n 's/^export OSXCROSS_OSX_VERSION_MIN="\(.*\)"$/\1/p' <<<"$conf")"
osx_flavor="$(sed -n 's/^export OSXCROSS_BUILD_FLAVOR="\(.*\)"$/\1/p' <<<"$conf")"

test "$osx_target" = "$expected_target"
test "$sdk_version" = "$expected_sdk_version"
test "$osx_min" = "$expected_minos"
test "$osx_flavor" = "stable"
test "$(realpath "$target_dir")" = "/opt/osxcross"
test "$(realpath "$sdk_dir")" = "$(realpath "$expected_sdk")"
test "$(realpath "$SDKROOT")" = "$(realpath "$expected_sdk")"
test -d "$SDKROOT"

test -x "$(command -v "$cc_name")"
test -x "$(command -v "$cxx_name")"
test -x "$(command -v "$ar_name")"
test "$(printenv "CC_${suffix}")" = "$cc_name"
test "$(printenv "CXX_${suffix}")" = "$cxx_name"
test "$(printenv "AR_${suffix}")" = "$ar_name"
test "$(printenv "CARGO_TARGET_${upper}_LINKER")" = "$cc_name"
test "$(printenv "CARGO_TARGET_${upper}_AR")" = "$ar_name"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
printf '%s\n' \
  '#include <stdio.h>' \
  'int main(void) {' \
  '  puts("system-image");' \
  '  return 0;' \
  '}' >"${workdir}/hello.c"

"$cc_name" -O2 "${workdir}/hello.c" -o "${workdir}/hello"
file "${workdir}/hello" | grep -q 'Mach-O 64-bit arm64 executable'
"$otool_name" -l "${workdir}/hello" \
  | grep -A5 'cmd LC_BUILD_VERSION' \
  | grep -q "minos ${expected_minos}"

printf '%s\n' \
  '#include <cstdio>' \
  'int main() {' \
  '  std::puts("system-image");' \
  '  return 0;' \
  '}' >"${workdir}/hello.cpp"

"$cxx_name" -O2 "${workdir}/hello.cpp" -o "${workdir}/hello-cpp"
file "${workdir}/hello-cpp" | grep -q 'Mach-O 64-bit arm64 executable'

echo "system-image verification passed"
