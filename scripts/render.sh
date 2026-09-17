#!/usr/bin/env bash
# Render a Mapnik style through the osmflat datasource to a PNG -- then Read the
# PNG to see the result. Installs the `render` release on first use.
#
#   render.sh <style.xml> <out.png> <minx> <miny> <maxx> <maxy> [width height]
#   render.sh style.xml /tmp/out.png -93.33 44.93 -93.23 45.01     # Minneapolis
#
# @ARCHIVE@ / @EXT@ in the style are substituted with the resolved data paths.
# Data: OSMFLAT_ARCHIVE (required), OSMFLAT_EXT (guessed from the archive name).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/osmflat-env.sh"

if [ "$#" -ne 6 ] && [ "$#" -ne 8 ]; then
    echo "usage: render.sh <style.xml> <out.png> <minx> <miny> <maxx> <maxy> [width height]" >&2
    exit 2
fi
style="$1"; out="$2"; shift 2
[ -f "$style" ] || osmflat_die "no such style: $style"

RENDER="$(osmflat_need render)"
ARCHIVE="$(osmflat_archive)"
EXT="$(osmflat_ext "$ARCHIVE" || true)"

if [ -z "$EXT" ]; then
    osmflat_log "warning: no Ext sidecar found for $ARCHIVE."
    osmflat_log "  \`tags\` push-down and _osmflat_land=yes will not work."
    osmflat_log "  Build one: scripts/build-archive.sh --ext-only \"$ARCHIVE\""
fi

fonts="$(osmflat_font_dir "$RENDER")"
[ -n "$fonts" ] && export MAPNIK_FONT_DIR="$fonts"

# The style is a template; render the substituted copy from a temp file so the
# style on disk stays portable.
tmp="$(mktemp -t osmflat-style.XXXXXX)"
trap 'rm -f "$tmp"' EXIT
sed -e "s|@ARCHIVE@|$ARCHIVE|g" -e "s|@EXT@|${EXT:-}|g" "$style" > "$tmp"

# arg 1 is the plugin dir; the static release build has osmflat compiled in and
# ignores it, but the positional argument is still required.
"$RENDER" "$(dirname "$RENDER")" "$tmp" "$ARCHIVE" "$out" "$@"
