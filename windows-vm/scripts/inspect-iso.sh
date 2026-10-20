#!/usr/bin/env bash
# Verify one ISO and report the editions it can install.
#
# Packer can download and hash the ISO itself, but then a wrong URL or a wrong
# edition name only shows up halfway through a 40-minute install. Doing it here
# keeps the image build a pure "run the template" step and leaves the verified
# file in place so Packer does not download it a second time.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: inspect-iso.sh --url URL --dest FILE [--expected-sha256 HEX] [--checksum-out FILE]

prints:
  iso_sha256=<hex>
  image_names=<semicolon separated editions>
USAGE
}

url=""
dest=""
expected=""
checksum_out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) url="$2"; shift 2 ;;
    --dest) dest="$2"; shift 2 ;;
    --expected-sha256) expected="${2,,}"; shift 2 ;;
    --checksum-out) checksum_out="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$url" && -n "$dest" ]] || { usage >&2; exit 2; }

for tool in curl sha256sum 7z wiminfo; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

mkdir -p "$(dirname "$dest")"
if [[ -s "$dest" ]]; then
  echo "reusing $dest" >&2
else
  echo "downloading $url" >&2
  curl --fail --location --show-error --retry 5 --retry-all-errors \
    --connect-timeout 30 --continue-at - --output "$dest" "$url"
fi

actual=$(sha256sum "$dest" | cut -d' ' -f1)
echo "iso_sha256=$actual"
if [[ -n "$checksum_out" ]]; then
  printf 'sha256:%s\n' "$actual" >"$checksum_out"
fi
if [[ -n "$expected" && "$actual" != "$expected" ]]; then
  echo "checksum mismatch: expected $expected, got $actual" >&2
  exit 1
fi

# wimlib reads both install.wim and the compressed install.esd that newer
# media ships, and prints the edition names setup matches on.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
member=$(7z l -ba "$dest" | awk '$NF ~ /sources\/install\.(wim|esd)$/ {print $NF; exit}')
if [[ -z "$member" ]]; then
  echo "the ISO holds no sources/install.wim or sources/install.esd" >&2
  exit 1
fi
7z e -y -o"$work" "$dest" "$member" >/dev/null
image=$(find "$work" -maxdepth 1 \( -name 'install.wim' -o -name 'install.esd' \) | head -n1)

names=$(wiminfo "$image" | awk -F': *' '
  /^Name: / {printf "%s%s", (count++ ? ";" : ""), $2}
')
if [[ -z "$names" ]]; then
  echo "could not read any edition name out of $member" >&2
  exit 1
fi
echo "image_names=$names"
