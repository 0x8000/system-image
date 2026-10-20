ARG UBUNTU_IMAGE=ubuntu:24.04
FROM ${UBUNTU_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG OSXCROSS_REPOSITORY=https://github.com/tpoechtrager/osxcross.git
ARG OSXCROSS_REVISION=27d21e4977c9751d01199c7a226a6faf494c3dd9
ARG MACOS_SDK_VERSION=15.5
ARG MACOS_SDK_URL=https://github.com/joseluisq/macosx-sdks/releases/download/15.5/MacOSX15.5.sdk.tar.xz
ARG MACOS_SDK_SHA256=c15cf0f3f17d714d1aa5a642da8e118db53d79429eb015771ba816aa7c6c1cbd
ARG OSXCROSS_BUILD_FLAVOR=stable
ARG OSXCROSS_DEPLOYMENT_TARGET=11.0
ARG OSXCROSS_TARGET_DIR=/opt/osxcross

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      bzip2 \
      ca-certificates \
      clang \
      cmake \
      cpio \
      curl \
      file \
      g++ \
      gcc \
      git \
      libbz2-dev \
      libclang-dev \
      libssl-dev \
      libxml2-dev \
      liblzma-dev \
      lld \
      llvm \
      llvm-dev \
      make \
      patch \
      perl \
      pkg-config \
      python3 \
      sed \
      tar \
      uuid-dev \
      xz-utils \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --filter=blob:none "${OSXCROSS_REPOSITORY}" /tmp/osxcross \
    && git -C /tmp/osxcross checkout --detach "${OSXCROSS_REVISION}" \
    && mkdir -p /tmp/osxcross/tarballs \
    && curl --fail --location --show-error \
      --retry 5 \
      --retry-all-errors \
      --connect-timeout 30 \
      --max-time 900 \
      --output "/tmp/osxcross/tarballs/MacOSX${MACOS_SDK_VERSION}.sdk.tar.xz" \
      "${MACOS_SDK_URL}" \
    && echo "${MACOS_SDK_SHA256}  /tmp/osxcross/tarballs/MacOSX${MACOS_SDK_VERSION}.sdk.tar.xz" \
      | sha256sum --check --strict \
    && UNATTENDED=1 \
      BUILD_FLAVOR="${OSXCROSS_BUILD_FLAVOR}" \
      TARGET_DIR="${OSXCROSS_TARGET_DIR}" \
      OSX_VERSION_MIN="${OSXCROSS_DEPLOYMENT_TARGET}" \
      /tmp/osxcross/build.sh \
    && rm -rf /tmp/osxcross

COPY scripts/container-entrypoint.sh /usr/local/bin/container-entrypoint.sh
COPY scripts/verify-image.sh /usr/local/bin/verify-image
RUN chmod 0755 \
      /usr/local/bin/container-entrypoint.sh \
      /usr/local/bin/verify-image

ENV PATH="/opt/osxcross/bin:${PATH}"
ENV OSXCROSS_TARGET_DIR=/opt/osxcross
ENV OSXCROSS_SDK_VERSION=15.5
ENV SDKROOT=/opt/osxcross/SDK/MacOSX15.5.sdk
ENV MACOSX_DEPLOYMENT_TARGET=11.0
ENV LIBCLANG_PATH=/usr/lib/llvm-18/lib
ENV BINDGEN_EXTRA_CLANG_ARGS_aarch64_apple_darwin="--sysroot=/opt/osxcross/SDK/MacOSX15.5.sdk"
ENV CROSS_TARGET=aarch64-apple-darwin

ENTRYPOINT ["/usr/local/bin/container-entrypoint.sh"]
CMD ["bash"]
