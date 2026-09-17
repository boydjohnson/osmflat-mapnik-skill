# osmflat-mapnik-skill

A [skill](SKILL.md) for designing Mapnik map styles over an OpenStreetMap
extract, rendered through the [osmflat](https://github.com/boydjohnson/osmflat-mapnik-plugin)
datasource. The agent introspects the archive's real tag vocabulary, drafts a
Mapnik XML style, renders it to a PNG, looks at the PNG, and iterates.

## Install

Drop this directory into `.claude/skills/osmflat-mapnik-skill/`, or install it
as a skill package. The scripts fetch what they need from GitHub releases on
first use — checksum-verified, into `${XDG_DATA_HOME:-~/.local/share}/osmflat`:

| binary | repo |
|---|---|
| `render` | [osmflat-mapnik-plugin](https://github.com/boydjohnson/osmflat-mapnik-plugin) |
| `osmflat-taginfo` | [osmflat-taginfo](https://github.com/boydjohnson/osmflat-taginfo) |
| `osmflatc` | [osmflat-rs](https://github.com/boydjohnson/osmflat-rs) |
| `osmflat-extc` | [osmflat-ext](https://github.com/boydjohnson/osmflat-ext) |

`scripts/install.sh` pre-warms or upgrades them all. Prebuilt targets: macOS
arm64, Linux x86_64/aarch64.

## Data

Point `OSMFLAT_ARCHIVE` at an osmflat archive, or build one from an `.osm.pbf`
extract ([geofabrik](https://download.geofabrik.de),
[bbbike](https://extract.bbbike.org)):

```sh
scripts/build-archive.sh /path/to/area.osm.pbf
export OSMFLAT_ARCHIVE=/path/to/area.osm.flat
```

## Use

```sh
scripts/taginfo.sh key highway values --format table --sortname count --sortorder desc
scripts/render.sh templates/basemap.xml out.png -93.30 44.95 -93.24 45.00
```

See [SKILL.md](SKILL.md) for the datasource parameters, the geometry model, the
coastline/land-fill pattern, and the scale-gating conventions.
