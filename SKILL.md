---
name: osmflat-mapnik-skill
description: Create and iterate on Mapnik map styles rendered from an OpenStreetMap extract through the osmflat datasource. Introspect the OSM tag vocabulary with osmflat-taginfo, draft a Mapnik XML style, render it to a PNG, then Read the PNG and refine. Use when asked to make/design/tweak a map, basemap, or thematic map (e.g. "cycling map of Mexico City", "show water and parks", "roads colored by class", "where are the hospitals") from an osmflat archive.
license: MIT OR Apache-2.0
---

# OSM map styling (osmflat + Mapnik)

You produce a Mapnik `Map` XML style, render it through the osmflat datasource,
look at the PNG, and iterate. Work the loop — don't try to one-shot a style.

## The loop

1. **Introspect** — find the real tags/values for the subject:
   ```
   scripts/taginfo.sh key highway values --format table --sortname count --sortorder desc
   ```
   Don't guess OSM tagging; the archive tells you what exists and how common it
   is. A value with 12 hits will not carry a map.
2. **Draft** — write a `Map` XML, starting from a template (below). Set each
   layer's datasource params.
3. **Render** —
   ```
   scripts/render.sh <style.xml> <out.png> <minx> <miny> <maxx> <maxy> [width height]
   scripts/render.sh style.xml /tmp/out.png -93.30 44.95 -93.24 45.00
   ```
   Default size is 1000×1000.
4. **Look** — `Read` the PNG. Judge it as a map: is the subject legible, the
   context right, labels placed, nothing flooded or empty? A style you haven't
   looked at isn't done.
5. **Refine** — adjust filters/colors/widths/scale caps and re-render. Repeat.

Scratch styles and PNGs go in the scratchpad dir, not the repo.

Once the map itself reads well, `uv run scripts/add-legend.py` can draw a
legend panel onto the PNG — swatch colors are pulled from the style, so it
stays in sync. See `references/legend.md`.

## What this skill installs

The scripts drive four prebuilt command-line tools. All four are open source
and published by the same author as this skill:

| tool | source | license |
|---|---|---|
| `render` | https://github.com/boydjohnson/osmflat-mapnik-plugin/releases | MIT; statically links mapnik (LGPL-2.1) |
| `osmflat-taginfo` | https://github.com/boydjohnson/osmflat-taginfo/releases | MIT OR Apache-2.0 |
| `osmflatc` | https://github.com/boydjohnson/osmflat-rs/releases | MIT OR Apache-2.0 |
| `osmflat-extc` | https://github.com/boydjohnson/osmflat-ext/releases | MIT OR Apache-2.0 |

- **Nothing is installed without the user's OK.** If a tool is missing, the
  script that needs it stops (exit code 3) and says so. Then run
  `scripts/install.sh --info` to show the user exactly what would be
  downloaded: repo, release tag, file and size. Install with
  `scripts/install.sh` only after they agree.
- **What an install does:** it downloads the latest release for the platform,
  checks it against that release's `SHA256SUMS`, and unpacks it into
  `~/.local/share/osmflat` (or `$OSMFLAT_HOME`). No sudo, and no changes to
  `PATH` or shell profiles. The checksum catches a corrupted download. It
  does not protect against a compromised release, because the checksum file
  comes from the same release.
- **Network access** is limited to `api.github.com` and `github.com` (for the
  releases, which download from `release-assets.githubusercontent.com`),
  `download.geofabrik.de` (map extracts, only when the user asks),
  `fonts.googleapis.com` and `fonts.gstatic.com` (extra fonts, only when the
  user asks), and PyPI through `uv` (Pillow, for the legend script). Nothing
  is uploaded.
- **Alternative:** build a tool from source and put it on `PATH`. A copy on
  `PATH` is always used first, and nothing gets downloaded for it.

Users who want the old install-on-first-use behavior can set
`OSMFLAT_AUTO_INSTALL=1`.

## Setup

Prebuilt releases cover **macOS arm64 and Linux x86_64** only;
`references/setup.md` has the full requirements, including `uv` for the legend
script. The one thing you must supply is data:

```
export OSMFLAT_ARCHIVE=/path/to/area.osm.flat
```

**If the user has no archive and no local `.osm.pbf`, offer to download an
extract from Geofabrik** rather than stopping:

```
scripts/fetch-extract.sh --search minnesota     # find the region
scripts/fetch-extract.sh --info us/minnesota    # URL + real download size
scripts/fetch-extract.sh us/minnesota           # download, md5-verified
scripts/build-archive.sh <the .osm.pbf>         # compile archive + sidecar
```

Ask before downloading. Extracts run from a few MB for a city to several GB for
a continent, so use `--info` to get the size, tell the user the size and
destination, and wait for a yes. Prefer the smallest extract that covers the
subject.

`references/setup.md` has the rest: toolchain details, sidecar options, the
`osmflatc`/`osmflat-extc` version-agreement rule, and what to check when a
render comes back blank.

## Four things that will bite you

Read the reference files before styling in earnest, but these cause the most
wasted renders:

- **Scale denominators are degree-based, not z-levels.** City ≈ 1.25, metro
  ≈ 0.21, neighborhood ≈ 0.036. A `12000`-style value never gates anything.
  `render.sh` prints the actual value for the bbox you just rendered.
- **`tags` must be a superset of the layer's `<Filter>`s.** It's a performance
  prefilter; narrower than the filters it feeds, it drops features silently.
- **Font face-names are exact, and a wrong one renders no text and no error.**
  In the bundled DejaVu, regular weight is `Book`, not `Regular`; Sans slants
  are `Oblique` while Serif slants are `Italic`. Run `scripts/fonts.sh` instead
  of guessing. DejaVu has no CJK, Thai or Devanagari; with the user's OK,
  `scripts/fetch-fonts.sh` adds Noto fonts for those (`references/fonts.md`).
- **A blank PNG is a query that matched nothing**, not a render failure: bbox
  outside the extract, over-narrow `tags`, missing sidecar, or a stale archive.

## Reference

| file | read it when |
|---|---|
| `references/setup.md` | toolchain install, building an archive + sidecar, debugging a blank render |
| `references/datasource.md` | choosing `<Layer>` datasource params, taginfo queries, synthetic attributes, geometry model |
| `references/cartography.md` | scale gating, casings, labels, and the symbolizer cookbook |
| `references/fonts.md` | any `TextSymbolizer`: exact face-names, script coverage, non-Latin fallback |
| `references/legend.md` | adding a legend panel to a finished render |
| `references/coastline.md` | the map touches a coast and land/water must read correctly |

## Templates

- `templates/thematic.xml` — faint context basemap + one highlighted theme.
  The usual starting point: swap the THEME layer for your subject.
- `templates/basemap.xml` — multi-scale general basemap: land/water, landuse,
  a road ramp with casings, scale-gated labels and POIs.
- `templates/coastline.xml` — the land-fill pattern, minimal.
- `templates/legend.json` — a legend spec for `basemap.xml`, to copy and edit.
