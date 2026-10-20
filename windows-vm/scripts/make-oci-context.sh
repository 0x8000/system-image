#!/usr/bin/env bash
# Turn one qcow2 into a container image context the registry can hold.
#
# GitHub's container registry caps a single layer at 10 GB. A Windows disk sits
# uncomfortably close to that even compressed, so the disk is split into parts
# and every part gets its own Dockerfile instruction, and therefore its own
# layer. A consumer concatenates the parts back in order; manifest.json records
# the hash and size of the assembled file.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: make-oci-context.sh --disk FILE --output-dir DIR [--part-size 1800M]

writes:
  DIR/Dockerfile
  DIR/manifest.json
  DIR/parts/disk.qcow2.part-NN
USAGE
}

disk=""
out=""
part_size="1800M"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk) disk="$2"; shift 2 ;;
    --output-dir) out="$2"; shift 2 ;;
    --part-size) part_size="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$disk" && -n "$out" ]] || { usage >&2; exit 2; }
[[ -f "$disk" ]] || { echo "no such disk: $disk" >&2; exit 1; }

for tool in split sha256sum stat qemu-img python3; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

# A part count that silently changes would invalidate the manifest, so the
# output directory is rebuilt from scratch every time.
rm -rf "$out"
mkdir -p "$out/parts"

split -b "$part_size" -d --suffix-length=2 "$disk" "$out/parts/disk.qcow2.part-"

parts=("$out"/parts/disk.qcow2.part-*)
count=${#parts[@]}
sha=$(sha256sum "$disk" | cut -d' ' -f1)
size=$(stat -c '%s' "$disk")
virtual=$(qemu-img info --output=json "$disk" |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')

WINDOWS_VM_PARTS="$count" WINDOWS_VM_SHA="$sha" WINDOWS_VM_SIZE="$size" \
  WINDOWS_VM_VIRTUAL="$virtual" WINDOWS_VM_PART_SIZE="$part_size" \
  python3 - "$out" <<'PY'
import json
import os
import sys
from pathlib import Path

out = Path(sys.argv[1])
(out / "manifest.json").write_text(
    json.dumps(
        {
            "disk": "disk.qcow2",
            "format": "qcow2",
            "sha256": os.environ["WINDOWS_VM_SHA"],
            "size": int(os.environ["WINDOWS_VM_SIZE"]),
            "virtual_size": int(os.environ["WINDOWS_VM_VIRTUAL"]),
            "parts": int(os.environ["WINDOWS_VM_PARTS"]),
            "part_size": os.environ["WINDOWS_VM_PART_SIZE"],
        },
        indent=2,
    )
    + "\n"
)
PY

# One ADD per part keeps every layer under the registry's per-layer limit.
{
  echo "FROM scratch"
  echo
  echo 'LABEL org.opencontainers.image.title="fastnet windows bdd vm"'
  echo 'LABEL org.opencontainers.image.description="Windows 11 Enterprise LTSC 2024 golden disk for FastNet BDD"'
  echo
  echo "ADD manifest.json /parts/manifest.json"
  for part in "${parts[@]}"; do
    echo "ADD parts/$(basename "$part") /parts/$(basename "$part")"
  done
  echo
  # A scratch image has no binary to run, but `docker create` still requires a
  # command. The manifest is the only meaningful default.
  echo 'CMD ["/parts/manifest.json"]'
} >"$out/Dockerfile"

echo "wrote $out ($count parts, $size bytes, sha256=$sha, virtual=$virtual)"
