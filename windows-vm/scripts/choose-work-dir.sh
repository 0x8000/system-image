#!/usr/bin/env bash
# Print a writable directory with room for a Windows install.
#
# Hosted runners keep /mnt large but root-owned, and the root of the filesystem
# is not writable by the runner user even when the volume has space. This
# script creates a directory under a candidate and prints it, so a caller never
# has to reason about mount ownership or about which job ran on which machine.
set -euo pipefail

minimum_gib=${1:-45}
name=${2:-windows-vm}

candidates=()
[ -d /mnt ] && candidates+=("/mnt/$name")
[ -n "${RUNNER_TEMP:-}" ] && candidates+=("$RUNNER_TEMP/$name")
[ -n "${HOME:-}" ] && candidates+=("$HOME/.cache/$name")
candidates+=("/tmp/$name")

for candidate in "${candidates[@]}"; do
  parent=$(dirname "$candidate")
  if [ ! -w "$parent" ]; then
    # Only /mnt is worth taking ownership of; the rest are already ours.
    if [ "$parent" = "/mnt" ]; then
      sudo mkdir -p "$candidate" 2>/dev/null || continue
      sudo chown "$(id -u):$(id -g)" "$candidate" 2>/dev/null || continue
    else
      continue
    fi
  else
    mkdir -p "$candidate" 2>/dev/null || continue
  fi

  [ -w "$candidate" ] || continue
  avail=$(df --output=avail -k "$candidate" | tail -1)
  # Report the free space on stderr so the caller's stdout stays a bare path.
  echo "$candidate: $((avail / 1024 / 1024)) GiB free" >&2
  if [ "$avail" -ge $((minimum_gib * 1024 * 1024)) ]; then
    echo "$candidate"
    exit 0
  fi
done

echo "no writable directory with ${minimum_gib} GiB free" >&2
exit 1
