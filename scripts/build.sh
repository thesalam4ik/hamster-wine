#!/bin/sh
# build.sh: build a Wine runtime of a flavour into $WORK/dist/<id>.
#
# 1. source.sh makes the patched tree (incremental: unchanged series → tree untouched).
# 2. Wine's build tools are built natively for arm64, so the build never runs thousands of x86_64
#    tool processes under Rosetta.
# 3. Wine for x86_64: the Unix half with Apple clang, the Windows (PE) half with llvm-mingw for both
#    i386 and x86_64 ("new WoW64": 32-bit games run without 32-bit macOS code).
# 4. The x86_64 GnuTLS/FreeType dylibs from the pinned Gcenx archive go beside Wine.
# The result is relocatable: Wine finds its files relative to ntdll.so.
#
# Vulkan is on (--with-vulkan): the universal Khronos loader is built beside Wine, which
# dispatches to MoltenVK/KosmicKrisp at runtime. SDL and FFmpeg stay off until we have x86_64 builds.
#
# Environment: FLAVOUR, JOBS (default: all cores), HAMSTER_WORK, RECONFIGURE, REBUILD_TOOLS.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/lib.sh"

[ -x "$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" ] || die "llvm-mingw missing; run bootstrap.sh"
[ -f "$GCENX_ARCHIVE" ] || die "Gcenx archive missing; run bootstrap.sh"
"$HERE/source.sh"

VERSION=$(sed -n 's/^PACKAGE_VERSION=.\(.*\).$/\1/p' "$SRC/configure")
SERIES_ID=$(cut -c 1-8 "$SRC/.hamster-series")
ID="$FLAVOUR-$VERSION-$SERIES_ID"
DIST="$WORK/dist/$ID"

export LC_ALL=en_US.UTF-8
export MACOSX_DEPLOYMENT_TARGET
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
export SDKROOT
export PATH="$LLVM_MINGW/bin:$(brew_prefix bison)/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# ccache keyed relative to WORK, so moving the work folder keeps the cache.
export CCACHE_DIR="$WORK/ccache" CCACHE_MAXSIZE=20G CCACHE_COMPILERCHECK=content CCACHE_BASEDIR="$WORK"
CCACHE=$(command -v ccache || true)
CLANG=$(xcrun --find clang)
CLANGXX=$(xcrun --find clang++)
unset CC CXX OBJC CFLAGS CXXFLAGS OBJCFLAGS LDFLAGS

# --- Native arm64 tools -------------------------------------------------------------------------
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
# wrc reads <tools>/nls/locale.nls, which a __tooldeps__-only build does not make.
mkdir -p "$TOOLS/nls"
ln -sf "$SRC/nls/locale.nls" "$TOOLS/nls/locale.nls"

# --- x86_64 dylibs ------------------------------------------------------------------------------
if [ ! -f "$DEPS/lib/libgnutls.30.dylib" ]; then
  info "Collecting x86_64 GnuTLS and FreeType from $(basename "$GCENX_ARCHIVE")"
  "$HERE/collect-dylibs.sh" "$GCENX_ARCHIVE" "$DEPS/lib" libgnutls.30.dylib libfreetype.6.dylib
fi
# The Vulkan loader Wine dlopens --with-vulkan; it dispatches to the ICD (MoltenVK/KosmicKrisp)
# chosen at runtime through VK_ICD_FILENAMES.
"$HERE/build-vulkan-loader.sh"

