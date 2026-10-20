#!/usr/bin/env bash
set -euo pipefail

target=x86_64-pc-windows-msvc
target_suffix=x86_64_pc_windows_msvc
target_upper=X86_64_PC_WINDOWS_MSVC

for tool in clang-cl lld-link llvm-lib llvm-rc wine; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not available in PATH" >&2
    exit 1
  fi
done

export CC_${target_suffix}=clang-cl
export CXX_${target_suffix}=clang-cl
export AR_${target_suffix}=llvm-lib
export RC_${target_suffix}=llvm-rc
export CARGO_TARGET_${target_upper}_LINKER=lld-link
export CARGO_TARGET_${target_upper}_AR=llvm-lib
export CARGO_TARGET_${target_upper}_RUNNER=wine
export WINEDEBUG="${WINEDEBUG:--all}"

if [ -z "${WINEPREFIX:-}" ]; then
  export WINEPREFIX=/tmp/wine
fi

if [ ! -f "${WINEPREFIX}/.update-timestamp" ]; then
  mkdir -p "${WINEPREFIX}"
  wineboot --init >/dev/null 2>&1 || true
fi

exec "$@"
