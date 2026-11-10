#!/bin/sh
# collect-dylibs.sh ARCHIVE DEST LIB...: copy LIBs and every dylib they load (recursively, through
# @rpath/@loader_path names) from a Gcenx Wine archive's lib folder into DEST.
#
# Only the libraries Wine needs at run time are taken, not the archive's Wine. Each copy's install
# name becomes @rpath/<name>, and it is re-signed ad hoc (changing load commands breaks signatures).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/lib.sh"
ARCHIVE=$1 DEST=$2
shift 2

staging="$WORK/gcenx-lib"
if [ ! -d "$staging" ]; then
  info "Unpacking the lib folder of $(basename "$ARCHIVE")"
  mkdir -p "$staging.part"
  # The archive holds "Wine Devel.app/Contents/Resources/wine/lib/..."; keep only the dylibs.
  tar -xJf "$ARCHIVE" -C "$staging.part" --include '*/wine/lib/*.dylib'
  lib=$(find "$staging.part" -type d -path '*/wine/lib' | head -n 1)
  [ -n "$lib" ] || die "no wine/lib in $ARCHIVE"
  mv "$lib" "$staging"
  find "$staging.part" -depth -type d -empty -delete 2>/dev/null || true
fi

mkdir -p "$DEST"
queue="$*"
done_list=" "
while [ -n "$queue" ]; do
  set -- $queue
  name=$1; shift; queue="$*"
  case "$done_list" in *" $name "*) continue ;; esac
  done_list="$done_list$name "
  [ -f "$staging/$name" ] || die "$name is not in the archive"
  cp -L "$staging/$name" "$DEST/$name"
  chmod u+w "$DEST/$name"
  install_name_tool -id "@rpath/$name" "$DEST/$name" 2>/dev/null
  # Dependencies by @rpath/@loader_path names are ours to bring; system ones stay as they are.
  for dep in $(otool -L "$DEST/$name" | tail -n +2 | awk '{print $1}' | grep -E '^@(rpath|loader_path)/' | sed 's|.*/||'); do
    [ "$dep" = "$name" ] || queue="$queue $dep"
  done
  codesign --force --sign - "$DEST/$name" 2>/dev/null
done
info "Collected:$(printf '%s' "$done_list" | tr -s ' ')"
