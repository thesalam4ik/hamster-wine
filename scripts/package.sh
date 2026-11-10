#!/bin/sh
# package.sh [ID]: pack a built runtime (default: the newest in $WORK/dist) into $WORK/packages, the
# three files of a release:
#   <id>.tar.xz          the runtime; the archive's root is the <id> folder
#   <id>-source.tar.gz   the corresponding source the LGPL asks us to publish beside it: this
#                        repository at HEAD, which is the upstream pin, the patch series and the scripts
#   package.json         version, file name, SHA-256 and size of the runtime archive, for launchers
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/lib.sh"

ID=${1:-$(ls -t "$WORK/dist" 2>/dev/null | head -n 1)}
[ -n "$ID" ] && [ -f "$WORK/dist/$ID/manifest.json" ] || die "no built runtime; run build.sh"
OUT="$WORK/packages"
rm -rf "$OUT"
mkdir -p "$OUT"
info "Packing $ID"
tar -cJf "$OUT/$ID.tar.xz" --options 'xz:threads=0' -C "$WORK/dist" "$ID"
git -C "$ENGINE" archive --format=tar.gz --prefix="$ID-source/" -o "$OUT/$ID-source.tar.gz" HEAD
printf '{ "version": "%s", "file": "%s.tar.xz", "sha256": "%s", "size": %s }\n' \
  "$ID" "$ID" "$(sha256_of "$OUT/$ID.tar.xz")" "$(stat -f %z "$OUT/$ID.tar.xz")" > "$OUT/package.json"
cat "$OUT/package.json"
info "Packages in $OUT"
