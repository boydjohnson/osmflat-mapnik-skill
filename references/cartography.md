# Conventions, gotchas, and a symbolizer cookbook

## Scale gating uses tiny numbers

The map SRS is geographic, so Mapnik's `scale_denominator` is degree-based, NOT
z-level numbers. Reference values at 1000px wide:

| view | ≈ denominator | | view | ≈ denominator |
|---|---|---|---|---|
| country (~30°) | 107 | | city (~0.35°) | 1.25 |
| state (~5°) | 18 | | metro (~0.06°) | 0.21 |
| region (~1.7°) | 6 | | neighborhood (~0.01°) | 0.036 |

So `<MaxScaleDenominator>0.1</MaxScaleDenominator>` hides detail past
~neighborhood; `12000`-style values never gate anything. `render.sh` prints the
actual value for the bbox you just rendered — read it off and gate against it.

`MaxScaleDenominator` caps drop fine detail as you zoom **out**. Leave the
coarse skeleton (motorway/trunk roads, big water and forest, city/town labels)
uncapped so it carries the state and country views.

## Gotchas

- **Casing = two `<Style>` passes**, not two symbolizers in one rule: a
  `casing` style (wide dark stroke) then a `fill` style (narrow colored) on the
  same layer, so casings tuck under fills at intersections. Add `order=z_order`.
- **Fonts**: `TextSymbolizer` needs `face-name="DejaVu Sans Book"` (bundled
  with the `render` release; `render.sh` points mapnik at it). No text renders
  without a valid face-name.
- **Area labels**: `placement="interior"` works on relation polygons (and
  best-effort on closed ways). Road labels use `placement="line"`.
- **`MarkersSymbolizer`** logs a benign `SVG parse error: … 100%` — ignore it;
  `marker-type="ellipse"`/`"arrow"` still render.
- **Numeric filters** need the key in `numeric=` or they compare as strings
  (`'10' < '4'`).
- **`tags` must stay a superset** of the layer's `<Filter>`s or you'll silently
  drop features.
- **Gate labels**, or a wide bbox drowns in them. Unreadable label soup is the
  most common way a technically-correct style fails as a map.

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
- **Water/land fill**: background water color + `tags=_osmflat_land=yes` layer
  (`order=way_area`) painted land-color, ordinary water layers after it — see
  `references/coastline.md`.
