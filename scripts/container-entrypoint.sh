#!/usr/bin/env bash
set -euo pipefail

target=aarch64-apple-darwin
target_suffix=aarch64_apple_darwin
target_upper=AARCH64_APPLE_DARWIN

if ! command -v osxcross-conf >/dev/null 2>&1; then
  echo "osxcross-conf is not available in PATH" >&2
  exit 1
fi

eval "$(osxcross-conf)"
: "${OSXCROSS_TARGET:?osxcross-conf did not provide OSXCROSS_TARGET}"
tool_prefix="${target}${OSXCROSS_TARGET#darwin}-"

declare -gx AR_${target_suffix}="${tool_prefix}ar"
declare -gx CC_${target_suffix}="${tool_prefix}clang"
declare -gx CXX_${target_suffix}="${tool_prefix}clang++"
declare -gx CARGO_TARGET_${target_upper}_LINKER="${tool_prefix}clang"
declare -gx CARGO_TARGET_${target_upper}_AR="${tool_prefix}ar"

exec "$@"
