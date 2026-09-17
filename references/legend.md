# Legends

`scripts/add-legend.py` draws a legend panel onto a rendered PNG. Swatch colors
are read from the style XML at run time, so the legend cannot drift from the
palette; only the human labels are curated, since those can't be derived from a
Filter expression.

It is a post-processing step — render first, then attach.

Run it with `uv`. Pillow is declared inline in the script (PEP 723), so `uv
run` fetches it into a throwaway environment: nothing to install first, and
nothing added to the system Python. The shebang does the same, so
`./scripts/add-legend.py` works directly wherever `uv` is on PATH.

```
uv run scripts/add-legend.py --xml style.xml --list
```

Without `uv`, `python3 scripts/add-legend.py ...` still works provided Pillow
is installed; the script says so if it isn't.

## Workflow

1. **Inspect the style** to see what can go in the legend. Don't guess style
   names or rule indices:
   ```
   uv run scripts/add-legend.py --xml style.xml --list
   ```
   It prints every `<Style>`, each `Rule` with its index, the filter it matches,
   the colors it draws, and a suggested swatch `kind`.
2. **Write a spec** naming the rules to show and what to call them
   (`templates/legend.json` is a working example for `templates/basemap.xml`).
3. **Render, then attach:**
   ```
   scripts/render.sh style.xml out.png -93.30 44.95 -93.24 45.00
   uv run scripts/add-legend.py --xml style.xml --png out.png --spec legend.json
   ```

## Spec format

```json
{
  "title": "Legend",
  "position": "sw",
  "entries": [
    {"style": "landcover",    "rule": 0, "kind": "fill", "label": "Water"},
    {"style": "streets-fill", "rule": 0, "kind": "line", "label": "Motorway"},
    {"style": "bike-routes",  "rule": 0, "kind": "line-multi", "label": "Bike Route"},
    {"style": "pois",         "rule": 0, "kind": "dot",  "label": "Cafe"}
  ]
}
```

| field | meaning |
|---|---|
| `title` | panel heading; `""` omits it. Default `Legend` |
| `position` | `sw` (default), `se`, `nw`, `ne` |
| `background` | panel fill; defaults to the Map's `background-color` |
| `style` | the `<Style name="...">` the swatch reads from |
| `rule` | 0-based index into that style's `<Rule>`s |
| `kind` | how to draw the swatch (below) |
| `label` | the text shown |

`--title` and `--position` on the command line override the spec.

### Swatch kinds

| kind | reads | draws |
|---|---|---|
| `fill` | `PolygonSymbolizer fill` + optional `LineSymbolizer stroke` | filled rectangle with outline |
| `line` | `LineSymbolizer stroke` / `stroke-width` | a stroke of that color |
| `line-multi` | all `LineSymbolizer`s in the rule | casing + fill, for a two-pass road |
| `dot` | `MarkersSymbolizer fill` / `stroke` | a filled circle |

`line-multi` takes the widest stroke as the casing and the narrowest non-white
one as the true color, which is the usual casing/fill pairing. For a road ramp
built as two separate `<Style>` passes, point `line` at the *fill* style — the
casing style on its own reads as an undifferentiated dark line.

## Re-running is safe

The first run caches the legend-free render as `<name>.pristine.png` and stamps
the output with a PNG metadata marker. Every later run redraws from the cache,
so legends never stack. Re-rendering the map overwrites the target with a fresh
unmarked PNG, which is detected and refreshes the cache automatically — so the
normal loop of *render → attach → tweak style → render → attach* just works.

Keep the `.pristine.png` next to the map. If it goes missing while the target
still carries the marker, the script warns and proceeds, and that run will
stack a second legend on the first.

## Fonts

Labels use DejaVu from the `render` release, found via `MAPNIK_FONT_DIR`, else
`$OSMFLAT_HOME/pkg/osmflat-render-*/fonts`, else `--font-dir`. If none is
found it falls back to Pillow's bitmap font and says so — legible, but ugly.
See `references/fonts.md`.
