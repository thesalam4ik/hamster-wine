#!/bin/sh
# build-arm64ec.sh: build the experimental arm64 Wine runtime into $WORK/dist/<id>.
#
# ARM64EC Wine runs Wine, its system DLLs and the graphics translation natively on Apple silicon and
# emulates only the game's x86 code through FEX (libarm64ecfex.dll / libwow64fex.dll). This is the
# host KosmicKrisp (arm64, see build-kosmickrisp.sh) needs: the x86_64 runtime cannot load an arm64
# Vulkan driver.
#
# Reuses the patched source tree (source.sh) and the native arm64 build tools from build.sh. The
# Unix half is built natively with Apple clang (no Rosetta); the Windows half as ARM64EC + x86_64
# thunks with llvm-mingw. --with-vulkan against our universal Khronos loader (build-vulkan-loader.sh).
# FEX comes from $FEX_DIR (an unpacked FEX build with wine/aarch64-{unix,windows}); default is
# GameHub's FEX-0826 (read-only reference), copied into the runtime.
#
# This first build keeps GnuTLS/FreeType off (their arm64 dylibs are not bundled yet); add them later.
#
# Environment: FLAVOUR, JOBS, HAMSTER_WORK, FEX_DIR, RECONFIGURE, REBUILD_TOOLS.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/lib.sh"

[ "$(uname -m)" = arm64 ] || die "the arm64 runtime must be built on Apple silicon"
[ -x "$LLVM_MINGW/bin/arm64ec-w64-mingw32-clang" ] || die "llvm-mingw has no arm64ec target; run bootstrap.sh"
LOADER="$DEPS/lib/libvulkan.1.dylib"
[ -f "$LOADER" ] || die "Vulkan loader missing; run build-vulkan-loader.sh"
FEX_DIR=${FEX_DIR:-$HOME/Library/Application Support/com.gamemac.www/wine-engine/downloads/FEX-0826}
"$HERE/source.sh"

VERSION=$(sed -n 's/^PACKAGE_VERSION=.\(.*\).$/\1/p' "$SRC/configure")
SERIES_ID=$(cut -c 1-8 "$SRC/.hamster-series")
ID="$FLAVOUR-arm64ec-$VERSION-$SERIES_ID"
DIST="$WORK/dist/$ID"
BUILD_EC="$WORK/build-arm64ec-$FLAVOUR"

export LC_ALL=en_US.UTF-8
export MACOSX_DEPLOYMENT_TARGET
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
export SDKROOT
export PATH="$LLVM_MINGW/bin:$(brew_prefix bison)/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export CCACHE_DIR="$WORK/ccache" CCACHE_MAXSIZE=20G CCACHE_COMPILERCHECK=content CCACHE_BASEDIR="$WORK"
CCACHE=$(command -v ccache || true)
CLANG=$(xcrun --find clang)
CLANGXX=$(xcrun --find clang++)
unset CC CXX OBJC CFLAGS CXXFLAGS OBJCFLAGS LDFLAGS

# --- Native arm64 build tools (shared with build.sh) --------------------------------------------
if [ ! -x "$TOOLS/tools/winebuild/winebuild" ] || [ -n "${REBUILD_TOOLS:-}" ]; then
  info "Building Wine's tools for arm64"
  mkdir -p "$TOOLS"
  (
    cd "$TOOLS"
    export CC="$CCACHE $CLANG -arch arm64" CXX="$CCACHE $CLANGXX -arch arm64"
    run_logged "$TOOLS/configure.log" "$SRC/configure" \
      --enable-archs=aarch64 --with-mingw=llvm-mingw --disable-tests \
      --without-x --without-gnutls --without-vulkan --without-gstreamer --without-ffmpeg \
      --without-unwind --without-sdl --without-cups --without-sane --without-krb5
    run_logged "$TOOLS/build.log" make -j"$JOBS" __tooldeps__
  )
fi
mkdir -p "$TOOLS/nls"
ln -sf "$SRC/nls/locale.nls" "$TOOLS/nls/locale.nls"