# --- x86_64 Wine with i386 + x86_64 PE ----------------------------------------------------------
mkdir -p "$BUILD"
cd "$BUILD"
export CC="$CCACHE $CLANG -arch x86_64" CXX="$CCACHE $CLANGXX -arch x86_64" OBJC="$CCACHE $CLANG -arch x86_64"
export CFLAGS=-O2 CXXFLAGS=-O2 OBJCFLAGS=-O2 CROSSCFLAGS=-O2
export x86_64_CC="$CCACHE x86_64-w64-mingw32-clang" x86_64_CXX="$CCACHE x86_64-w64-mingw32-clang++"
export i386_CC="$CCACHE i686-w64-mingw32-clang" i386_CXX="$CCACHE i686-w64-mingw32-clang++"
# Headers from Homebrew (architecture-independent), libraries from the x86_64 dylibs, which Wine
# dlopens by the sonames below, relative to lib/wine/x86_64-unix.
export GNUTLS_CFLAGS="-I$(brew_prefix gnutls)/include" GNUTLS_LIBS="-L$DEPS/lib -lgnutls"
export FREETYPE_CFLAGS="-I$(brew_prefix freetype)/include/freetype2"
export FREETYPE_LIBS="-L$DEPS/lib -Wl,-rpath,$DEPS/lib -lfreetype"
export ac_cv_lib_soname_gnutls='@loader_path/../../libgnutls.30.dylib'
export ac_cv_lib_soname_freetype='@loader_path/../../libfreetype.6.dylib'
# Vulkan: architecture-independent headers from Homebrew; the loader (built above into $DEPS/lib) is
# dlopened by this soname at runtime, relative to lib/wine/x86_64-unix.
export VULKAN_CFLAGS="-I$(brew_prefix vulkan-headers)/include"
export ac_cv_lib_soname_vulkan='@loader_path/../../libvulkan.1.dylib'
if [ ! -f Makefile ] || [ "$SRC/configure" -nt Makefile ] || [ -n "${RECONFIGURE:-}" ] ||
   [ "$(cat .hamster-prefix 2>/dev/null)" != "$DIST" ]; then
  info "Configuring Wine $VERSION ($ID)"
  run_logged "$BUILD/configure.log" "$SRC/configure" \
    --build=aarch64-apple-darwin --host=x86_64-apple-darwin \
    --prefix="$DIST" --with-wine-tools="$TOOLS" \
    --enable-archs=i386,x86_64 --with-mingw=llvm-mingw --disable-tests \
    --without-x --with-freetype --with-gnutls --with-vulkan \
    --without-gstreamer --without-ffmpeg --without-sdl --without-cups --without-sane --without-krb5
  printf '%s\n' "$DIST" > .hamster-prefix
fi

info "Building with $JOBS jobs (log: $BUILD/build.log)"
start=$(date +%s)
run_logged "$BUILD/build.log" make -j"$JOBS"
if [ -d "$DIST" ]; then rm -r "${DIST:?}"; fi
run_logged "$BUILD/install.log" make install
cp -a "$DEPS/lib/." "$DIST/lib/"
# With arm64 tools, the in-process tools/wine/wine launcher is not installed; the x86_64 loader
# is what runs anyway.
ln -sf ../lib/wine/x86_64-unix/wine "$DIST/bin/wine"

topics=$(grep -v '^#' "$ENGINE/$(flavour series)" | cut -d / -f 1 | sort -u | tr '\n' ' ')
/usr/bin/python3 -I - "$DIST/manifest.json" "$ID" "$FLAVOUR" "wine-$VERSION" $topics <<'EOF'
import json, sys
path, id, flavour, version, *topics = sys.argv[1:]
json.dump({"id": id, "flavour": flavour, "wineVersion": version, "patches": topics,
           "syncModes": ["msync", "wineSync"]}, open(path, "w"), indent=2, sort_keys=True)
EOF
# Licence texts travel with the binaries (NOTICE.md): Wine's from its tree, the Vulkan loader's from
# its source, each bundled library's from its Homebrew formula (same projects as the Gcenx dylibs).
mkdir -p "$DIST/licenses"
cp "$SRC/COPYING.LIB" "$SRC/LICENSE" "$SRC/AUTHORS" "$DIST/licenses/"
cp "$WORK"/vulkan-loader/*/LICENSE.txt "$DIST/licenses/vulkan-loader-LICENSE.txt"
for formula in gnutls nettle gmp libtasn1 libidn2 libunistring p11-kit freetype libpng brotli gettext zstd libffi; do
  for text in "$(brew_prefix "$formula")"/COPYING* "$(brew_prefix "$formula")"/LICENSE*; do
    [ -f "$text" ] && cp "$text" "$DIST/licenses/$formula-$(basename "$text")"
  done
done
info "Built $ID in $(( ($(date +%s) - start) / 60 )) min: $DIST"
"$DIST/bin/wine" --version
