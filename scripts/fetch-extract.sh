#!/usr/bin/env bash
# Download an OSM extract from Geofabrik (download.geofabrik.de).
#
#   fetch-extract.sh --search minnesota          # find the region path
#   fetch-extract.sh --info us/minnesota         # URL + download size, no fetch
#   fetch-extract.sh us/minnesota [dest-dir]     # download + verify md5
#
# A region can be given as a Geofabrik id (`us/minnesota`), a full path
# (`north-america/us/minnesota`), or a complete .osm.pbf URL. Default dest-dir
# is $OSMFLAT_HOME/data. Resolving a bare id reads Geofabrik's index and so
# needs python3 or jq; a full path or URL needs neither.
#
# ASK THE USER FIRST. Extracts are large -- a US state is a few hundred MB, a
# continent is several GB. Use --info to get the real size, tell the user the
# size and destination, and download only once they agree.
#
# Geofabrik extracts are ODbL-licensed OpenStreetMap data.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/osmflat-env.sh"

GF_BASE="https://download.geofabrik.de"
GF_INDEX="$GF_BASE/index-v1.json"
GF_CACHE="$OSMFLAT_HOME/cache/geofabrik-index.json"

usage() {
    echo "usage: fetch-extract.sh --search <term>" >&2
    echo "       fetch-extract.sh --info   <region|url>" >&2
    echo "       fetch-extract.sh          <region|url> [dest-dir]" >&2
    exit 2
}

# The index is only needed to *discover* a region; a known path builds a URL
# directly, so this soft dependency never blocks the common case.
_gf_index() {
    local age=99999
    if [ -f "$GF_CACHE" ]; then
        age=$(( ($(date +%s) - $(stat -f %m "$GF_CACHE" 2>/dev/null \
                || stat -c %Y "$GF_CACHE" 2>/dev/null || echo 0)) / 86400 ))
    fi
    if [ ! -f "$GF_CACHE" ] || [ "$age" -ge 7 ]; then
        mkdir -p "$(dirname "$GF_CACHE")"
        osmflat_log "fetching the Geofabrik extract index..."
        curl -fsSL "$GF_INDEX" -o "$GF_CACHE.part" || osmflat_die "could not fetch $GF_INDEX"
        mv "$GF_CACHE.part" "$GF_CACHE"
    fi
    echo "$GF_CACHE"
}

