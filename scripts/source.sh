#!/bin/sh
# source.sh: make the patched Wine tree of a flavour: the pinned commit, then one commit per patch
# of the series (`git am`), in $WORK/src/wine-<flavour>.
#
# The patch files are the source of truth. The tree is regenerated only when the pin or the series
# changes (their hash is stored in the tree), so rebuilds stay incremental. To work on a patch:
# edit and commit in the tree, then `git format-patch` it back into components/wine/patches/<topic>/.
#
# Environment: FLAVOUR (default hamster), HAMSTER_WORK.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/lib.sh"

URL=$(flavour url)
COMMIT=$(flavour commit)
SERIES="$ENGINE/$(flavour series)"
PATCHES=$(dirname "$SERIES")/patches
STAMP=$( (printf '%s\n' "$COMMIT"; grep -v '^#' "$SERIES" | while read -r p; do [ -n "$p" ] && cat "$PATCHES/$p"; done) | shasum -a 256 | cut -c 1-16)

if [ "$(cat "$SRC/.hamster-series" 2>/dev/null)" = "$STAMP" ]; then
  info "Wine tree up to date ($SRC)"
  exit 0
fi

if [ ! -d "$SRC/.git" ]; then
  info "Fetching Wine $COMMIT"
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin "$URL"
fi
git -C "$SRC" fetch -q --depth 1 origin "$COMMIT"
git -C "$SRC" checkout -q -f --detach "$COMMIT"
git -C "$SRC" clean -q -fdx
info "Applying $(grep -cv '^#' "$SERIES") patches"
grep -v '^#' "$SERIES" | while read -r patch; do
  [ -n "$patch" ] || continue
  git -C "$SRC" -c user.name=engine -c user.email=engine@localhost am -q --keep-cr "$PATCHES/$patch" ||
    die "patch $patch does not apply (git -C $SRC am --abort to reset)"
done
printf '%s\n' "$STAMP" > "$SRC/.hamster-series"
info "Wine tree ready: $SRC ($(git -C "$SRC" rev-parse --short HEAD))"
