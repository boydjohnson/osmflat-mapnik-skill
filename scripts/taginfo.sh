#!/usr/bin/env bash
# Introspect the OSM tag vocabulary of the archive, so style filters are
# grounded in what the data actually contains. Installs `osmflat-taginfo` on
# first use. Wraps the taginfo.openstreetmap.org-compatible CLI.
#
#   taginfo.sh key highway values --format table --sortname count --sortorder desc
#   taginfo.sh key highway combinations --format table --sortname together_count
#   taginfo.sh tag natural=water stats
#   taginfo.sh keys --format table --rp 40
#
# Needs an Ext sidecar built with `osmflat-extc --taginfo`.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/osmflat-env.sh"

TAGINFO="$(osmflat_need osmflat-taginfo)"
ARCHIVE="$(osmflat_archive)"
EXT="$(osmflat_ext "$ARCHIVE" || true)"

[ -n "$EXT" ] || osmflat_die "no Ext sidecar found for $ARCHIVE (taginfo needs one).
Build it:  scripts/build-archive.sh --ext-only \"$ARCHIVE\"
Or point at an existing one with OSMFLAT_EXT=/path/to/area.ext"

exec "$TAGINFO" -a "$ARCHIVE" -x "$EXT" "$@"
