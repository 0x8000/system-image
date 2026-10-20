#!/usr/bin/env bash
# Reassemble the golden disk from its container image.
#
# The image carries the disk split into parts because of the registry's
# per-layer limit. This script stitches them back together and refuses to leave
# a file behind unless its hash matches the manifest.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: fetch-image.sh --image ghcr.io/OWNER/windows-vm:TAG --output-dir DIR

writes DIR/disk.qcow2 and prints its path
USAGE
}

image=""
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) image="$2"; shift 2 ;;
    --output-dir) out="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$image" && -n "$out" ]] || { usage >&2; exit 2; }
command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }

mkdir -p "$out"
docker pull "$image"
container=$(docker create "$image")
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
docker cp "$container:/parts" "$out/"

python3 - "$out" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

out = Path(sys.argv[1])
# `docker cp` keeps the directory when the source is a directory, so the
# payload normally lands under parts/. The flat layout is accepted as well so
# an image built by an older revision still reassembles.
root = out / "parts" if (out / "parts" / "manifest.json").is_file() else out
manifest = json.loads((root / "manifest.json").read_text())
target = out / manifest["disk"]
parts = sorted(root.glob("disk.qcow2.part-*"))
if len(parts) != manifest["parts"]:
    raise SystemExit(f"expected {manifest['parts']} parts, found {len(parts)}")

with target.open("wb") as handle:
    for part in parts:
        handle.write(part.read_bytes())

actual = subprocess.run(
    ["sha256sum", str(target)], capture_output=True, text=True, check=True
).stdout.split()[0]
if actual != manifest["sha256"]:
    target.unlink()
    raise SystemExit(f"assembled disk hash {actual} != {manifest['sha256']}")
if target.stat().st_size != manifest["size"]:
    target.unlink()
    raise SystemExit("assembled disk size does not match the manifest")
print(target)
PY
