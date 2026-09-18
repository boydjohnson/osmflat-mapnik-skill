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
broken rather than silently empty. To fix it, fetch a Noto family (below) and
use a FontSet.

## Fetching fonts from Google Fonts

`scripts/fetch-fonts.sh` downloads fonts from Google Fonts. Use it for a
writing system DejaVu can't show, or when the map calls for a different
typeface. **Ask the user first**: it's a download, and CJK fonts are large.

```
scripts/fetch-fonts.sh --info "Noto Sans:400,700" "Noto Sans JP"   # files + sizes, nothing downloaded
scripts/fetch-fonts.sh "Noto Sans:400,700" "Noto Sans JP"          # after the user agrees
scripts/fetch-fonts.sh --list                                      # what's fetched, as face-names
scripts/fetch-fonts.sh --remove "Noto Sans JP"
```

A family is `"Name"` for the regular weight, or `"Name:400,700,400i"` for a
list of weights (`i` means italic), spelled exactly as on fonts.google.com. A
misspelled family, or a weight the family doesn't come in, fails the whole
request.

Downloaded files go in `$OSMFLAT_HOME/fonts/google/`. Once that folder has
fonts in it, `render.sh` and `fonts.sh` load fonts from `$OSMFLAT_HOME/fonts/`
instead, which also links to the bundled DejaVu. Existing styles keep working:
a basemap renders pixel-identical either way.

**Google fonts use `Regular`, where DejaVu uses `Book`.** Examples:
`Noto Sans Regular`, `Noto Sans Bold`, `Noto Serif Italic`,
`Noto Sans JP Regular`. `Noto Sans Book` renders nothing. Run
`scripts/fonts.sh` after fetching and copy the names exactly.

Noto families for the writing systems DejaVu lacks (size per weight):

| writing system | family | size |
|---|---|---|
| Japanese | `Noto Sans JP` | 5 MB |
| Chinese, simplified | `Noto Sans SC` | 10 MB |
| Chinese, traditional | `Noto Sans TC` | 7 MB |
| Korean | `Noto Sans KR` | 6 MB |
| Thai | `Noto Sans Thai` | 45 KB |
| Devanagari | `Noto Sans Devanagari` | 214 KB |
| Bengali | `Noto Sans Bengali` | 136 KB |
| Tamil | `Noto Sans Tamil` | 76 KB |

Fetch only the weights the style uses. A CJK regular and bold together are
10–20 MB.

Limits:
- Google Fonts doesn't publish checksums. The script only checks that each
  file is a TrueType or OpenType font.
- The script relies on Google sending `.ttf` files to non-browser clients.
  That has worked for years, but Google doesn't document it. If Google starts
  sending browser formats, the script stops with a message rather than saving
  files mapnik can't load.
- The API always serves the newest version of a font, so re-fetching can
  change label widths slightly.

## Adding a font by hand

For a font that isn't on Google Fonts, copy the `.ttf`, `.otf` or `.ttc` file
into `$OSMFLAT_HOME/fonts/google/`. It's picked up the same way as fetched
fonts, and DejaVu stays available.

Setting `MAPNIK_FONT_DIR` yourself overrides all of this. **It replaces the
bundled directory rather than adding to it**, so if you point it at a folder
holding only your font, every DejaVu face stops resolving. If you use it,
copy the bundled fonts into that folder too:

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
characters DejaVu lacks come from the fallback. After
`scripts/fetch-fonts.sh "Noto Sans JP"`:

```xml
<FontSet name="labels">
  <Font face-name="DejaVu Sans Book"/>
  <Font face-name="Noto Sans JP Regular"/>
</FontSet>
...
<TextSymbolizer fontset-name="labels" size="11" fill="#333"
                halo-fill="#fff" halo-radius="1.2">[name]</TextSymbolizer>
```

Verified: `Tokyo 東京` renders as `Tokyo □□` with `face-name="DejaVu Sans Book"`
and correctly as `Tokyo 東京` through the fontset above.

The fallback font has to be somewhere mapnik loads fonts from. A font fetched
with `fetch-fonts.sh` already is. A font added by hand needs to go in
`$OSMFLAT_HOME/fonts/google/`, or in a `MAPNIK_FONT_DIR` folder that also holds
a copy of DejaVu.

## Label conventions

- Halos carry legibility over busy fills: `halo-fill="#ffffff"
  halo-radius="1.2"` is a reasonable default on a light basemap.
- Road labels use `placement="line"`; area labels use `placement="interior"`,
  which works on relation polygons and best-effort on closed ways.
- Label only what is named: `<Filter>[name] != ''</Filter>`.
- Gate labels with `<MaxScaleDenominator>` or a wide bbox drowns in them. See
  `references/cartography.md` for the degree-based scale values.
