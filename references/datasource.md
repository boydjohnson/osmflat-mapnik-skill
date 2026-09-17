# Datasource: querying the archive

## Introspect with taginfo

Don't guess OSM tagging — the archive tells you what exists and how common it
is.

```
scripts/taginfo.sh key highway values --format table --sortname count --sortorder desc
scripts/taginfo.sh key highway combinations --format table --sortname together_count
scripts/taginfo.sh key amenity values --format table --sortname count --sortorder desc
scripts/taginfo.sh tag natural=water stats
scripts/taginfo.sh keys --format table --rp 40
```

Use it to pick which key(s) and value(s) carry the theme, and which co-tags to
style/label (`name`, `ref`, `lanes`, `surface`, …). Counts are from the loaded
extract, not the live planet — which is exactly what you want, since a value
with 12 hits in this archive will not carry a map. Add
`--bbox MINX MINY MAXX MAXY` to count only inside the area you're about to
render.

## Datasource params (per `<Layer>`)

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

`tags` is a performance prefilter, not a replacement for `<Filter>`. If it is
narrower than the filters it feeds, features are dropped silently.

## Synthetic attributes

Always available on every feature:

| attribute | type | notes |
|---|---|---|
| `osm_id` | Integer | |
| `osm_type` | String | `node` / `way` / `relation` |
| `is_closed` | Boolean | |
| `way_area` | Double | spherical m² — `[way_area] > 1000000` = areas > 1 km² |
| `z_order` | Integer | |

Every other attribute is a raw OSM tag, exposed only when a `<Filter>` or
symbolizer references it (`[name]`, `[highway]`, …), and null when absent.

`way_area` and `z_order` are already numeric. Any other key needs to be listed
in `numeric=` or it compares as a string (`'10' < '4'`).

## Geometry model (semantically neutral)

- node → `point`; way → `line_string` (open OR closed); `type=multipolygon` /
  `boundary` relation → `multi_polygon`. No area heuristics — **you** decide.
- A closed way fills with `PolygonSymbolizer` (it auto-closes the ring) and/or
  strokes with `LineSymbolizer`. For area fills, query `osm_type=way,relation`.
- "Has a tag" filter is `[k] != ''`; exact is `[k]='v'`. Absent tags are null
  and never match, so `[k] != ''` cleanly means "tagged with k".
