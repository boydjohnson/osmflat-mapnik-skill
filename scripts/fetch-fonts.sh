#!/usr/bin/env bash
# Fetch fonts from Google Fonts, for scripts DejaVu lacks (CJK, Thai,
# Devanagari, ...) or for typographic choice.
#
#   fetch-fonts.sh --info "Noto Sans:400,700" "Noto Sans JP"   # files and sizes; downloads nothing
#   fetch-fonts.sh "Noto Sans:400,700" "Noto Sans JP"          # download
#   fetch-fonts.sh --list                                      # fetched fonts, as face-names
#   fetch-fonts.sh --remove "Noto Sans JP"                     # delete a fetched family
#
# A family is "Name" (regular weight) or "Name:400,700,400i": weights, with an
# `i` suffix for italic. Names are spelled exactly as on fonts.google.com.
#
# ASK THE USER FIRST. Run --info, tell them the families, total size and
# destination, and download only once they agree. Latin families are about
# 0.5 MB per weight; CJK families are about 5 MB per weight.
#
# Files go to $OSMFLAT_HOME/fonts/google/. Once any are there, render.sh and
# fonts.sh point mapnik at $OSMFLAT_HOME/fonts/, which also links the bundled
# DejaVu, so every existing face-name keeps working. Check the new names with
# fonts.sh: Google fonts use "Regular" where DejaVu uses "Book".
#
# Google Fonts publishes no checksums; each file is checked to be a TrueType or
# OpenType font before it is kept. Fonts are OFL or Apache licensed.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/osmflat-env.sh"

GF_CSS="https://fonts.googleapis.com/css2"
GDIR="$OSMFLAT_HOME/fonts/google"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "usage: fetch-fonts.sh [--info] <family[:weights]>...   e.g. \"Noto Sans:400,700\"" >&2
    echo "       fetch-fonts.sh --list" >&2
    echo "       fetch-fonts.sh --remove <family>" >&2
    exit 2
}

# File stem for a family: "Noto Sans JP" -> "NotoSansJP"
_stem() { printf '%s' "$1" | tr -d ' '; }

# "i" for italic, else nothing. Must always succeed: a bare `[ ] && echo i`
# inside an assignment fails the assignment for upright fonts, and set -e
# then exits without a word.
_sfx() { if [ "$1" = italic ]; then echo i; fi; }

# "Noto Sans:400,700i" -> "family=Noto+Sans:ital,wght@0,400;1,700"
_css_param() {
    local spec="$1" name weights w tuples="" italic=0 list
    name="${spec%%:*}"
    # Google family names are letters, digits and spaces; anything else is a
    # typo, and must not be pasted into a URL.
    case "$name" in *[!A-Za-z0-9\ ]*|"") osmflat_die "not a Google Fonts family name: '$name'" ;; esac
    weights=""; [ "$spec" != "$name" ] && weights="${spec#*:}"
    [ -z "$weights" ] && weights=400
    for w in ${weights//,/ }; do
        case "$w" in
            [1-9]00)  tuples+="0,$w"$'\n' ;;
            [1-9]00i) tuples+="1,${w%i}"$'\n'; italic=1 ;;
            *) osmflat_die "bad weight '$w' in '$spec': use 100-900, with an i suffix for italic" ;;
        esac
    done
    # The API requires the tuples sorted, and rejects duplicates.
    list="$(printf '%s' "$tuples" | sort -t, -k1,1n -k2,2n -u)"
    if [ "$italic" = 1 ]; then
        printf 'family=%s:ital,wght@%s' "${name// /+}" "$(printf '%s' "$list" | paste -sd';' -)"
    else
        printf 'family=%s:wght@%s' "${name// /+}" "$(printf '%s' "$list" | cut -d, -f2 | paste -sd';' -)"
    fi
}

# Print "family|style|weight|url" per font file for the requested families.
_resolve() {
    local query="" spec css
    for spec in "$@"; do query+="${query:+&}$(_css_param "$spec")"; done
    css="$(curl -fsL "$GF_CSS?$query")" || osmflat_die "Google Fonts rejected the request.
Check each family name and weight on fonts.google.com: a family that does not
exist, or a weight it does not come in, fails the whole request."
    printf '%s\n' "$css" | awk -F"'" '
        /font-family/ { fam = $2 }
        /font-style/  { sty = ($0 ~ /italic/) ? "italic" : "normal" }
        /font-weight/ { w = $0; gsub(/[^0-9]/, "", w) }
        /src:/        { match($0, /https:[^)]*/); print fam "|" sty "|" w "|" substr($0, RSTART, RLENGTH) }'
}

