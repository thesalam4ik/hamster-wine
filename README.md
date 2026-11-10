# hamster-wine: Wine for Hamster Launcher

Wine built from source with a macOS patch series, for Apple Silicon. Nothing upstream is vendored: a
flavour in `sources.json` pins an upstream commit, and `components/wine/series` lists the patches
applied on top. Hamster Launcher downloads the runtimes from this repository's releases.

```sh
scripts/bootstrap.sh   # Homebrew formulae, llvm-mingw, Gcenx archive (x86_64 dylibs)
scripts/build.sh       # patched tree → arm64 tools → x86_64 Wine (i386 + x86_64 PE)
scripts/package.sh     # <id>.tar.xz, <id>-source.tar.gz, package.json
scripts/install.sh     # clone the build into Hamster Launcher's Runtimes folder (local testing)
```

Builds go to `$HAMSTER_WORK/engine.noindex` (default `/private/tmp/hamster-build/engine.noindex`):
`src/wine-<flavour>` (the patched git tree), `tools-arm64-*`, `build-x86_64-*`, `dist/<id>`, `ccache`.
`JOBS` defaults to every core. A runtime id is `<flavour>-<wine version>-<series hash>`, so a changed
pin or series is a new id.

## Releases

`.github/workflows/build.yml` builds every push and pull request on a macOS runner. On `main`, a
build whose id has no release yet is published as one, tagged with the id: change the pin or a
patch, push, and the new runtime is out. `package.json` of the newest release is at
`releases/latest/download/package.json`.

## Layout

| Path | What |
|---|---|
| `sources.json` | flavours: upstream URL, ref, pinned commit, series file |
| `components/wine/series` | patch order (one path per line, `#` comments) |
| `components/wine/patches/<topic>/` | the patches, `git format-patch` files with `From:` and `Topic:` |
| `scripts/lib.sh` | paths, download pins (URL + SHA-256), helpers |
| `scripts/source.sh` | pinned commit + `git am` of the series, skipped when unchanged |
| `scripts/build.sh` | the build (comments explain each stage) |
| `scripts/collect-dylibs.sh` | x86_64 dylibs and their dependencies from the Gcenx archive |
| `scripts/package.sh` | the release files |
| `scripts/install.sh` | install a build into `~/Library/Application Support/HamsterLauncher/Runtimes` |

## Patch topics

| Topic | What it does | Environment |
|---|---|---|
| `msync` | Mach-semaphore synchronisation; Rosetta code regions; `WINEDLLPATH_PREPEND` | `WINEMSYNC=1`, `WINEDLLPATH_PREPEND` |
| `d3dmetal` | winemac.drv bridge D3DMetal needs to present into Wine's windows | `CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal`, `CX_APPLEGPTK_LIBD3DSHARED_PATH` |
| `dxmt` | window data layout DXMT 0.80 reads | |
| `fps-log` | one line of frame pacing per second (D3DMetal path) | `MACROCK_FPS_LOG` |
| `window-title` | launcher-chosen window titles | `MACROCK_WINDOW_TITLE[_SUFFIX]` |
| `bundle-icon` | keep the host app's Dock icon | `WINEMAC_KEEP_BUNDLE_ICON=1` |
| `afunix` | AF_UNIX sockets (Wine MR !7650) | |
| `com-context`, `storage-file`, `bcp47mrm` | WinRT/COM pieces modern games' runtimes call | |
| `opengl-extensions` | upstream fix (Wine 11.19): OpenGL contexts below 3.0 list their GL extensions again; 11.17 gave legacy OpenGL games none, so no framebuffer objects | |

## Working on a patch

```sh
scripts/source.sh                             # tree in $HAMSTER_WORK/engine.noindex/src/wine-hamster
cd /private/tmp/hamster-build/engine.noindex/src/wine-hamster
# edit, commit with a "Topic: <topic>" trailer, then:
git format-patch -1 -o <this repository>/components/wine/patches/<topic>/
# add the file to components/wine/series in order
```

Licence: LGPL-2.1-or-later (`LICENSE`), like Wine. Origins of the patches: `NOTICE.md`.