# --- ARM64EC Wine (arm64ec + aarch64 PE, native arm64 Unix) -------------------------------------
mkdir -p "$BUILD_EC"
cd "$BUILD_EC"
export CC="$CCACHE $CLANG -arch arm64" CXX="$CCACHE $CLANGXX -arch arm64" OBJC="$CCACHE $CLANG -arch arm64"
export CFLAGS=-O2 CXXFLAGS=-O2 OBJCFLAGS=-O2 CROSSCFLAGS=-O2
export VULKAN_CFLAGS="-I$(brew_prefix vulkan-headers)/include"
export ac_cv_lib_soname_vulkan='@loader_path/../../libvulkan.1.dylib'
if [ ! -f Makefile ] || [ "$SRC/configure" -nt Makefile ] || [ -n "${RECONFIGURE:-}" ] ||
   [ "$(cat .hamster-prefix 2>/dev/null)" != "$DIST" ]; then
  info "Configuring ARM64EC Wine $VERSION ($ID)"
  run_logged "$BUILD_EC/configure.log" "$SRC/configure" \
    --build=aarch64-apple-darwin --host=aarch64-apple-darwin \
    --prefix="$DIST" --with-wine-tools="$TOOLS" \
    --enable-archs=arm64ec --with-mingw=llvm-mingw --disable-tests \
    --without-x --without-gnutls --without-freetype --with-vulkan \
    --without-gstreamer --without-ffmpeg --without-sdl --without-cups --without-sane --without-krb5
  printf '%s\n' "$DIST" > .hamster-prefix
fi

info "Building with $JOBS jobs (log: $BUILD_EC/build.log)"
start=$(date +%s)
# Wine's type-library imports pass `-Ldlls/*` to widl, a glob over dlls/ that intermittently misses a
# just-built .tlb under heavy -j ("cannot find stdole2.tlb"). The build is resumable and makes
# monotonic progress, so retry a bounded number of times; a real error still fails every attempt.
built_ok=
for attempt in 1 2 3 4 5 6; do
  if make -j"$JOBS" > "$BUILD_EC/build.log" 2>&1; then built_ok=1; break; fi
  grep -q "cannot find .*\.tlb" "$BUILD_EC/build.log" || { tail -n 40 "$BUILD_EC/build.log" >&2; die "build failed (log: $BUILD_EC/build.log)"; }
  info "transient .tlb race on attempt $attempt; retrying"
done
[ -n "$built_ok" ] || { tail -n 40 "$BUILD_EC/build.log" >&2; die "build still failing after retries (log: $BUILD_EC/build.log)"; }
if [ -d "$DIST" ]; then rm -r "${DIST:?}"; fi
run_logged "$BUILD_EC/install.log" make install
cp "$LOADER" "$DIST/lib/libvulkan.1.dylib"
ln -sf ../lib/wine/aarch64-unix/wine "$DIST/bin/wine"

# --- FEX: the x86 emulation Wine loads on ARM64 -------------------------------------------------
if [ -d "$FEX_DIR/wine" ]; then
  info "Adding FEX from $(basename "$FEX_DIR")"
  for sub in aarch64-unix aarch64-windows; do
    if [ -d "$FEX_DIR/wine/$sub" ]; then
      mkdir -p "$DIST/lib/wine/$sub"
      cp "$FEX_DIR/wine/$sub"/lib*fex.* "$DIST/lib/wine/$sub/" 2>/dev/null || true
    fi
  done
else
  info "WARNING: no FEX at $FEX_DIR — the runtime cannot run x86 games until FEX is added"
fi

topics=$(grep -v '^#' "$ENGINE/$(flavour series)" | cut -d / -f 1 | sort -u | tr '\n' ' ')
/usr/bin/python3 -I - "$DIST/manifest.json" "$ID" "$FLAVOUR" "wine-$VERSION" $topics <<'EOF'
import json, sys
path, id, flavour, version, *topics = sys.argv[1:]
json.dump({"id": id, "flavour": flavour, "wineVersion": version, "patches": topics,
           "architecture": "arm64ec", "syncModes": ["msync", "wineSync"]}, open(path, "w"), indent=2, sort_keys=True)
EOF
info "Built $ID in $(( ($(date +%s) - start) / 60 )) min: $DIST"
"$DIST/bin/wine" --version
