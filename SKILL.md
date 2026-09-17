---
name: osmflat-mapnik-skill
description: Create and iterate on Mapnik map styles rendered from an OpenStreetMap extract through the osmflat datasource. Introspect the OSM tag vocabulary with osmflat-taginfo, draft a Mapnik XML style, render it to a PNG, then Read the PNG and refine. Use when asked to make/design/tweak a map, basemap, or thematic map (e.g. "cycling map of Mexico City", "show water and parks", "roads colored by class", "where are the hospitals") from an osmflat archive.
---

# OSM map styling (osmflat + Mapnik)

You produce a Mapnik `Map` XML style, render it through the osmflat datasource,
look at the PNG, and iterate. Work the loop — don't try to one-shot a style.

## The loop

1. **Introspect** — find the real tags/values for the subject with
   `scripts/taginfo.sh` (don't guess OSM tagging; the archive tells you what
   exists and how common it is).
2. **Draft** — write a `Map` XML (start from `templates/thematic.xml`). Set each
   layer's datasource params.
3. **Render** — `scripts/render.sh <style.xml> <out.png> <minx> <miny> <maxx> <maxy>`.
4. **Look** — `Read` the PNG. Judge it as a map: is the subject legible, the
   context right, labels placed, nothing flooded or empty?
5. **Refine** — adjust filters/colors/widths/scale caps and re-render. Repeat.

Scratch styles/PNGs go in the scratchpad dir, not the repo.

## 0. Setup

The scripts install what they need from GitHub releases on first use — nothing
to do ahead of time. `scripts/install.sh` pre-warms or upgrades all four:

| binary | repo | role |
|---|---|---|
| `render` | boydjohnson/osmflat-mapnik-plugin | style.xml → PNG (mapnik statically linked in, fonts bundled) |
| `osmflat-taginfo` | boydjohnson/osmflat-taginfo | tag introspection |
| `osmflatc` | boydjohnson/osmflat-rs | `.osm.pbf` → `.osm.flat` |
| `osmflat-extc` | boydjohnson/osmflat-ext | `.osm.flat` → `.ext` sidecar |

They land in `${XDG_DATA_HOME:-~/.local/share}/osmflat`, checksum-verified
against the release `SHA256SUMS`. A binary already on `PATH` wins, so a local
dev build shadows the release. Prebuilt targets are macOS arm64 and Linux
x86_64/aarch64; anything else has to be built from source.

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

## 1. Introspect with taginfo

```
scripts/taginfo.sh key highway values --format table --sortname count --sortorder desc
scripts/taginfo.sh key highway combinations --format table --sortname together_count
scripts/taginfo.sh key amenity values --format table --sortname count --sortorder desc
scripts/taginfo.sh tag natural=water stats
```
Use it to pick which key(s) and value(s) carry the theme, and which co-tags to
style/label (`name`, `ref`, `lanes`, `surface`, …). Counts are from the loaded
extract, not the live planet — which is exactly what you want, since a value
with 12 hits in this archive will not carry a map. Add `--bbox MINX MINY MAXX
MAXY` to count only inside the area you're about to render.

## 2. Datasource params (per `<Layer>`)

| param | purpose |
|---|---|
| `type`=`osmflat` | selects the plugin (required) |
| `file`=`@ARCHIVE@` | archive dir (render.sh substitutes) |
| `ext`=`@EXT@` | Ext sidecar → enables `tags` push-down (render.sh substitutes) |
| `osm_type` | `node`\|`way`\|`relation`\|`all`, comma-separated (e.g. `way,relation`) |
| `tags` | tag prefilter `key=value`/`key=*`, comma-separated. **Must be a superset of the layer's `<Filter>`s.** Huge speedup at wide zoom |
| `numeric` | comma-separated keys to expose as numbers (so `[lanes] > 2` compares numerically) |
| `order` | `z_order` (roads: minor under major, bridges last) or `way_area` (areas: large under small) |
| `simplify` | Douglas–Peucker px tolerance (default 0.5, on; `0` off) |

**Synthetic attributes** always available on every feature: `osm_id` (Integer),
`osm_type` (String node/way/relation), `is_closed` (Boolean), `way_area`
(Double, spherical m² — `[way_area] > 1000000` = areas > 1 km²), `z_order`
(Integer). Every other attribute is a raw OSM tag, exposed only when a
`<Filter>`/symbolizer references it (`[name]`, `[highway]`, …), null when absent.

## 3. Geometry model (semantically neutral)

- node → `point`; way → `line_string` (open OR closed); `type=multipolygon`/
  `boundary` relation → `multi_polygon`. No area heuristics — **you** decide.
- A closed way fills with `PolygonSymbolizer` (it auto-closes the ring) and/or
  strokes with `LineSymbolizer`. For area fills, query `osm_type=way,relation`.
- "Has a tag" filter is `[k] != ''`; exact is `[k]='v'`. Absent tags are null and
  never match, so `[k] != ''` cleanly means "tagged with k".

## 4. Water/land fill (coastline closing)

`natural=coastline` ways mark a boundary, not a fillable area — there's no
polygon a `PolygonSymbolizer` can paint for "everything on the land side."
For any style where the ocean/bay needs to read as water and the mainland/
islands need to read as land (waterway maps, basemaps that touch a coast),
use the synthetic land layer instead of trying to fill `natural=coastline`
directly — see `templates/coastline.xml`:

