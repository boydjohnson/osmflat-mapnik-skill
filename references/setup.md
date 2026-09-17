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

Prebuilt targets are macOS arm64 and Linux x86_64/aarch64; anything else has to
be built from source and put on `PATH`. Set `GITHUB_TOKEN` if you hit the
unauthenticated GitHub API rate limit.

## Data

**Data is the one thing you must supply.** Point `OSMFLAT_ARCHIVE` at an
osmflat archive directory:

```
export OSMFLAT_ARCHIVE=/path/to/area.osm.flat
```

If there is no archive, build one from an `.osm.pbf` extract
(download.geofabrik.de, extract.bbbike.org):

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
