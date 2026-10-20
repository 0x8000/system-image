IMAGE ?= ghcr.io/0x8000/aarch64-apple-darwin
TAG ?= macos-15.5
PLATFORM ?= linux/amd64
BUILD_DIR ?= .build
BUILD_ARGS ?=

.PHONY: build verify smoke clean

build:
	docker buildx build \
		--platform "$(PLATFORM)" \
		$(BUILD_ARGS) \
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
		bash -ec '$$CC_aarch64_apple_darwin -O2 hello.c -o hello && file hello && aarch64-apple-darwin24.5-otool -l hello | grep -A2 LC_BUILD_VERSION'

clean:
	rm -rf "$(BUILD_DIR)"