1. Give the `<Map>` a water `background-color`.
2. Add a layer with `tags=_osmflat_land=yes` (a magic key; no real OSM entity
   ever carries it) and `<Filter>[_osmflat_land]='yes'</Filter>` in its style,
   `PolygonSymbolizer` filled land-color, `order=way_area`. This returns one
   closed-way feature per precomputed land ring; drawing largest-first with a
   plain painter's algorithm nests islands/lakes-on-islands correctly with no
   explicit hole/exterior pairing.
3. Put ordinary `natural=water`/`natural=bay`/waterway layers *after* the land
   layer so named lakes/bays/rivers still draw on top of the land fill.

This only works if the Ext sidecar was built with
`osmflat-extc --land-polygons <shapefile>` (preferred — closes mainland
coastlines too, imported from osmdata.openstreetmap.de's `land-polygons`
dataset) or, failing that, `--coastline` (closes islands/lakes only; a real
mainland coastline is an open chain across any bounded extract and can never
close via ring assembly alone). `build-archive.sh` passes `--coastline` by
default; for land polygons:

```
OSMFLAT_EXTC_ARGS="--land-polygons /path/to/land-polygons.shp" \
  scripts/build-archive.sh --ext-only /path/to/area.osm.flat
```

Without either, `_osmflat_land=yes` silently returns zero features — not an
error, just flat background water everywhere. If unsure what a sidecar was
built with, `ls` it (a `coastline` or `land_polygons` subdirectory) or render a
small test bbox over a known landmass and confirm it isn't blank.

## 5. Render + look

```
scripts/render.sh style.xml /tmp/out.png -93.30 44.95 -93.24 45.00   # downtown Minneapolis
scripts/render.sh style.xml /tmp/out.png -99.30 19.20 -98.95 19.60 1600 1200
```
Args 7/8 are optional pixel width/height (default 1000×1000). Then `Read` the
PNG — that is the point of the loop; a style you haven't looked at isn't done.

## Conventions & gotchas (read before styling)

- **Scale gating uses tiny numbers.** The map SRS is geographic, so Mapnik's
  `scale_denominator` is degree-based, NOT z-level numbers. Reference:
  country ≈107, state ≈18, region ≈6, city ≈1.25, metro ≈0.21, neighborhood
  ≈0.036. So `<MaxScaleDenominator>0.1</MaxScaleDenominator>` hides detail past
  ~neighborhood; `12000`-style values never gate. render.sh prints the actual
  value for the bbox you just rendered — read it off and gate against it.
- **Casing = two `<Style>` passes**, not two symbolizers in one rule: a `casing`
  style (wide dark stroke) then a `fill` style (narrow colored) on the same
  layer, so casings tuck under fills at intersections. Add `order=z_order`.
- **Fonts**: `TextSymbolizer` needs `face-name="DejaVu Sans Book"` (bundled with
  the `render` release; render.sh points mapnik at it). No text renders without
  a valid face-name.
- **Area labels**: `placement="interior"` works on relation polygons (and best-
  effort on closed ways). Road labels use `placement="line"`.
- **`MarkersSymbolizer`** logs a benign `SVG parse error: … 100%` — ignore it;
  `marker-type="ellipse"`/`"arrow"` still render.
- **Numeric filters** need the key in `numeric=` or they compare as strings
  (`'10' < '4'`). **`way_area`/`z_order`** are already numeric.
- **`tags` must stay a superset** of the layer's `<Filter>`s or you'll silently
  drop features. It's a performance prefilter, not a replacement for `<Filter>`.
- **A blank PNG with no error** means the query matched nothing: bbox outside
  the extract, a `tags` prefilter narrower than the `<Filter>`, a missing
  sidecar, or a stale archive. Bisect by rendering one layer with no `tags`.

## Symbolizer cookbook

- **Road ramp**: filter `[highway]=...` per class; `LineSymbolizer` width by
  class; casing+fill passes; `order=z_order`.
- **Area fills**: `PolygonSymbolizer fill="..."`; gate small ones with
  `[way_area] > N`; `order=way_area`; `osm_type=way,relation`.
- **Labels**: `TextSymbolizer ... placement="line|interior">[name]</TextSymbolizer>`
  with `halo-fill`/`halo-radius`. Only named: `[name] != ''`.
- **POIs**: `MarkersSymbolizer marker-type="ellipse"` on `osm_type=node` +
  `TextSymbolizer [name]`. Gate with `<MaxScaleDenominator>` so they show only
  when zoomed in.
- **Oneway arrows**: `MarkersSymbolizer marker-type="arrow" placement="line"`.
- **Water/land fill**: background water color + `tags=_osmflat_land=yes`
  layer (`order=way_area`) painted land-color, ordinary water layers after
  it — see §4.

## Templates

- `templates/thematic.xml` — faint context basemap + one highlighted theme.
  The usual starting point: swap the THEME layer for your subject.
- `templates/basemap.xml` — multi-scale general basemap: land/water, landuse,
  a road ramp with casings, scale-gated labels and POIs.
- `templates/coastline.xml` — the §4 land-fill pattern, minimal.
