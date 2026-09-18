#!/usr/bin/env bash
# List the mapnik face-names available to render.sh, so styles don't guess.
#
#   fonts.sh                 # face-names in the active font dir
#   fonts.sh --dir <path>    # ...in some other dir (what MAPNIK_FONT_DIR would expose)
#   fonts.sh --files         # also show which file each face comes from
#
# A face-name is family + style as freetype reports it, which is NOT the
# filename: DejaVuSans.ttf is "DejaVu Sans Book", and DejaVuSansCondensed.ttf
# is "DejaVu Sans Condensed" with no style suffix at all. A face-name mapnik
# cannot resolve renders NO TEXT and NO ERROR, so check here first.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/osmflat-env.sh"

SHOW_FILES=0
DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --files) SHOW_FILES=1; shift ;;
        --dir)   DIR="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$DIR" ]; then
    if [ -n "${MAPNIK_FONT_DIR:-}" ]; then
        DIR="$MAPNIK_FONT_DIR"
    else
        # Two steps: a failure inside a nested $(...) is not caught by set -e,
        # which would bury the "not installed" message under a second error.
        RENDER="$(osmflat_need render)"
        DIR="$(osmflat_font_dir "$RENDER")"
    fi
fi
[ -n "$DIR" ] && [ -d "$DIR" ] || osmflat_die "no font directory found (looked at: ${DIR:-none})"

command -v python3 >/dev/null 2>&1 || osmflat_die "fonts.sh needs python3 to read font name tables.
The bundled faces are listed in references/fonts.md."

echo "font dir: $DIR" >&2
python3 - "$DIR" "$SHOW_FILES" <<'PY'
# Minimal sfnt 'name' table reader -- stdlib only, no fontTools dependency.
import os, struct, sys

def records(data, base=0):
    """Yield (nameID, text) from the 'name' table of the font at offset `base`."""
    tag, num = struct.unpack_from(">4sH", data, base)[0], struct.unpack_from(">H", data, base + 4)[0]
    out = {}
    for i in range(num):
        t, _, off, _ln = struct.unpack_from(">4sIII", data, base + 12 + 16 * i)
        if t == b"name":
            fmt, count, str_off = struct.unpack_from(">HHH", data, off)
            for j in range(count):
                pid, eid, lid, nid, ln, o = struct.unpack_from(">HHHHHH", data, off + 6 + 12 * j)
                raw = data[off + str_off + o: off + str_off + o + ln]
                try:
                    s = raw.decode("utf-16-be") if pid == 3 else raw.decode("latin-1")
                except Exception:
                    continue
                # Rank candidates: Windows/English beats Windows/other-language
                # beats Mac. Without the language test a later non-English
                # record wins and yields a face-name mapnik cannot resolve
                # (e.g. "Arial Unicode MS Normal" instead of "... Regular").
                rank = 2 if (pid == 3 and lid == 0x409) else (1 if pid == 3 else 0)
                if nid not in out or rank > out[nid][0]:
                    out[nid] = (rank, s)
            break
    return {k: v[1] for k, v in out.items()}

def faces(path):
    with open(path, "rb") as fh:
        data = fh.read()
    bases = [0]
    if data[:4] == b"ttcf":                      # font collection
        n = struct.unpack_from(">I", data, 8)[0]
        bases = [struct.unpack_from(">I", data, 12 + 4 * i)[0] for i in range(n)]
    for b in bases:
        try:
            n = records(data, b)
        except Exception:
            continue
        # freetype prefers the typographic family/subfamily (16/17) when present:
        # that is why "Condensed" folds into the family instead of the style.
        fam = n.get(16) or n.get(1)
        sub = n.get(17) or n.get(2)
        if fam:
            yield " ".join(x for x in (fam.strip(), (sub or "").strip()) if x)

d, show_files = sys.argv[1], sys.argv[2] == "1"
rows = []
for fn in sorted(os.listdir(d)):
    if os.path.splitext(fn)[1].lower() not in (".ttf", ".otf", ".ttc"):
        continue
    for face in faces(os.path.join(d, fn)):
        rows.append((face, fn))
if not rows:
    print("no fonts found", file=sys.stderr); raise SystemExit(1)
w = max(len(r[0]) for r in rows)
for face, fn in sorted(set(rows)):
    print(f"{face:<{w}}  {fn}" if show_files else face)
PY
