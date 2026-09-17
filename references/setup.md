# Setup: toolchain and data

## Toolchain

The scripts install what they need from GitHub releases on first use — nothing
to do ahead of time. `scripts/install.sh` pre-warms or upgrades all four:

| binary | repo | role |
|---|---|---|
| `render` | boydjohnson/osmflat-mapnik-plugin | style.xml → PNG (mapnik statically linked in, fonts bundled) |
| `osmflat-taginfo` | boydjohnson/osmflat-taginfo | tag introspection |
| `osmflatc` | boydjohnson/osmflat-rs | `.osm.pbf` → `.osm.flat` |
| `osmflat-extc` | boydjohnson/osmflat-ext | `.osm.flat` → `.ext` sidecar |

They land in `${XDG_DATA_HOME:-~/.local/share}/osmflat`, checksum-verified
against the release `SHA256SUMS`. Resolution order per tool is an explicit
`OSMFLAT_BIN_<TOOL>` override, then `PATH`, then the managed install dir, then
download — so a local dev build on `PATH` shadows the release.

Set `GITHUB_TOKEN` if you hit the unauthenticated GitHub API rate limit.

## Requirements

### Platform

The full toolchain has prebuilt releases for exactly two targets:

| platform | status |
|---|---|
| **macOS arm64** (Apple Silicon) | all four tools |
| **Linux x86_64** | all four tools |
| Linux aarch64 | `render` only — `osmflatc`, `osmflat-extc` and `osmflat-taginfo` have no release build |
| macOS x86_64 (Intel) | no releases at all |

On an unsupported platform the installer names the missing target rather than
failing on a 404; build that tool from source and put it on `PATH`, where it
takes precedence over the managed install.

Note the release target triples are not uniform across the four repos (gnu vs
musl, with and without the vendor field), so they are mapped per tool.

### Commands

Required by everything:

| command | used for |
|---|---|
| `bash` | all scripts (arrays and indirect expansion, so not `sh`) |
| `curl` | downloading releases and extracts |
| `tar` | unpacking releases |
| `sha256sum` **or** `shasum` | verifying release checksums; the install refuses to proceed without one |

Plus the usual POSIX text tools (`awk`, `sed`, `grep`, `find`, `stat`,
`mktemp`, …), which every supported platform already has.

Optional, per feature:

| command | needed for | without it |
|---|---|---|
| `uv` | `add-legend.py`, which declares Pillow inline (PEP 723) | use `python3` with Pillow installed |
| `python3` | `fonts.sh`; Geofabrik region lookup in `fetch-extract.sh` | `fonts.sh` fails; lookup falls back to `jq` |
| `jq` | alternative to `python3` for region lookup | `--search` is unavailable, and a bare id like `monaco` no longer resolves — give the full path, `europe/monaco` |
| `md5sum` **or** `md5` | checking a downloaded extract against Geofabrik's `.md5` | the check is skipped with a warning |

Nothing here needs a system mapnik: the `render` release has it statically
linked with the osmflat plugin compiled in, and ships its own fonts.

## Data

**Data is the one thing you must supply.** Point `OSMFLAT_ARCHIVE` at an
osmflat archive directory:

```
export OSMFLAT_ARCHIVE=/path/to/area.osm.flat
```

### No archive yet?

If the user has no `.osm.flat` archive and no local `.osm.pbf`, **offer to
download an extract from Geofabrik** rather than stopping. Ask first — extracts
are large, and the choice of region is theirs.

1. Find the region. Ask the user what area they want if it isn't already clear
   from the request, then:
   ```
   scripts/fetch-extract.sh --search minnesota
   ```
2. Get the real size and confirm with the user before downloading:
   ```
   scripts/fetch-extract.sh --info us/minnesota
   ```
   A city or small country is a few MB; a US state is a few hundred MB; a
   continent is several GB. Tell them the size and where it will land, and wait
   for a yes.
3. Download (verifies the published md5), then compile:
   ```
   scripts/fetch-extract.sh us/minnesota
   scripts/build-archive.sh ~/.local/share/osmflat/data/minnesota-latest.osm.pbf
   ```

A region can be a Geofabrik id (`us/minnesota`), a full path
(`north-america/us/minnesota`), or a complete `.osm.pbf` URL. Default
destination is `$OSMFLAT_HOME/data`, which `render.sh` finds automatically when
it holds exactly one archive.

Prefer the smallest extract that covers the subject: compile time and disk both
scale with the input, and a city map does not need a continent. Geofabrik data
is OpenStreetMap, under the ODbL.

If the user already has an `.osm.pbf`, skip straight to:

```
scripts/build-archive.sh /path/to/area.osm.pbf
```

That runs `osmflatc`, then `osmflat-extc` for the **Ext sidecar** — the
inverted tag index behind `taginfo.sh`, the `tags` push-down, and precomputed
multipolygon/coastline rings. `render.sh` finds the sidecar next to the archive
(`area.osm.ext`) or takes `OSMFLAT_EXT`. Without one, `taginfo.sh` fails and
`tags=`/`_osmflat_land=yes` silently do nothing — so build it.

A sidecar is bound to one parent build: rebuild it whenever the archive is
rebuilt, or opening it fails on a fingerprint mismatch.

Rebuild only the sidecar against an existing archive:

```
scripts/build-archive.sh --ext-only /path/to/area.osm.flat
```

## Version agreement

`osmflatc` and `osmflat-extc` share a flatdata schema and are released in
lockstep. Mixing versions fails partway through the sidecar build with a
multi-hundred-line `WrongSignature` schema diff. `build-archive.sh` checks this
up front and refuses with a readable message instead.

This is easy to hit because `PATH` beats the managed install dir — a forgotten
`cargo install osmflatc` silently shadows the release. That precedence is
deliberate, so that a dev build of one of these tools can be tested in place.
To force the managed release for one run:

```
OSMFLAT_BIN_OSMFLATC=~/.local/share/osmflat/bin/osmflatc \
OSMFLAT_BIN_OSMFLAT_EXTC=~/.local/share/osmflat/bin/osmflat-extc \
  scripts/build-archive.sh /path/to/area.osm.pbf
```

`OSMFLAT_SKIP_VERSION_CHECK=1` overrides the check entirely.

## When a render comes back blank

A blank PNG with no error means the query matched nothing. In rough order of
likelihood:

- the bbox falls outside the extract;
- a `tags` prefilter is narrower than the layer's `<Filter>`;
- the Ext sidecar is missing, so a `tags=` push-down returns nothing;
- the archive is stale against the current plugin — it can return zero features
  at every bbox with no error, while `osmflat-taginfo` still reads it fine.
  taginfo working is **not** evidence that the archive renders.

Bisect by rendering one layer with no `tags` parameter, then against a
known-good archive.
