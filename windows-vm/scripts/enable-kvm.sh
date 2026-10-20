#!/usr/bin/env bash
# Make /dev/kvm usable by the current user, or explain why it cannot be.
#
# GitHub's hosted Linux runners expose KVM but leave it owned by the `kvm`
# group, which the runner user is not in. Two things matter:
#
#  * the udev rule below is the one GitHub's Android emulator documentation
#    uses, and it is what survives on a long-lived machine;
#  * `access(2)` (what `test -w` uses) can still report EACCES on a device
#    whose mode already looks permissive, so success is decided by actually
#    opening the device, which is what qemu does.
set -euo pipefail

can_open() {
  python3 - <<'PY'
import os
import sys

try:
    fd = os.open("/dev/kvm", os.O_RDWR)
except OSError as error:
    print(f"open failed: {error}", file=sys.stderr)
    sys.exit(1)
os.close(fd)
PY
}

if [ ! -e /dev/kvm ]; then
  echo "/dev/kvm is not present on this machine" >&2
  exit 1
fi

if can_open; then
  echo "kvm-usable"
  exit 0
fi

rule=/etc/udev/rules.d/99-kvm4all.rules
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |
  sudo tee "$rule" >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm
# A container's /dev is often a bind mount that udev does not manage, so the
# mode is also set directly; both steps are idempotent.
sudo chmod 0666 /dev/kvm || true

if can_open; then
  echo "kvm-unlocked"
  exit 0
fi

echo "/dev/kvm cannot be opened for read/write even after the udev rule and chmod" >&2
ls -l /dev/kvm >&2 || true
exit 1
