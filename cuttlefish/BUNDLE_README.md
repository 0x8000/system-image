# Cuttlefish @VERSION@ portable bundle (@ARCH@)

This is a single, self-contained Cuttlefish host bundle: a Debian 13 rootfs
with `cuttlefish-base` + `cuttlefish-user` (including `cvd`, `crosvm`, the
host-side orchestrator and every runtime dependency) plus a `cvd` wrapper.
Nothing is installed on your system by extraction alone.

Built from [google/android-cuttlefish](`@REF@`) at commit `@COMMIT@`,
packaged `@BUILT@`. The wrapper sources and packages are provided by this
repository's CI; Cuttlefish itself is Apache-2.0 upstream.

## Requirements

- `@ARCH@` Linux with KVM (`/dev/kvm` must exist; enable VT-x/AMD-V in the BIOS)
- `sudo` (the wrapper re-executes itself as root: Cuttlefish must configure
  bridges, tap devices, nftables and DHCP in the host network namespace)
- `util-linux` (`unshare`, `setpriv`), `tar` + `zstd` for the `.run` variant
- roughly 6 GB of disk after extraction (bundle + downloaded Android images)

## Quick start

```sh
tar --zstd -xf cuttlefish-@VERSION@-@ARCH@.tar.zst      # or: sh cuttlefish-@VERSION@-@ARCH@.run
cd cuttlefish-@VERSION@-@ARCH@
./cvd --setup                 # host setup (also runs automatically on first cvd call)

mkdir /tmp/cf-work && cd /tmp/cf-work
~/cuttlefish-@VERSION@-@ARCH@/cvd fetch \
  --default_build=aosp-android-latest-release/aosp_cf_@ARCH@_only_phone-userdebug
~/cuttlefish-@VERSION@-@ARCH@/cvd create --product_path="$PWD"
~/cuttlefish-@VERSION@-@ARCH@/cvd status
~/cuttlefish-@VERSION@-@ARCH@/cvd stop
```

`cvd fetch` downloads public AOSP artifacts anonymously; for private branches
configure credentials as documented upstream (`cvd fetch --help`).

## What the wrapper does

- `./cvd <cvd arguments>` runs everything **inside the bundle rootfs** with a
  private mount namespace: host `/dev`, `/sys`, `/proc` are bound in, your
  `$HOME` (and other "user data" paths like `/tmp`, `/`) are mounted at their
  real paths, and the bundled `cvd` runs as your user (not root) with the
  correct supplementary groups.
- `./cvd --setup` performs the one-time host configuration:
  - loads `tun`, `vhost_net`, `vhost_vsock`, `vhci-hcd`, `bridge` modules,
  - sets file capabilities on the rootfs `cvdalloc` / `cvd_refresh_groups`,
  - registers upstream's udev rules and fixes `/dev/vhost-*` permissions,
  - creates the `cvd-ebr` / `cvd-wbr` bridges, tap devices, DHCP servers and
    NAT rules by running the package's `cuttlefish-host-resources` init script.
- `./cvd --teardown` removes the bridges/taps/dnsmasq instances.
- `./cvd --shell` gives you a shell inside the rootfs for debugging.
- `./cvd --bundle-info` / `./cvd --bundle-help` show bundle metadata/help.

State that outlives individual commands lives in the host network namespace
(bridges/taps) and inside the rootfs (`rootfs/run/CUTTLEFISH_*`, scripts).
Instance disks, logs and `~/.cvd` stay in your real home directory.

## Environment knobs

| Variable | Meaning |
| --- | --- |
| `CUTTLEFISH_BUNDLE_SUDO=0` | Do not re-exec via sudo (must already be root) |
| `CUTTLEFISH_BUNDLE_NO_SETUP=1` | Skip automatic host setup |
| `CUTTLEFISH_BUNDLE_ROOT=DIR` | Point the wrapper at a different `rootfs` |

## Caveats

- Not built to run **inside** Docker (Cuttlefish needs to own parts of the
  host kernel and network). Run it directly on a Linux machine or VM.
- Kernel modules are best-effort; most kernels ship `vhost_net` /
  `vhost_vsock` / `vhci-hcd` as modules and `modprobe` handles them.
- GPU acceleration needs the host graphics stack; without it Cuttlefish falls
  back to SwiftShader (slower but functional).
- The udev rules address Google's USB aidt network gadget; harmless elsewhere.
- Do not run bundles you didn't build: the wrapper intentionally executes
  code in the extracted rootfs. Extract a fresh copy per untrusted source.
- Restarting the host removes the bridges/taps/dnsmasq; re-run `./cvd --setup`.

## Why root?

Cuttlefish's virtual devices attach to mac80211_hwsim radio bridges that live
in the host network namespace — creating `cvd-ebr`/`cvd-wbr`, tap device pairs
and DNS/NAT rules requires `CAP_NET_ADMIN`. `cvdalloc` carries that capability
as a *file* capability for per-instance taps, but the one-time bridge setup is
root territory. This matches how the upstream Debian packages behave; the
wrapper simply makes that transparent.
