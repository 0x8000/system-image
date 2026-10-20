ARG UBUNTU_IMAGE=ubuntu:24.04
FROM ${UBUNTU_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG XWIN_VERSION=0.10.0
ARG XWIN_SHA256=d870eb4b2f390878af6da1ccd3cf321d22fcb72720984853b4be732ae597fc88
ARG XWIN_MANIFEST_URL=https://download.visualstudio.microsoft.com/download/pr/c95450be-0a45-4779-b142-33f567ccfd6e/f24aa010ba2fd5079d502e47bf40f5932f097df4bd716234dc68175b39649401/VisualStudio.17.Release.chman
ARG XWIN_MANIFEST_SHA256=4f0f290bb4d58a061a49a2fa893357a8c9e7e2b49fc91873f533ab8f791e4fa0
ARG MSVC_CRT_VERSION=14.44.17.14
ARG WINDOWS_SDK_VERSION=10.0.26100
ARG XWIN_DIR=/opt/xwin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      ca-certificates \
      clang-19 \
      cmake \
      curl \
      file \
      gzip \
      libclang-19-dev \
      lld-19 \
      llvm-19 \
      ninja-build \
      pkg-config \
      python3 \
      tar \
      unzip \
      wine \
      wine64 \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    test "$(dpkg --print-architecture)" = "amd64"; \
    xwin_prefix="xwin-${XWIN_VERSION}-x86_64-unknown-linux-musl"; \
    curl --fail --location --show-error \
      --retry 5 \
      --retry-all-errors \
      --connect-timeout 30 \
      --output /tmp/xwin.tar.gz \
      "https://github.com/Jake-Shadle/xwin/releases/download/${XWIN_VERSION}/${xwin_prefix}.tar.gz"; \
    echo "${XWIN_SHA256}  /tmp/xwin.tar.gz" | sha256sum --check --strict; \
    tar -xzf /tmp/xwin.tar.gz -C /tmp; \
    install -m 0755 "/tmp/${xwin_prefix}/xwin" /usr/local/bin/xwin; \
    rm -rf /tmp/xwin.tar.gz "/tmp/${xwin_prefix}"

RUN set -eux; \
    curl --fail --location --show-error \
      --retry 5 \
      --retry-all-errors \
      --connect-timeout 30 \
      --max-time 300 \
      --output /tmp/VisualStudio.chman \
      "${XWIN_MANIFEST_URL}"; \
    echo "${XWIN_MANIFEST_SHA256}  /tmp/VisualStudio.chman" | sha256sum --check --strict; \
    xwin --accept-license \
      --cache-dir /tmp/xwin-cache \
      --manifest /tmp/VisualStudio.chman \
      --arch x86_64 \
      --variant desktop \
      --crt-version "${MSVC_CRT_VERSION}" \
      --sdk-version "${WINDOWS_SDK_VERSION}" \
      --timeout 10m \
      --http-retry 5 \
      splat --output "${XWIN_DIR}"; \
    rm -rf /tmp/xwin-cache /tmp/VisualStudio.chman /usr/local/bin/xwin

RUN ln -sf /usr/lib/llvm-19/bin/clang /usr/local/bin/clang-cl \
    && ln -sf /usr/lib/llvm-19/bin/llvm-lib /usr/local/bin/llvm-lib \
    && ln -sf /usr/lib/llvm-19/bin/llvm-rc /usr/local/bin/llvm-rc

COPY windows/scripts/lld-link /usr/local/bin/lld-link
COPY windows/scripts/container-entrypoint.sh /usr/local/bin/container-entrypoint.sh
COPY windows/scripts/verify-image.sh /usr/local/bin/verify-image
COPY windows/cmake/x86_64-pc-windows-msvc-toolchain.cmake /opt/windows/cmake/x86_64-pc-windows-msvc-toolchain.cmake
COPY windows/cmake/override.cmake /opt/windows/cmake/override.cmake

RUN chmod 0755 \
      /usr/local/bin/lld-link \
      /usr/local/bin/container-entrypoint.sh \
      /usr/local/bin/verify-image

ENV CL_FLAGS="--target=x86_64-pc-windows-msvc -Wno-unused-command-line-argument -fuse-ld=lld-link /imsvc /opt/xwin/crt/include /imsvc /opt/xwin/sdk/include/ucrt /imsvc /opt/xwin/sdk/include/um /imsvc /opt/xwin/sdk/include/shared /imsvc /opt/xwin/sdk/include/winrt"
ENV CFLAGS_x86_64_pc_windows_msvc="${CL_FLAGS}"
ENV CXXFLAGS_x86_64_pc_windows_msvc="${CL_FLAGS} /EHsc"
ENV LIB="/opt/xwin/crt/lib/x86_64;/opt/xwin/sdk/lib/um/x86_64;/opt/xwin/sdk/lib/ucrt/x86_64"
ENV BINDGEN_EXTRA_CLANG_ARGS_x86_64_pc_windows_msvc="-I/opt/xwin/crt/include -I/opt/xwin/sdk/include/ucrt -I/opt/xwin/sdk/include/um -I/opt/xwin/sdk/include/shared -I/opt/xwin/sdk/include/winrt"
ENV RCFLAGS="-I/opt/xwin/crt/include -I/opt/xwin/sdk/include/ucrt -I/opt/xwin/sdk/include/um -I/opt/xwin/sdk/include/shared -I/opt/xwin/sdk/include/winrt"
ENV CMAKE_GENERATOR=Ninja
ENV CMAKE_TOOLCHAIN_FILE_x86_64_pc_windows_msvc=/opt/windows/cmake/x86_64-pc-windows-msvc-toolchain.cmake
ENV CC_x86_64_pc_windows_msvc=clang-cl
ENV CXX_x86_64_pc_windows_msvc=clang-cl
ENV AR_x86_64_pc_windows_msvc=llvm-lib
ENV RC_x86_64_pc_windows_msvc=llvm-rc
ENV TARGET_CC=clang-cl
ENV TARGET_CXX=clang-cl
ENV TARGET_AR=llvm-lib
ENV CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER=lld-link
ENV CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_AR=llvm-lib
ENV CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUNNER=wine
ENV LIBCLANG_PATH=/usr/lib/llvm-19/lib
ENV WINEDEBUG=-all
ENV CROSS_TARGET=x86_64-pc-windows-msvc

ENTRYPOINT ["/usr/local/bin/container-entrypoint.sh"]
CMD ["bash"]
