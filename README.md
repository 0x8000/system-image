# system-image

Reusable Linux-hosted cross-compilation images for macOS and Windows.

The images contain only the reusable system layer. They intentionally do not
contain project-specific tools such as `xidlc`, `protoc`, or a database client
library. Projects can derive from an image and add those tools in their own
repository.

## Images

| Target | Image | Tag |
| --- | --- | --- |
| `aarch64-apple-darwin` | `ghcr.io/0x8000/aarch64-apple-darwin` | `macos-15.5` |
| `aarch64-apple-darwin` | `ghcr.io/0x8000/aarch64-apple-darwin` | `macos-26.1` |
| `x86_64-pc-windows-msvc` | `ghcr.io/0x8000/x86_64-pc-windows-msvc` | `msvc-14.44.17.14` |

The Windows package is private because the MSVC CRT and Windows SDK are not
publicly redistributable. Authenticate to GHCR before pulling it.

## macOS

The macOS image contains:

- Ubuntu 24.04
- clang, LLVM, CMake, and the osxcross runtime/build dependencies
- osxcross pinned to a commit
- a checksum-verified macOS SDK
- an entrypoint that exports the compiler variables expected by Cargo and
  `cc-rs`

## Local build

```sh
# Build default macOS image (macos-15.5)
make build
make verify
make smoke

# Build macOS 15.5 image explicitly
make macos-15-build
make macos-15-verify
make macos-15-smoke

# Build macOS 26.1 image
make macos-26-build
make macos-26-verify
make macos-26-smoke
```

For the Windows image:

```sh
make windows-build
make windows-verify
make windows-smoke
```

Run all verification suites with `make verify-all`.

To use a local SDK mirror without changing the Dockerfile:

```sh
make build BUILD_ARGS='--network host --build-arg MACOS_SDK_URL=http://127.0.0.1:18080/MacOSX15.5.sdk.tar.xz'
make macos-26-build BUILD_ARGS='--network host --build-arg MACOS_SDK_URL=http://127.0.0.1:18080/MacOSX26.1.sdk.tar.xz'
```

The default image is `ghcr.io/0x8000/aarch64-apple-darwin:macos-15.5`.

## Windows

The Windows image follows the `cargo-xwin` approach:

- `xwin` downloads and splats the MSVC CRT and Windows SDK
- `clang-cl` compiles C and C++
- `lld-link` links
- `llvm-lib` creates static libraries
- Wine runs Windows test executables; it is not used for compilation

The toolchain is pinned to MSVC CRT `14.44.17.14` and Windows SDK
`10.0.26100`. The image includes a CMake toolchain file and the environment
variables used by Cargo, `cc-rs`, bindgen, and CMake.

## Use from `cross`

```toml
[target.aarch64-apple-darwin]
image = "ghcr.io/0x8000/aarch64-apple-darwin:macos-15.5"
pre-build = []

[target.x86_64-pc-windows-msvc]
image = "ghcr.io/0x8000/x86_64-pc-windows-msvc:msvc-14.44.17.14"
pre-build = []
```

The entrypoint exports:

```text
CC_aarch64_apple_darwin
CXX_aarch64_apple_darwin
AR_aarch64_apple_darwin
CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER
CARGO_TARGET_AARCH64_APPLE_DARWIN_AR
```

The Windows entrypoint exports:

```text
CC_x86_64_pc_windows_msvc
CXX_x86_64_pc_windows_msvc
AR_x86_64_pc_windows_msvc
RC_x86_64_pc_windows_msvc
CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER
CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_AR
CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUNNER
```

## Add project tools

Keep the base image generic and derive a project image when additional tools are
needed:

```dockerfile
FROM ghcr.io/0x8000/aarch64-apple-darwin:macos-15.5

ARG XIDLC_VERSION=0.95.0
RUN curl --fail --location \
      "https://github.com/xidl/xidl/releases/download/v${XIDLC_VERSION}/xidlc-x86_64-unknown-linux-musl.tar.gz" \
      | tar -xz -C /usr/local/bin xidlc \
    && chmod 0755 /usr/local/bin/xidlc
```

Then point `Cross.toml` at the derived image. The base image remains reusable by
other projects and the project-specific layer changes independently.

## Cuttlefish portable bundle

`cuttlefish/` builds and ships the [google/android-cuttlefish](https://github.com/google/android-cuttlefish)
virtual Android stack as a single self-contained download for Linux hosts. The
bundle is a Debian 13 rootfs with the upstream `cuttlefish-base` and
`cuttlefish-user` packages (`cvd`, `crosvm`, the orchestrator, and every runtime
dependency) plus a `cvd` wrapper that runs the whole stack inside the rootfs and
performs the required host setup (kernel modules, udev rules, `cvd-ebr`/`cvd-wbr`
bridges, DHCP; re-executing via `sudo` when needed). Nothing is installed on the
host by extraction alone; instance disks, logs, and `~/.cvd` stay in `$HOME`.

- `cuttlefish/cvd` — the wrapper that runs everything inside `rootfs/`
- `cuttlefish/build-bundle.sh` — assembles the rootfs (debootstrap + debs) and
  produces `cuttlefish-<version>-x86_64.tar.zst` and a self-extracting `.run`
- `cuttlefish/BUNDLE_README.md` — user guide shipped inside every bundle
- `.github/workflows/cuttlefish.yml` — CI: builds upstream debs in its own build
  container, packs the bundle in a `debian:13` container, and publishes a GitHub
  release tagged `cuttlefish-<ref>`; weekly cron picks up new upstream tags and
  skips existing releases, or run it manually with `workflow_dispatch`

Why not AppImage or Docker? AppImage cannot represent this workload: the stack
is dozens of cooperating processes calling each other by absolute paths, needs
file capabilities that squashfs/FUSE does not carry, and must configure host
network state regardless of the packaging format. A plain rootfs + wrapper
needs no extra dependencies and stays out of the way of `sudo` access.

## Publishing

The workflow validates every image change. On pushes to `main` it publishes to
GitHub Container Registry as:

- `ghcr.io/0x8000/aarch64-apple-darwin:macos-15.5`
- `ghcr.io/0x8000/aarch64-apple-darwin:macos-15.5-sha-<commit>`
- `ghcr.io/0x8000/aarch64-apple-darwin:macos-26.1`
- `ghcr.io/0x8000/aarch64-apple-darwin:macos-26.1-sha-<commit>`
- `ghcr.io/0x8000/x86_64-pc-windows-msvc:msvc-14.44.17.14`
- `ghcr.io/0x8000/x86_64-pc-windows-msvc:msvc-14.44.17.14-sha-<commit>`

You can also manually trigger the `Publish image` workflow via `workflow_dispatch`
and specify which image version to build (e.g. `all`, `macos-15.5`, `macos-26.1`, or `msvc-14.44.17.14`).

Publishing requires the repository to allow GitHub Actions to write packages.
