#!/usr/bin/env bash
# Turn an .osm.pbf extract into the archive pair the renderer needs:
#   area.osm.pbf --osmflatc--> area.osm.flat --osmflat-extc--> area.osm.ext
#
#   build-archive.sh <area.osm.pbf> [out-dir]
#   build-archive.sh --ext-only <area.osm.flat>     # rebuild just the sidecar
#
# Get extracts from download.geofabrik.de or extract.bbbike.org. Both tools
# install from their latest release on first use.
#
# Sidecar features built here (all of them; drop flags to save time/space):
#   --taginfo --combinations   tag introspection for taginfo.sh
#   --multipolygons            precomputed relation rings (area fills)
#   --backrefs                 reverse references
#   --coastline                island/lake ring closing
#
# Coastal areas: pass --land-polygons <shapefile> through with
#   OSMFLAT_EXTC_ARGS="--land-polygons /path/to/land-polygons.shp"
# (from osmdata.openstreetmap.de). That is what makes `_osmflat_land=yes` close
# a mainland coastline; --coastline alone only closes islands and lakes.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/osmflat-env.sh"

EXT_ONLY=0
if [ "${1:-}" = "--ext-only" ]; then EXT_ONLY=1; shift; fi
[ $# -ge 1 ] || { echo "usage: build-archive.sh <area.osm.pbf> [out-dir]   |   build-archive.sh --ext-only <area.osm.flat>" >&2; exit 2; }

EXTC="$(osmflat_need osmflat-extc)"
extc_args=(--taginfo --combinations --multipolygons --backrefs --coastline)
# shellcheck disable=SC2206
[ -n "${OSMFLAT_EXTC_ARGS:-}" ] && extc_args+=(${OSMFLAT_EXTC_ARGS})

if [ "$EXT_ONLY" = 1 ]; then
    ARCHIVE="$1"
    [ -d "$ARCHIVE" ] || osmflat_die "no such archive directory: $ARCHIVE"
else
    PBF="$1"
    [ -f "$PBF" ] || osmflat_die "no such pbf: $PBF"
    ARCHIVE="${2:-${PBF%.pbf}.flat}"
    OSMFLATC="$(osmflat_need osmflatc)"
    osmflat_log "compiling $PBF -> $ARCHIVE (this is the slow step)"
    "$OSMFLATC" "$PBF" "$ARCHIVE"
fi

OUT="${OSMFLAT_EXT:-${ARCHIVE%.flat}.ext}"
osmflat_log "building sidecar $OUT (${extc_args[*]})"
"$EXTC" "$ARCHIVE" --out "$OUT" "${extc_args[@]}"

echo
echo "done. Point the renderer at it:"
echo "  export OSMFLAT_ARCHIVE=$ARCHIVE"
echo "  export OSMFLAT_EXT=$OUT"
