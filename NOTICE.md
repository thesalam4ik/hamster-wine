# Engine notices

## Wine patches

`components/wine/patches/` and `components/wine/series` were copied unmodified on 2026-11-07 from
SiliconBedrock's `engine/components/wine` (macrock-engine 0.2.3, itself from
[vincenzopio/macrock-engine](https://github.com/vincenzopio/macrock-engine)). Each patch modifies Wine
and is licensed **LGPL-2.1-or-later**, like Wine. Every patch keeps its author in its `From:` header
and its origin in its message:

- `msync`, `d3dmetal`: from hsr-wine-d3dmetal (LGPL-2.1-or-later), partly derived from CrossOver FOSS.
- `dxmt`: from [bedrock-mac](https://github.com/1JRobertson/bedrock-mac) (LGPL-2.1-or-later).
- `afunix`: Wine merge request !7650 by Ally Sommers, Ralf Habacker and Giang Nguyen.
- `opengl-extensions`: Wine commit 1c2d909829c757fdf70c8d863642cd0ae9b81e59 by Rémi Bernon (in Wine 11.19),
  unmodified, added 2026-11-11. Drop it when the pin reaches 11.19.
- `fps-log`, `window-title`, `bundle-icon`, `com-context`, `storage-file`, `bcp47mrm`: macrock-engine and
  SiliconBedrock authors.

## Scripts

`scripts/` are written for Hamster Launcher and licensed LGPL-2.1-or-later like the rest of this
repository (`LICENSE`). They follow the same build approach as macrock-engine's `packaging/macos`
(arm64 tools, x86_64 Wine with llvm-mingw, Gcenx dylibs) but contain none of its GPL-3.0 code.

## Distributing a runtime

A release carries the runtime, the complete corresponding source beside it (`<id>-source.tar.gz`:
the pinned upstream commit in `sources.json`, the patch series and the build scripts) and, inside the
runtime's `licenses/` folder, Wine's `COPYING.LIB`, `LICENSE` and `AUTHORS`, the Vulkan loader's
licence and the licence texts of the bundled libraries that Homebrew ships (GnuTLS, Nettle, GMP,
libtasn1, libidn2, libunistring, p11-kit, FreeType, libpng, Brotli, gettext, zstd, libffi).

Still to do: the texts for bzip2, zlib, libiconv and MacPorts legacy-support, which come in the
Gcenx archive without them.
