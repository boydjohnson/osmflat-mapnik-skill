# Water/land fill (coastline closing)

`natural=coastline` ways mark a boundary, not a fillable area — there's no
polygon a `PolygonSymbolizer` can paint for "everything on the land side."
For any style where the ocean/bay needs to read as water and the mainland/
islands need to read as land (waterway maps, basemaps that touch a coast),
use the synthetic land layer instead of trying to fill `natural=coastline`
directly. `templates/coastline.xml` is this pattern, ready to copy.

## The pattern

1. Give the `<Map>` a water `background-color`.
2. Add a layer with `tags=_osmflat_land=yes` (a magic key; no real OSM entity
   ever carries it) and `<Filter>[_osmflat_land]='yes'</Filter>` in its style,
   `PolygonSymbolizer` filled land-color, `order=way_area`. This returns one
   closed-way feature per precomputed land ring; drawing largest-first with a
   plain painter's algorithm nests islands/lakes-on-islands correctly with no
   explicit hole/exterior pairing.
3. Put ordinary `natural=water`/`natural=bay`/waterway layers *after* the land
   layer so named lakes/bays/rivers still draw on top of the land fill.

## What the sidecar must have been built with

| flag | what it closes |
|---|---|
| `--land-polygons <shapefile>` | mainland **and** islands — preferred |
| `--coastline` | islands and lakes **only** |
| neither | nothing; the layer returns zero features |

A real mainland coastline is an open chain across any bounded extract and can
never close via ring assembly alone, which is why `--coastline` leaves the
mainland unfilled. `--land-polygons` imports already-closed rings from an
external shapefile in Web Mercator/EPSG:3857 — osmdata.openstreetmap.de's
`land-polygons` dataset.

`build-archive.sh` passes `--coastline` by default. For land polygons:

```
OSMFLAT_EXTC_ARGS="--land-polygons /path/to/land-polygons.shp" \
  scripts/build-archive.sh --ext-only /path/to/area.osm.flat
```

## Verifying

With neither flag, `_osmflat_land=yes` silently returns zero features — not an
error, just flat background water everywhere. If unsure what a sidecar was
built with, `ls` it for a `coastline` or `land_polygons` subdirectory, or
render a small test bbox over a known landmass and confirm it isn't blank.

A `--coastline`-only sidecar has a characteristic look at continental scale:
offshore islands and archipelagos fill land-color while the mainland stays
water. That is the expected failure, not a bug in the style.
