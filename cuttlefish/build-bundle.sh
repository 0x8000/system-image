#!/usr/bin/env bash
#
# Build a portable Cuttlefish bundle.
#
# Inputs: the cuttlefish-base/cuttlefish-user .deb packages produced by
# tools/buildutils/cw (upstream's build container), plus this script's
# directory for the wrapper and README template.
#
# Output (under --dist):
#   cuttlefish-<version>-<arch>.tar.zst        rootfs + wrapper, for tar --zstd -xf
#   cuttlefish-<version>-<arch>.tar.zst.sha256
#   cuttlefish-<version>-<arch>.run            self-extracting variant of the tarball
#   cuttlefish-<version>-<arch>.run.sha256
#
# The stage layout is:
#   <stage>/cvd       wrapper that runs everything inside rootfs/
#   <stage>/rootfs/   Debian rootfs with cuttlefish-base + cuttlefish-user
#   <stage>/README.md
#   <stage>/VERSION,  <stage>/ARCH
#
# Run from CI inside a debian:13 container (needs debootstrap, zstd, dpkg).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

log() { printf '%s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
usage: build-bundle.sh --debs DIR --dist DIR --ref REF --commit SHA [--version V]
                       [--arch amd64|x86_64] [--suite trixie] [--mirror URL]
EOF
  exit 2
}

debs=""
dist=""
version=""
ref=""
commit=""
suite="trixie"
mirror="http://deb.debian.org/debian"
dpkg_arch="amd64"
kernel_arch="x86_64"

while [ $# -gt 0 ]; do
  case "$1" in
    --debs)    debs="${2:?}";    shift 2 ;;
    --dist)    dist="${2:?}";    shift 2 ;;
    --version) version="${2:?}"; shift 2 ;;
    --ref)     ref="${2:?}";     shift 2 ;;
    --commit)  commit="${2:?}";  shift 2 ;;
    --arch)
      case "${2:?}" in
        amd64|x86_64)  dpkg_arch=amd64;  kernel_arch=x86_64  ;;
        arm64|aarch64) dpkg_arch=arm64;  kernel_arch=aarch64 ;;
        *) die "unsupported --arch: $2" ;;
      esac
      shift 2
      ;;
    --suite)  suite="${2:?}";  shift 2 ;;
    --mirror) mirror="${2:?}"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$debs" ]  && [ -n "$dist" ]   && [ -n "$ref" ] && [ -n "$commit" ] || usage
[ -n "${version:-}" ] || true

[ "$(id -u)" -eq 0 ] || die "must run as root"
for tool in debootstrap zstd dpkg-deb tar sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required"
done
host_arch="$(dpkg --print-architecture)"
[ "$dpkg_arch" = "$host_arch" ] || \
  die "cross-arch bootstrap is not supported (host is $host_arch, wanted $dpkg_arch)"

# ---- Locate the packages -----------------------------------------------------

[ -d "$debs" ] || die "--debs is not a directory: $debs"
base_deb="$(find "$debs" -maxdepth 1 -name "cuttlefish-base_*_${dpkg_arch}.deb" | sort | tail -n1)"
user_deb="$(find "$debs" -maxdepth 1 -name "cuttlefish-user_*_${dpkg_arch}.deb" | sort | tail -n1)"
[ -n "$base_deb" ] || die "no cuttlefish-base_*_${dpkg_arch}.deb in $debs"
[ -n "$user_deb" ] || die "no cuttlefish-user_*_${dpkg_arch}.deb in $debs"

if [ -z "$version" ]; then
  version="$(dpkg-deb -f "$base_deb" Version)"
  [ -n "$version" ] || die "cannot read version from $base_deb"
fi
clean_version="$(printf '%s' "$version" | tr ':/' '__')"
log "building cuttlefish bundle: version=$version arch=$dpkg_arch ref=$ref commit=${commit:0:12}"

# ---- Stage -------------------------------------------------------------------

rm -rf "$dist"
mkdir -p "$dist"
stage_name="cuttlefish-${clean_version}-${kernel_arch}"
stage="$dist/$stage_name"
rootfs="$stage/rootfs"
mkdir -p "$stage"

# ---- Debian rootfs -----------------------------------------------------------

log "bootstrapping $suite ($dpkg_arch)"
debootstrap --variant=minbase --arch="$dpkg_arch" "$suite" "$rootfs" "$mirror"

# A well-formed sources.list: security repo is only correct for the default
# mirror, so custom mirrors get the base repo only.
{
  printf 'deb %s %s main\n' "$mirror" "$suite"
  printf 'deb %s %s-updates main\n' "$mirror" "$suite"
  case "$mirror" in
    *deb.debian.org*) printf 'deb http://security.debian.org/debian-security %s-security main\n' "$suite" ;;
  esac
} > "$rootfs/etc/apt/sources.list"

cp /etc/resolv.conf "$rootfs/etc/resolv.conf" 2>/dev/null || true

# Stop dpkg from trying to run services during configuration.
printf '#!/bin/sh\nexit 101\n' > "$rootfs/usr/sbin/policy-rc.d"
chmod 755 "$rootfs/usr/sbin/policy-rc.d"

mkdir -p "$rootfs/tmp/cuttlefish-debs"
cp -f "$base_deb" "$user_deb" "$rootfs/tmp/cuttlefish-debs/"

log "installing cuttlefish packages and runtime dependencies"
chroot "$rootfs" env DEBIAN_FRONTEND=noninteractive bash -eux -c '
  apt-get update -qq
  apt-get install -y --no-install-recommends \
    /tmp/cuttlefish-debs/cuttlefish-base_*.deb \
    /tmp/cuttlefish-debs/cuttlefish-user_*.deb \
    ca-certificates curl passwd procps zstd kmod
  apt-get clean
