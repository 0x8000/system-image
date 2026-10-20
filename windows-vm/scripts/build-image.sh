#!/usr/bin/env bash
# Build the Windows golden disk end to end.
#
# Every step that can fail cheaply runs before the expensive one: the ISO is
# hashed, the edition name is read out of the media, and the answer file is
# rendered from that name. Packer then only has to install and provision.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: build-image.sh --work-dir DIR [options]

required:
  --work-dir DIR          scratch directory (ISO, installers, Packer output)

options:
  --iso-url URL           Windows LTSC ISO (default: Microsoft evaluation media)
  --iso-sha256 HEX        expected ISO hash; recorded but not required
  --image-name NAME       edition to install (default: LTSC 2024 Evaluation)
  --virtio-iso-url URL    virtio-win drivers ISO
  --virtio-sha256 HEX     expected virtio-win hash
  --webview2-url URL      offline Evergreen WebView2 installer
  --npcap-url URL         Npcap installer
  --npcap-sha256 HEX      expected Npcap hash
  --ffmpeg-url URL        optional ffmpeg zip for screen recording
  --accelerator MODE      kvm (default) or tcg
  --disk-interface IFACE  virtio (default) or sata
  --disk-size-mb N        virtual disk size (default 40960)
  --cpus N                vCPUs (default 4)
  --memory-mb N           RAM (default 6144)
  --compress              shrink the exported qcow2 with qemu-img -c
  --output-disk FILE      where the finished disk is written
USAGE
}

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=""
iso_url="https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_LTSC_EVAL_x64FRE_en-us.iso"
iso_sha="67cec5865eaa037a72ddc633a717a10a2bed50778862267223ddb9c60ef5da68"
image_name="Windows 11 Enterprise LTSC 2024 Evaluation"
virtio_url="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.285-1/virtio-win-0.1.285.iso"
virtio_sha=""
webview2_url="https://go.microsoft.com/fwlink/?linkid=2124701"
npcap_url="https://npcap.com/dist/npcap-1.89.exe"
npcap_sha=""
ffmpeg_url=""
accelerator="kvm"
disk_interface="virtio"
disk_size_mb=40960
cpus=4
memory_mb=6144
compress=0
output_disk=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-dir) work="$2"; shift 2 ;;
    --iso-url) iso_url="$2"; shift 2 ;;
    --iso-sha256) iso_sha="${2,,}"; shift 2 ;;
    --image-name) image_name="$2"; shift 2 ;;
    --virtio-iso-url) virtio_url="$2"; shift 2 ;;
    --virtio-sha256) virtio_sha="${2,,}"; shift 2 ;;
    --webview2-url) webview2_url="$2"; shift 2 ;;
    --npcap-url) npcap_url="$2"; shift 2 ;;
    --npcap-sha256) npcap_sha="${2,,}"; shift 2 ;;
    --ffmpeg-url) ffmpeg_url="$2"; shift 2 ;;
    --accelerator) accelerator="$2"; shift 2 ;;
    --disk-interface) disk_interface="$2"; shift 2 ;;
    --disk-size-mb) disk_size_mb="$2"; shift 2 ;;
    --cpus) cpus="$2"; shift 2 ;;
    --memory-mb) memory_mb="$2"; shift 2 ;;
    --compress) compress=1; shift ;;
    --output-disk) output_disk="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$work" ]] || { usage >&2; exit 2; }
mkdir -p "$work"/{iso,installers}

echo "== verifying the ISO" >&2
inspect_args=(--url "$iso_url" --dest "$work/iso/windows.iso")
if [[ -n "$iso_sha" ]]; then
  inspect_args+=(--expected-sha256 "$iso_sha")
else
  echo "::warning::no ISO hash was pinned; recording the hash of the downloaded file instead" >&2
fi
inspect=$("$ROOT/scripts/inspect-iso.sh" "${inspect_args[@]}")
echo "$inspect" >&2
actual_sha=$(awk -F= '$1=="iso_sha256"{print $2}' <<<"$inspect")
editions=$(awk -F= '$1=="image_names"{print $2}' <<<"$inspect")

if ! tr ';' '\n' <<<"$editions" | grep -Fxq "$image_name"; then
  echo "::error::the ISO has no edition named '$image_name'; it offers:" >&2
  tr ';' '\n' <<<"$editions" >&2
  exit 1
fi
printf 'sha256:%s\n' "$actual_sha" >"$work/iso/checksum.txt"

echo "== rendering the answer file" >&2
# The driver paths and the driver CD must agree: setup treats a driver path
# that is not on the media as a fatal error.
driver_mode=none
[[ "$disk_interface" == "virtio" ]] && driver_mode=virtio
# The answer file, the WinRM bootstrap and the virtio drivers share one
# CD-ROM. Setup reads Autounattend.xml from any removable media root, so a
# single medium avoids a second drive letter that would shift between runs.
python3 "$ROOT/scripts/render-answer.py" \
  --template "$ROOT/packer/answer_files/Autounattend.xml.tpl" \
  --output "$ROOT/packer/generated/cd/Autounattend.xml" \
  --image-name "$image_name" \
  --drivers "$driver_mode"

