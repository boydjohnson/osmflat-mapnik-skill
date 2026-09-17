---
name: osmflat-mapnik-skill
description: Create and iterate on Mapnik map styles rendered from an OpenStreetMap extract through the osmflat datasource. Introspect the OSM tag vocabulary with osmflat-taginfo, draft a Mapnik XML style, render it to a PNG, then Read the PNG and refine. Use when asked to make/design/tweak a map, basemap, or thematic map (e.g. "cycling map of Mexico City", "show water and parks", "roads colored by class", "where are the hospitals") from an osmflat archive.
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

## Setup

The scripts install the four binaries they need from GitHub releases on first
use, so usually there is nothing to do. The one thing you must supply is data:

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
- **`TextSymbolizer` needs `face-name="DejaVu Sans Book"`.** No face-name, no
  text — silently.
- **A blank PNG is a query that matched nothing**, not a render failure: bbox
  outside the extract, over-narrow `tags`, missing sidecar, or a stale archive.

## Reference

| file | read it when |
|---|---|
| `references/setup.md` | toolchain install, building an archive + sidecar, debugging a blank render |
| `references/datasource.md` | choosing `<Layer>` datasource params, taginfo queries, synthetic attributes, geometry model |
| `references/cartography.md` | scale gating, casings, labels, and the symbolizer cookbook |
| `references/coastline.md` | the map touches a coast and land/water must read correctly |

## Templates

- `templates/thematic.xml` — faint context basemap + one highlighted theme.
  The usual starting point: swap the THEME layer for your subject.
- `templates/basemap.xml` — multi-scale general basemap: land/water, landuse,
  a road ramp with casings, scale-gated labels and POIs.
- `templates/coastline.xml` — the land-fill pattern, minimal.
