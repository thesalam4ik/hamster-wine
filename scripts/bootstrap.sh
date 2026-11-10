#!/bin/sh
# bootstrap.sh: install what the engine build needs. Safe to run again.
#
# Homebrew formulae for build tools and headers, the pinned llvm-mingw and the pinned Gcenx archive
# (x86_64 dylibs). Every download is checked against its SHA-256 in lib.sh.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/lib.sh"

[ -x /opt/homebrew/bin/brew ] || die "Homebrew is required: https://brew.sh"
xcode-select -p >/dev/null 2>&1 || die "the Command Line Tools are required: xcode-select --install"

missing=
for formula in $HOMEBREW_FORMULAE; do
  /opt/homebrew/bin/brew list --formula "$formula" >/dev/null 2>&1 || missing="$missing $formula"
done
if [ -n "$missing" ]; then
  info "Installing Homebrew formulae:$missing"
  # shellcheck disable=SC2086
  /opt/homebrew/bin/brew install $missing
fi

if [ ! -x "$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" ]; then
  archive="$DOWNLOADS/$(basename "$LLVM_MINGW_URL")"
  fetch "$LLVM_MINGW_URL" "$LLVM_MINGW_SHA256" "$archive"
  info "Extracting llvm-mingw $LLVM_MINGW_VERSION"
  mkdir -p "$LLVM_MINGW.part"
  tar -xJf "$archive" -C "$LLVM_MINGW.part" --strip-components 1
  mv "$LLVM_MINGW.part" "$LLVM_MINGW"
fi

fetch "$GCENX_URL" "$GCENX_SHA256" "$GCENX_ARCHIVE"
info "Prerequisites ready in $WORK"
