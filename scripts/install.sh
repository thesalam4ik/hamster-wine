#!/bin/sh
# install.sh [ID]: install a built runtime (default: the newest in $WORK/dist) into the app's
# Runtimes folder, where the app and hamsterctl find it. The copy is an APFS clone (`cp -c`): no
# extra disk space until either side changes.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/lib.sh"

ID=${1:-$(ls -t "$WORK/dist" 2>/dev/null | head -n 1)}
[ -n "$ID" ] && [ -f "$WORK/dist/$ID/manifest.json" ] || die "no built runtime; run build.sh"
RUNTIMES="$HOME/Library/Application Support/HamsterLauncher/Runtimes"
mkdir -p "$RUNTIMES"
if [ -d "$RUNTIMES/$ID" ]; then rm -r "${RUNTIMES:?}/${ID:?}"; fi
cp -cR "$WORK/dist/$ID" "$RUNTIMES/$ID"
info "Installed $ID into $RUNTIMES"
