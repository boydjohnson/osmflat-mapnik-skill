# osmflat-mapnik-skill

A [skill](SKILL.md) for designing Mapnik map styles over an OpenStreetMap
extract, rendered through the [osmflat](https://github.com/boydjohnson/osmflat-mapnik-plugin)
datasource. The agent introspects the archive's real tag vocabulary, drafts a
Mapnik XML style, renders it to a PNG, looks at the PNG, and iterates.

## Install

Drop this directory into `.claude/skills/osmflat-mapnik-skill/`, or install it
as a skill package. The skill uses four prebuilt tools from the author's GitHub
releases. They are installed only when you run `scripts/install.sh`
(`--info` shows what it would download first). Each one is checked against its
release's `SHA256SUMS` and unpacked into `${XDG_DATA_HOME:-~/.local/share}/osmflat`:

| binary | repo |
|---|---|
| `render` | [osmflat-mapnik-plugin](https://github.com/boydjohnson/osmflat-mapnik-plugin) |
| `osmflat-taginfo` | [osmflat-taginfo](https://github.com/boydjohnson/osmflat-taginfo) |
| `osmflatc` | [osmflat-rs](https://github.com/boydjohnson/osmflat-rs) |
| `osmflat-extc` | [osmflat-ext](https://github.com/boydjohnson/osmflat-ext) |

Run `scripts/install.sh` again to upgrade, or set `OSMFLAT_AUTO_INSTALL=1` to
install on first use.

### Requirements

- **macOS arm64 or Linux x86_64.** Those are the two platforms with prebuilt
  releases of all four tools. Linux aarch64 has `render` only; Intel macOS has
  none. Anything else means building from source.
- `bash`, `curl`, `tar`, and `sha256sum`/`shasum`.
- [`uv`](https://docs.astral.sh/uv/) for `scripts/add-legend.py`, which
  declares Pillow inline — or `python3` with Pillow already installed.
- `python3` for `scripts/fonts.sh` and Geofabrik region search (`jq` also works
  for the latter).

No system mapnik needed: the `render` release is statically linked and ships
its own fonts. See [references/setup.md](references/setup.md) for the full
table.

## Data

Point `OSMFLAT_ARCHIVE` at an osmflat archive, or build one from an `.osm.pbf`
extract:

```sh
scripts/build-archive.sh /path/to/area.osm.pbf
export OSMFLAT_ARCHIVE=/path/to/area.osm.flat
```

No extract on hand? Fetch one from [Geofabrik](https://download.geofabrik.de)
(md5-verified; `--info` reports the download size first):

```sh
scripts/fetch-extract.sh --search minnesota
scripts/fetch-extract.sh --info us/minnesota
scripts/fetch-extract.sh us/minnesota
```

## Use

```sh
scripts/taginfo.sh key highway values --format table --sortname count --sortorder desc
scripts/render.sh templates/basemap.xml out.png -93.30 44.95 -93.24 45.00
```

[SKILL.md](SKILL.md) is the entry point — the render loop and the handful of
conventions that cause the most wasted renders. The detail lives alongside it:

| file | covers |
|---|---|
| [references/setup.md](references/setup.md) | toolchain install, building an archive + sidecar, debugging a blank render |
| [references/datasource.md](references/datasource.md) | `<Layer>` datasource params, taginfo queries, synthetic attributes, geometry model |
| [references/cartography.md](references/cartography.md) | scale gating, casings, labels, symbolizer cookbook |
| [references/fonts.md](references/fonts.md) | face-names, script coverage, fetching Google Fonts, non-Latin fallback |
| [references/legend.md](references/legend.md) | drawing a legend panel onto a finished render |
| [references/coastline.md](references/coastline.md) | land/water fill where the map touches a coast |

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT](LICENSE-MIT) at your option, matching the rest of the osmflat projects.

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in this work by you, as defined in the Apache-2.0 license, shall
be dual licensed as above, without any additional terms or conditions.

`templates/basemap.xml` is carried over from
[osmflat-mapnik-plugin](https://github.com/boydjohnson/osmflat-mapnik-plugin)
(MIT). Map data fetched by `scripts/fetch-extract.sh` is OpenStreetMap, under
the [ODbL](https://www.openstreetmap.org/copyright) — that license covers the
data, not this skill.