'

# The cuttlefish-host-resources init script sources /lib/lsb/init-functions.
# That file lives in lsb-base, which newer Debian releases may not carry, so
# fall back to a minimal stub rather than shipping a broken bundle.
if [ ! -e "$rootfs/lib/lsb/init-functions" ]; then
  chroot "$rootfs" env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends lsb-base || true
fi
if [ ! -e "$rootfs/lib/lsb/init-functions" ]; then
  mkdir -p "$rootfs/lib/lsb"
  cat > "$rootfs/lib/lsb/init-functions" <<'EOF'
# Minimal LSB init-functions stub for the Cuttlefish bundle.
log_success_msg()  { echo "$*"; }
log_failure_msg()  { echo "$*" >&2; }
log_warning_msg()  { echo "$*" >&2; }
log_action_msg()   { echo "$*"; }
log_begin_msg()    { echo "$*"; }
log_end_msg()      { echo "$*"; }
log_daemon_msg()   { echo "$*"; }
log_progress_msg() { echo "$*"; }
EOF
fi

# ---- Sanity checks -----------------------------------------------------------

check() {
  if [ ! -e "$rootfs/$1" ]; then
    die "bundle sanity check failed: $rootfs/$1 is missing"
  fi
}
check "usr/lib/cuttlefish-common/bin/cvd"
check "usr/lib/cuttlefish-common/bin/crosvm"
check "usr/lib/cuttlefish-common/bin/cvdalloc"
check "usr/lib/cuttlefish-common/bin/cvd_refresh_groups"
check "etc/init.d/cuttlefish-host-resources"
check "usr/bin/setpriv"
check "usr/sbin/setcap"
check "usr/sbin/useradd"
check "usr/sbin/usermod"
check "lib/lsb/init-functions"
log "sanity checks passed"

# ---- Cleanup -----------------------------------------------------------------

rm -f "$rootfs/usr/sbin/policy-rc.d"
rm -rf "$rootfs/tmp/cuttlefish-debs"
find "$rootfs/var/lib/apt/lists" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
for d in "var/cache/apt" "var/log" "var/backups" "var/tmp" "tmp" \
         "usr/share/doc" "usr/share/man" "usr/share/info" "usr/share/lintian" \
         "dev" "proc" "sys" "run"; do
  find "$rootfs/$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
done
rm -f "$rootfs/.dockerenv"
# Restore the resolver: /run was emptied above, so a resolv.conf symlink
# pointing into it must be replaced with a real file.
rm -f "$rootfs/etc/resolv.conf"
cp /etc/resolv.conf "$rootfs/etc/resolv.conf" 2>/dev/null || true

# ---- Stage files --------------------------------------------------------------

install -m 0755 "$SCRIPT_DIR/cvd" "$stage/cvd"
printf '%s\n' "$kernel_arch" > "$stage/ARCH"
built_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  printf '%s\n' "$version"
  printf 'ref: %s\n' "$ref"
  printf 'commit: %s\n' "$commit"
  printf 'built: %s\n' "$built_utc"
} > "$stage/VERSION"

sed \
  -e "s|@VERSION@|$clean_version|g" \
  -e "s|@RAW_VERSION@|$version|g" \
  -e "s|@REF@|$ref|g" \
  -e "s|@COMMIT@|$commit|g" \
  -e "s|@ARCH@|$kernel_arch|g" \
  -e "s|@BUILT@|$built_utc|g" \
  "$SCRIPT_DIR/BUNDLE_README.md" > "$stage/README.md"

# ---- Tarball -----------------------------------------------------------------

asset="$dist/$stage_name.tar.zst"
log "packing $asset"
tar \
  --numeric-owner --owner=0 --group=0 \
  --xattrs --xattrs-include='security.capability' \
  -cf - -C "$dist" "$stage_name" | zstd -T0 -12 -o "$asset"

# ---- Self-extracting variant ---------------------------------------------------

run_header="$(mktemp)"
cat > "$run_header" <<'EOF'
#!/bin/sh
# Self-extracting portable Cuttlefish bundle. Extracts into the current
# directory and prints the next steps.
set -eu
if ! command -v zstd >/dev/null 2>&1; then
  echo "error: zstd is required to unpack this bundle (e.g. apt install zstd)" >&2
  exit 1
fi
if ! command -v tar >/dev/null 2>&1; then
  echo "error: tar is required to unpack this bundle" >&2
  exit 1
fi
PAYLOAD_LINE=__PAYLOAD_LINE__
tail -n +"$PAYLOAD_LINE" "$0" | zstd -d | tar -xf -
exit $?
EOF
# The payload starts right after the marker line.
payload_line=$(( $(wc -l < "$run_header") + 2 ))
sed -i "s/__PAYLOAD_LINE__/$payload_line/" "$run_header"

run_file="$dist/$stage_name.run"
{
  cat "$run_header"
  echo '#__CUTTLEFISH_TARZST_PAYLOAD__'
  cat "$asset"
} > "$run_file"
chmod 0755 "$run_file"
rm -f "$run_header"

# ---- Checksums + summary ------------------------------------------------------

(
  cd "$dist"
  sha256sum "$stage_name.tar.zst" > "$stage_name.tar.zst.sha256"
  sha256sum "$stage_name.run" > "$stage_name.run.sha256"
)

log "bundle:"
du -sh "$stage/rootfs" "$asset" "$run_file"
ls -lh "$dist"