echo "== fetching the installers" >&2
fetch() {
  local url=$1 dest=$2 expected=${3:-}
  [[ -s "$dest" ]] && return 0
  curl --fail --location --show-error --retry 5 --retry-all-errors \
    --connect-timeout 30 --output "$dest.tmp" "$url"
  if [[ -n "$expected" ]]; then
    echo "$expected  $dest.tmp" | sha256sum --check --strict
  fi
  mv "$dest.tmp" "$dest"
}
fetch "$virtio_url" "$work/installers/virtio-win.iso" "$virtio_sha"
fetch "$webview2_url" "$work/installers/WebView2Setup.exe"
fetch "$npcap_url" "$work/installers/npcap-installer.exe" "$npcap_sha"

# Only a virtio disk needs drivers. A SATA build ships none: setup fails on a
# driver path it cannot reach, and the extra tree only enlarges the medium.
drivers="$ROOT/packer/generated/cd/drivers"
rm -rf "$drivers"
if [[ "$driver_mode" == "virtio" ]]; then
  # The storage and network drivers are required -- without them the disk is
  # invisible or the guest has no network -- while the rest only remove
  # warnings.
  required_drivers=(viostor vioscsi NetKVM)
  optional_drivers=(Balloon vioserial)

  mkdir -p "$drivers"
  stage="$work/installers/drivers-stage"
  rm -rf "$stage"
  mkdir -p "$stage"

  stage_driver() {
    local name=$1 tree=$2
    7z x -y -o"$stage" "$work/installers/virtio-win.iso" "*${name}/${tree}/amd64/*" >/dev/null
    local source_dir
    source_dir=$(find "$stage" -type d -path "*/${name}/${tree}/amd64" | head -n1)
    [[ -n "$source_dir" ]] || return 1
    mkdir -p "$drivers/$name/$tree"
    cp -a "$source_dir" "$drivers/$name/$tree/amd64"
    return 0
  }

  for name in "${required_drivers[@]}"; do
    if ! stage_driver "$name" w11; then
      echo "::error::virtio-win has no ${name}/w11/amd64 tree" >&2
      exit 1
    fi
  done

  # A few components ship w10 only; Windows 11 uses the same driver.
  for name in "${optional_drivers[@]}"; do
    stage_driver "$name" w11 || stage_driver "$name" w10 ||
      echo "::warning::virtio-win has no ${name} tree for Windows 11" >&2
  done
  rm -rf "$stage"
fi

# The guest agent ships on the same medium and is uploaded directly, so the
# image does not need to keep the ISO mounted.
agent=$(7z l -ba "$work/installers/virtio-win.iso" |
  awk '$NF ~ /guest-agent\/qemu-ga-x86_64\.msi$/ {print $NF; exit}')
if [[ -z "$agent" ]]; then
  echo "::error::virtio-win has no qemu-ga-x86_64.msi" >&2
  exit 1
fi
mkdir -p "$work/installers/agent"
7z e -y -o"$work/installers/agent" "$work/installers/virtio-win.iso" "$agent" >/dev/null
guest_agent="$work/installers/agent/qemu-ga-x86_64.msi"

echo "== running packer" >&2
# Packer's own log is the only place the full qemu command line appears when
# the VM fails to start.
export PACKER_LOG="${PACKER_LOG:-1}"
# Packer refuses to build into a directory that already exists, so the output
# path is cleared instead of created.
outdir="$work/output"
rm -rf "$outdir"
pushd "$ROOT/packer" >/dev/null
packer init .
packer build \
  -var "iso_url=$work/iso/windows.iso" \
  -var "iso_checksum=$(cat "$work/iso/checksum.txt")" \
  -var "guest_agent_msi=$guest_agent" \
  -var "webview2_installer=$work/installers/WebView2Setup.exe" \
  -var "npcap_installer=$work/installers/npcap-installer.exe" \
  -var "image_name=$image_name" \
  -var "accelerator=$accelerator" \
  -var "disk_interface=$disk_interface" \
  -var "disk_size_mb=$disk_size_mb" \
  -var "cpus=$cpus" \
  -var "memory_mb=$memory_mb" \
  -var "ffmpeg_url=$ffmpeg_url" \
  -var "output_directory=$outdir" \
  .
popd >/dev/null

built="$outdir/windows-ltsc-2024"
[[ -f "$built" ]] || { echo "packer produced no disk at $built" >&2; exit 1; }

output_disk=${output_disk:-$work/disk.qcow2}
mkdir -p "$(dirname "$output_disk")"
if [[ "$compress" == "1" ]]; then
  qemu-img convert -p -O qcow2 -c "$built" "$output_disk"
else
  qemu-img convert -p -O qcow2 "$built" "$output_disk"
fi
qemu-img info "$output_disk" >&2
echo "disk=$output_disk"
echo "iso_sha256=$actual_sha"