_gf_search() {
    local term="$1" idx
    idx="$(_gf_index)"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$idx" "$term" <<'PY'
import json, sys
idx, term = sys.argv[1], sys.argv[2].lower()
feats = json.load(open(idx))["features"]
hits = [f["properties"] for f in feats
        if term in f["properties"]["id"].lower()
        or term in f["properties"].get("name", "").lower()]
if not hits:
    print("no match; browse https://download.geofabrik.de", file=sys.stderr)
    raise SystemExit(1)
for p in sorted(hits, key=lambda p: p["id"])[:40]:
    print(f'{p["id"]:<34}  {p.get("name","")}')
if len(hits) > 40:
    print(f'... and {len(hits)-40} more', file=sys.stderr)
PY
    elif command -v jq >/dev/null 2>&1; then
        jq -r --arg t "$term" '
            .features[].properties
            | select((.id|ascii_downcase|contains($t)) or ((.name//"")|ascii_downcase|contains($t)))
            | "\(.id)\t\(.name//"")"' "$idx" | sort | head -40
    else
        osmflat_die "--search needs python3 or jq. Browse $GF_BASE instead, then
pass the region path directly, e.g. fetch-extract.sh north-america/us/minnesota"
    fi
}

# Region -> .osm.pbf URL. A bare Geofabrik id (us/minnesota) has no continent
# prefix, so it is resolved through the index; a full path is used as-is.
_gf_url() {
    local region="$1" idx url
    case "$region" in
        http://*|https://*) echo "$region"; return ;;
    esac
    region="${region#/}"; region="${region%/}"
    region="${region%-latest.osm.pbf}"; region="${region%.osm.pbf}"

    idx="$(_gf_index 2>/dev/null || true)"
    if [ -n "$idx" ] && command -v python3 >/dev/null 2>&1; then
        url="$(python3 - "$idx" "$region" <<'PY'
import json, sys
idx, want = sys.argv[1], sys.argv[2].lower()
for f in json.load(open(idx))["features"]:
    p = f["properties"]
    if p["id"].lower() == want and "pbf" in p.get("urls", {}):
        print(p["urls"]["pbf"]); break
PY
)"
        [ -n "$url" ] && { echo "$url"; return; }
    fi
    # Not an index id: treat it as a path under the download root.
    echo "$GF_BASE/$region-latest.osm.pbf"
}

# Prints "<bytes> <content-type>" for a URL, empty if it is not a real extract.
#
# Geofabrik answers an unknown path with a 200 HTML error page rather than a
# 404, so -f does not catch a typo'd region -- without the content-type check a
# 9 KB HTML page gets saved as a .osm.pbf. Note also: no awk IGNORECASE, which
# is a gawk extension that BSD awk ignores (silently empty size on macOS).
_gf_head() {
    local hdr size type
    hdr="$(curl -fsSLI "$1" 2>/dev/null | tr -d '\r' || true)"
    size="$(printf '%s\n' "$hdr" | grep -i '^content-length:' | tail -1 | awk '{print $2}')"
    type="$(printf '%s\n' "$hdr" | grep -i '^content-type:'   | tail -1 | awk '{print $2}')"
    case "$type" in
        application/octet-stream|application/x-protobuf|binary/*) ;;
        *) return 0 ;;
    esac
    [ -n "$size" ] && printf '%s %s\n' "$size" "$type"
}

_gf_size() { _gf_head "$1" | awk '{print $1}'; }

_human() {
    local b="${1:-0}"
    awk -v b="$b" 'BEGIN{
        if (b >= 1073741824) printf "%.1f GB", b/1073741824;
        else if (b >= 1048576) printf "%.0f MB", b/1048576;
        else if (b > 0) printf "%.0f KB", b/1024;
        else printf "unknown size";
    }'
}

_gf_md5() {
    if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | cut -d' ' -f1
    elif command -v md5 >/dev/null 2>&1; then md5 -q "$1"
    fi
}

[ $# -ge 1 ] || usage

case "$1" in
    --search) [ $# -eq 2 ] || usage; _gf_search "$2"; exit 0 ;;
    --info)
        [ $# -eq 2 ] || usage
        url="$(_gf_url "$2")"
        size="$(_gf_size "$url")"
        [ -n "$size" ] || osmflat_die "no extract at $url
That path does not serve a .osm.pbf (Geofabrik answers unknown paths with an
HTML page, not a 404). Search for the right region:
  fetch-extract.sh --search <term>"
        echo "url:  $url"
        echo "size: $(_human "$size")"
        exit 0 ;;
    -h|--help) usage ;;
esac

REGION="$1"
DEST="${2:-$OSMFLAT_HOME/data}"
URL="$(_gf_url "$REGION")"
SIZE="$(_gf_size "$URL")"
[ -n "$SIZE" ] || osmflat_die "no extract at $URL
That path does not serve a .osm.pbf (Geofabrik answers unknown paths with an
HTML page, not a 404). Search for the right region:
  fetch-extract.sh --search <term>"

mkdir -p "$DEST"
PBF="$DEST/$(basename "$URL")"

osmflat_log "downloading $(basename "$URL") ($(_human "$SIZE")) -> $DEST"
curl -fL --progress-bar -o "$PBF.part" "$URL" || osmflat_die "download failed: $URL"
mv "$PBF.part" "$PBF"

# Geofabrik publishes an .md5 beside every extract.
if want="$(curl -fsSL "$URL.md5" 2>/dev/null | awk '{print $1}')" && [ -n "$want" ]; then
    got="$(_gf_md5 "$PBF")"
    if [ -z "$got" ]; then
        osmflat_log "warning: no md5sum or md5 command; skipping integrity check"
    fi
    if [ -n "$got" ] && [ "$want" != "$got" ]; then
        rm -f "$PBF"
        osmflat_die "md5 mismatch for $(basename "$URL")
  expected $want
  got      $got
The download was corrupted; it has been removed. Try again."
    fi
    [ -n "$got" ] && osmflat_log "md5 verified"
fi

echo
echo "downloaded: $PBF"
echo "next, build the archive + sidecar (slow, CPU and disk heavy):"
echo "  scripts/build-archive.sh \"$PBF\""
