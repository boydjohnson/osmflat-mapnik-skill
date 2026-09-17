# Fonts and labels

A `face-name` mapnik cannot resolve renders **no text and no error** — the map
comes back looking like the label layer was never written. Never guess a
face-name.

```
scripts/fonts.sh            # face-names available to render.sh
scripts/fonts.sh --files    # ...and which file each comes from
```

## The bundled faces

The `render` release ships DejaVu and `render.sh` points mapnik at it. All 22
faces, each verified to render:

| family | faces |
|---|---|
| Sans | `DejaVu Sans Book`, `DejaVu Sans Bold`, `DejaVu Sans Oblique`, `DejaVu Sans Bold Oblique`, `DejaVu Sans ExtraLight` |
| Sans Condensed | `DejaVu Sans Condensed`, `DejaVu Sans Condensed Bold`, `DejaVu Sans Condensed Oblique`, `DejaVu Sans Condensed Bold Oblique` |
| Sans Mono | `DejaVu Sans Mono Book`, `DejaVu Sans Mono Bold`, `DejaVu Sans Mono Oblique`, `DejaVu Sans Mono Bold Oblique` |
| Serif | `DejaVu Serif Book`, `DejaVu Serif Bold`, `DejaVu Serif Italic`, `DejaVu Serif Bold Italic` |
| Serif Condensed | `DejaVu Serif Condensed`, `DejaVu Serif Condensed Bold`, `DejaVu Serif Condensed Italic`, `DejaVu Serif Condensed Bold Italic` |
| Math | `DejaVu Math TeX Gyre Regular` |

### Naming traps

A face-name is the family plus style as freetype reports it, which is **not**
the filename and not what you would guess:

- **Regular weight is `Book`**, not `Regular` — `DejaVu Sans Book`. The one
  exception is the math font, which really is `Regular`.
- **Sans slants are `Oblique`; Serif slants are `Italic`.** `DejaVu Sans
  Italic` and `DejaVu Serif Oblique` both render nothing.
- **Condensed takes no style suffix in the regular weight.** It is `DejaVu Sans
  Condensed`, *not* `DejaVu Sans Condensed Book` — freetype folds `Condensed`
  into the family name. Bold and slanted condensed faces do take the suffix.
- **ExtraLight is `DejaVu Sans ExtraLight`**, though the file's own family
  record says `DejaVu Sans Light`.

## Script coverage

DejaVu is broad but not universal. Verified against its character map:

| covered | not covered |
|---|---|
| Latin (incl. accents), Greek, Cyrillic, Arabic, Hebrew, Armenian, Georgian | **CJK** (Chinese, Japanese, Korean), **Thai**, **Devanagari** |

Names outside the covered set render as tofu boxes (`□□`), not as blanks — so a
map of Tokyo, Bangkok or Delhi labelled from `[name]` will come out visibly
broken rather than silently empty.

## Adding a font

**`MAPNIK_FONT_DIR` replaces the bundled directory; it does not extend it.**
Point it at a directory holding only your font and every DejaVu face stops
resolving. To add a font, copy the bundled fonts alongside it:

```
mkdir -p ~/myfonts
cp ~/.local/share/osmflat/pkg/osmflat-render-*/fonts/*.ttf ~/myfonts/
cp /path/to/YourFont.ttf ~/myfonts/
export MAPNIK_FONT_DIR=~/myfonts
scripts/fonts.sh                 # confirm the new face-name
```

## Falling back for non-Latin labels

Use a `<FontSet>` and reference it with `fontset-name` instead of `face-name`.
Mapnik walks the list per glyph, so Latin keeps DejaVu's look and only the
characters DejaVu lacks come from the fallback:

```xml
<FontSet name="labels">
  <Font face-name="DejaVu Sans Book"/>
  <Font face-name="Arial Unicode MS Regular"/>
</FontSet>
...
<TextSymbolizer fontset-name="labels" size="11" fill="#333"
                halo-fill="#fff" halo-radius="1.2">[name]</TextSymbolizer>
```

Verified: `Tokyo 東京` renders as `Tokyo □□` with `face-name="DejaVu Sans Book"`
and correctly as `Tokyo 東京` through the fontset above.

The fallback font must be in the font dir mapnik is using — which, per the
section above, means a directory holding both it and DejaVu.

## Label conventions

- Halos carry legibility over busy fills: `halo-fill="#ffffff"
  halo-radius="1.2"` is a reasonable default on a light basemap.
- Road labels use `placement="line"`; area labels use `placement="interior"`,
  which works on relation polygons and best-effort on closed ways.
- Label only what is named: `<Filter>[name] != ''</Filter>`.
- Gate labels with `<MaxScaleDenominator>` or a wide bbox drowns in them. See
  `references/cartography.md` for the degree-based scale values.