# Mapnik reads TrueType/OpenType. Google sends WOFF2 to browsers; if it ever
# sends that here too, stop rather than save files mapnik cannot load.
_check_formats() {
    local rows="$1" dups
    printf '%s\n' "$rows" | cut -d'|' -f4 | grep -v '\.ttf$' | head -1 | grep -q . && \
        osmflat_die "Google Fonts served a non-TrueType format:
$(printf '%s\n' "$rows" | cut -d'|' -f4 | grep -v '\.ttf$' | head -3)
mapnik cannot load it. This script relies on Google serving .ttf to non-browser
clients; that behavior seems to have changed."
    # One file per family/style/weight. More means the font is split into
    # unicode-range subsets, and keeping one would silently drop glyphs.
    dups="$(printf '%s\n' "$rows" | cut -d'|' -f1-3 | sort | uniq -d)"
    [ -z "$dups" ] || osmflat_die "Google Fonts split these into subsets, which this script does not handle:
$dups"
}

_is_font() {
    local magic
    magic="$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')"
    case "$magic" in 00010000|4f54544f|74727565) return 0 ;; *) return 1 ;; esac
}

_list() {
    if [ ! -d "$GDIR" ] || [ -z "$(ls -A "$GDIR" 2>/dev/null)" ]; then
        echo "no fonts fetched yet ($GDIR)"; return
    fi
    if command -v python3 >/dev/null 2>&1; then
        "$HERE/fonts.sh" --dir "$GDIR" --files
    else
        ls -1 "$GDIR"
    fi
}

[ $# -ge 1 ] || usage
command -v curl >/dev/null 2>&1 || osmflat_die "curl is required"

case "$1" in
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --list) _list; exit 0 ;;
    --remove)
        [ $# -eq 2 ] || usage
        stem="$(_stem "$2")"
        shopt -s nullglob
        files=("$GDIR/$stem"-*.ttf)
        [ ${#files[@]} -gt 0 ] || osmflat_die "no fetched files for '$2' in $GDIR"
        rm -f "${files[@]}"
        printf 'removed %s\n' "${files[@]##*/}"
        exit 0 ;;
esac

INFO=0
if [ "$1" = "--info" ]; then INFO=1; shift; fi
[ $# -ge 1 ] || usage

rows="$(_resolve "$@")"
[ -n "$rows" ] || osmflat_die "Google Fonts returned no font files for: $*"
_check_formats "$rows"

if [ "$INFO" = 1 ]; then
    total=0
    while IFS='|' read -r fam sty w url; do
        size="$(curl -fsSLI "$url" 2>/dev/null | tr -d '\r' | grep -i '^content-length:' | tail -1 | awk '{print $2}')"
        total=$(( total + ${size:-0} ))
        printf '  %-28s %-7s %s  %s\n' "$fam" "$w$(_sfx "$sty")" "$(_osmflat_human "${size:-0}")" "${url##*/}"
    done <<<"$rows"
    echo "total $(_osmflat_human "$total") from fonts.gstatic.com, into $GDIR/"
    echo "Nothing downloaded. Fetch with: scripts/fetch-fonts.sh $(printf '"%s" ' "$@")"
    exit 0
fi

mkdir -p "$GDIR"
while IFS='|' read -r fam sty w url; do
    out="$GDIR/$(_stem "$fam")-$w$(_sfx "$sty").ttf"
    osmflat_log "fetching $fam $w$(_sfx "$sty") -> ${out##*/}"
    curl -fsSL -o "$out.part" "$url" || { rm -f "$out.part"; osmflat_die "download failed: $url"; }
    if ! _is_font "$out.part"; then
        rm -f "$out.part"
        osmflat_die "$url is not a TrueType/OpenType font; discarded"
    fi
    mv "$out.part" "$out"
done <<<"$rows"

echo
echo "fetched into $GDIR. Face-names to use in styles:"
_list
