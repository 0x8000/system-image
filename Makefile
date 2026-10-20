MACOS_IMAGE ?= ghcr.io/0x8000/aarch64-apple-darwin
MACOS_15_TAG ?= macos-15.5
MACOS_26_TAG ?= macos-26.1
MACOS_TAG ?= $(MACOS_15_TAG)
WINDOWS_IMAGE ?= ghcr.io/0x8000/x86_64-pc-windows-msvc
WINDOWS_TAG ?= msvc-14.44.17.14

IMAGE ?= $(MACOS_IMAGE)
TAG ?= $(MACOS_TAG)
DOCKERFILE ?= macos/Dockerfile
PLATFORM ?= linux/amd64
BUILD_DIR ?= .build
BUILD_ARGS ?=

.PHONY: build verify smoke \
	macos-15-build macos-15-verify macos-15-smoke \
	macos-26-build macos-26-verify macos-26-smoke \
	windows-build windows-verify windows-smoke \
	verify-all clean

build:
	docker buildx build \
		--platform "$(PLATFORM)" \
		$(BUILD_ARGS) \
		--file "$(DOCKERFILE)" \
		--tag "$(IMAGE):$(TAG)" \
		--load \
		.

verify: build
	docker run --rm --platform "$(PLATFORM)" "$(IMAGE):$(TAG)" \
		/usr/local/bin/verify-image

smoke: build
	mkdir -p "$(BUILD_DIR)"
	printf '%s\n' \
		'#include <stdio.h>' \
		'int main(void) {' \
		'  puts("hello from macOS");' \
		'  return 0;' \
		'}' > "$(BUILD_DIR)/hello.c"
	docker run --rm --platform "$(PLATFORM)" \
		--volume "$(CURDIR)/$(BUILD_DIR):/workspace" \
		--workdir /workspace \
		"$(IMAGE):$(TAG)" \
		bash -ec '$$CC_aarch64_apple_darwin -O2 hello.c -o hello && file hello && $${CC_aarch64_apple_darwin%clang}otool -l hello | grep -A2 LC_BUILD_VERSION'

macos-15-build:
	$(MAKE) build \
		IMAGE="$(MACOS_IMAGE)" \
		TAG="$(MACOS_15_TAG)" \
		DOCKERFILE=macos/Dockerfile \
		BUILD_ARGS="--build-arg MACOS_SDK_VERSION=15.5 $(BUILD_ARGS)"

macos-15-verify: macos-15-build
	docker run --rm --platform "$(PLATFORM)" "$(MACOS_IMAGE):$(MACOS_15_TAG)" \
		/usr/local/bin/verify-image

macos-15-smoke: macos-15-build
	$(MAKE) smoke IMAGE="$(MACOS_IMAGE)" TAG="$(MACOS_15_TAG)"

macos-26-build:
	$(MAKE) build \
		IMAGE="$(MACOS_IMAGE)" \
		TAG="$(MACOS_26_TAG)" \
		DOCKERFILE=macos/Dockerfile \
		BUILD_ARGS="--build-arg MACOS_SDK_VERSION=26.1 $(BUILD_ARGS)"

macos-26-verify: macos-26-build
	docker run --rm --platform "$(PLATFORM)" "$(MACOS_IMAGE):$(MACOS_26_TAG)" \
		/usr/local/bin/verify-image

macos-26-smoke: macos-26-build
	$(MAKE) smoke IMAGE="$(MACOS_IMAGE)" TAG="$(MACOS_26_TAG)"

windows-build:
	$(MAKE) build \
		IMAGE="$(WINDOWS_IMAGE)" \
		TAG="$(WINDOWS_TAG)" \
		DOCKERFILE=windows/Dockerfile

windows-verify: windows-build
	docker run --rm --platform "$(PLATFORM)" "$(WINDOWS_IMAGE):$(WINDOWS_TAG)" \
		/usr/local/bin/verify-image

windows-smoke: windows-build
	mkdir -p "$(BUILD_DIR)/windows"
	printf '%s\n' \
		'#include <stdio.h>' \
		'int main(void) {' \
		'  puts("hello from Windows");' \
		'  return 0;' \
		'}' > "$(BUILD_DIR)/windows/hello.c"
	docker run --rm --platform "$(PLATFORM)" \
		--volume "$(CURDIR)/$(BUILD_DIR)/windows:/workspace" \
		--workdir /workspace \
		"$(WINDOWS_IMAGE):$(WINDOWS_TAG)" \
		bash -ec 'clang-cl $$CL_FLAGS hello.c /Fe:hello.exe && file hello.exe && wine hello.exe'

verify-all: macos-15-verify macos-26-verify windows-verify

clean:
	rm -rf "$(BUILD_DIR)"
