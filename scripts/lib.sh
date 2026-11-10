# lib.sh: paths, pins and helpers shared by the engine scripts. Source it after setting HERE.
# shellcheck shell=sh

ENGINE=$(CDPATH= cd -- "$HERE/.." && pwd)
FLAVOUR=${FLAVOUR:-hamster}

# Everything generated lives under WORK: outside the home folder (no spaces, not backed up), and
# *.noindex so Spotlight doesn't index hundreds of thousands of build files.
WORK=${HAMSTER_WORK:-/private/tmp/hamster-build}/engine.noindex
DOWNLOADS="$WORK/downloads"
SRC="$WORK/src/wine-$FLAVOUR"
TOOLS="$WORK/tools-arm64-$FLAVOUR"
BUILD="$WORK/build-x86_64-$FLAVOUR"
DEPS="$WORK/deps-x86_64"
JOBS=${JOBS:-$(sysctl -n hw.ncpu)}

# --- Pinned inputs. Change a pin only together with its SHA-256. ---------------------------------
MACOS_DEPLOYMENT_TARGET=26.0
# llvm-mingw builds the Windows (PE) half of Wine with clang, for i386 and x86_64.
LLVM_MINGW_VERSION=20260616
LLVM_MINGW_URL=https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_VERSION/llvm-mingw-$LLVM_MINGW_VERSION-ucrt-macos-universal.tar.xz
LLVM_MINGW_SHA256=2cab02a2e964bd4aae981150a45985d07c657cfa8d244959eb9e2dcc5eedd7b1
LLVM_MINGW=${LLVM_MINGW:-$WORK/toolchains/llvm-mingw-$LLVM_MINGW_VERSION}
# x86_64 macOS dylibs Wine needs at run time (GnuTLS, FreeType and their dependencies). Homebrew on
# Apple Silicon only has arm64 libraries, so we take these from Gcenx's x86_64 Wine build; Wine
# itself is compiled from our tree.
GCENX_URL=https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.8/wine-devel-11.8-osx64.tar.xz
GCENX_SHA256=5c9f0984961ee6289f4f2c4fe751c27f02b6c28855154e3f99b7e2bd8108b620
GCENX_ARCHIVE=${GCENX_ARCHIVE:-$DOWNLOADS/$(basename "$GCENX_URL")}
# Build tools and architecture-independent headers.
HOMEBREW_FORMULAE="bison gnutls freetype pkgconf gettext ccache autoconf cmake vulkan-headers"

info() { printf '==> %s\n' "$*"; }
die() { printf 'engine: %s\n' "$*" >&2; exit 1; }
sha256_of() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
brew_prefix() { printf '/opt/homebrew/opt/%s' "$1"; }

# json_get FILE KEY.PATH: one value of a JSON file (strings bare). macOS's python3, isolated mode.
json_get() {
  /usr/bin/python3 -I -c 'import json, sys
value = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    value = value[key]
print(value if isinstance(value, str) else json.dumps(value))' "$1" "$2"
}

# flavour KEY: a field of this flavour in sources.json.
flavour() { json_get "$ENGINE/sources.json" "flavours.$FLAVOUR.$1"; }

# fetch URL SHA256 DEST: download once, then always verify the digest.
fetch() {
  if [ ! -f "$3" ]; then
    mkdir -p "$(dirname "$3")"
    info "Downloading $(basename "$3")"
    curl -fL --retry 3 -sS "$1" -o "$3.part"
    mv "$3.part" "$3"
  fi
  [ "$(sha256_of "$3")" = "$2" ] || die "SHA-256 mismatch for $3"
}

# run_logged LOG CMD...: run quietly; on failure show the end of the log.
run_logged() {
  _log=$1; shift
  if ! "$@" > "$_log" 2>&1; then
    tail -n 40 "$_log" >&2
    die "failed: $* (full log: $_log)"
  fi
}
