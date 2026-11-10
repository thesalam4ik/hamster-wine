#!/bin/sh
# Build the Khronos Vulkan-Loader as a universal libvulkan.1.dylib and place it beside Wine's
# x86_64 dylibs ($DEPS/lib), so a Wine built --with-vulkan dlopens it.
#
# Why the loader and not MoltenVK directly: the loader reads VK_ICD_FILENAMES at runtime and
# dispatches to the chosen ICD (MoltenVK or KosmicKrisp), which is what GameSettings.vulkanDriver
# selects. Loading MoltenVK directly would freeze the driver at build time.
#
# Universal (x86_64 + arm64) so the x86_64 Wine loads it and an arm64 build could too. Pinned by tag.
# Environment: HAMSTER_WORK, JOBS.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/lib.sh"

TAG=vulkan-sdk-1.4.363.0
SRC_VK="$WORK/vulkan-loader/$TAG"
OUT="$DEPS/lib/libvulkan.1.dylib"

if [ -f "$OUT" ] && [ "$(cat "$WORK/vulkan-loader/.tag" 2>/dev/null)" = "$TAG" ]; then
  info "Vulkan-Loader $TAG already built: $OUT"
  exit 0
fi

if [ ! -d "$SRC_VK/.git" ]; then
  info "Cloning Vulkan-Loader $TAG"
  rm -rf "$SRC_VK"
  mkdir -p "$(dirname "$SRC_VK")"
  git clone --depth 1 --branch "$TAG" https://github.com/KhronosGroup/Vulkan-Loader.git "$SRC_VK"
fi

info "Building universal libvulkan.1.dylib (log: $WORK/vulkan-loader/build.log)"
# UPDATE_DEPS fetches the matching Vulkan-Headers at the tag's known-good commit.
run_logged "$WORK/vulkan-loader/build.log" cmake -S "$SRC_VK" -B "$SRC_VK/build" \
  -D UPDATE_DEPS=ON -D BUILD_TESTS=OFF -D CMAKE_BUILD_TYPE=Release \
  -D "CMAKE_OSX_ARCHITECTURES=x86_64;arm64"
run_logged "$WORK/vulkan-loader/build.log" cmake --build "$SRC_VK/build" -j "$JOBS"

built=$(find "$SRC_VK/build" -name 'libvulkan.1.*.dylib' -o -name 'libvulkan.1.dylib' | head -1)
[ -n "$built" ] || die "libvulkan.1.dylib not produced"
mkdir -p "$DEPS/lib"
cp "$built" "$OUT"
# A plain install name; Wine dlopens it by an @loader_path path, so this is cosmetic.
install_name_tool -id '@rpath/libvulkan.1.dylib' "$OUT" 2>/dev/null || true
printf '%s\n' "$TAG" > "$WORK/vulkan-loader/.tag"
lipo -archs "$OUT"
info "Installed $OUT"
