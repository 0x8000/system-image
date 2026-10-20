#!/usr/bin/env bash
# Make /dev/kvm usable by the current user, or explain why it cannot be.
#
# GitHub's hosted Linux runners expose KVM but leave it owned by the `kvm`
# group, and the runner user is not in it. This is the udev rule GitHub's own
# Android emulator documentation uses. It needs sudo, and it has to run in
# every job that starts a VM: each job gets a fresh machine.
set -euo pipefail

if [ ! -e /dev/kvm ]; then
  echo "/dev/kvm is not present on this machine" >&2
  exit 1
fi

if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  echo "kvm-already-usable"
  exit 0
fi

rule=/etc/udev/rules.d/99-kvm4all.rules
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |
  sudo tee "$rule" >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm

if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  echo "kvm-unlocked"
  exit 0
fi

echo "/dev/kvm is present but not writable even after the udev rule" >&2
ls -l /dev/kvm >&2 || true
exit 1
