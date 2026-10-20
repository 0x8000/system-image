# system-image

Reusable Linux-hosted cross-compilation images for macOS on Apple Silicon.

The image contains only the reusable system layer:

- Ubuntu 24.04
- clang, LLVM, CMake, and the osxcross runtime/build dependencies
- osxcross pinned to a commit
- a checksum-verified macOS SDK
- an entrypoint that exports the compiler variables expected by Cargo and
  `cc-rs`

It intentionally does not contain project-specific tools such as `xidlc`,
`protoc`, or a database client library. Projects can derive from this image and
add those tools in their own repository.

## Local build

```sh
make build
make verify
make smoke
```

To use a local SDK mirror without changing the Dockerfile:

```sh
make build BUILD_ARGS='--network host --build-arg MACOS_SDK_URL=http://127.0.0.1:18080/MacOSX15.5.sdk.tar.xz'
```

The default image is `ghcr.io/0x8000/system-image:macos-15.5`.

## Use from `cross`

```toml
[target.aarch64-apple-darwin]
image = "ghcr.io/0x8000/system-image:macos-15.5"
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

## Add project tools

Keep the base image generic and derive a project image when additional tools are
needed:

```dockerfile
FROM ghcr.io/0x8000/system-image:macos-15.5

ARG XIDLC_VERSION=0.95.0
RUN curl --fail --location \
      "https://github.com/xidl/xidl/releases/download/v${XIDLC_VERSION}/xidlc-x86_64-unknown-linux-musl.tar.gz" \
      | tar -xz -C /usr/local/bin xidlc \
    && chmod 0755 /usr/local/bin/xidlc
```

Then point `Cross.toml` at the derived image. The base image remains reusable by
other projects and the project-specific layer changes independently.

## Publishing

The workflow validates every Dockerfile change. On pushes to `main` it publishes
to GitHub Container Registry as:

- `ghcr.io/0x8000/system-image:macos-15.5`
- `ghcr.io/0x8000/system-image:sha-<commit>`

Publishing requires the repository to allow GitHub Actions to write packages.
