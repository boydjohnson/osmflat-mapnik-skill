#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["pillow>=10"]
# ///
"""Draw a legend panel onto a rendered map PNG.

Swatch colors are read live from the style XML (by <Style> name and Rule index)
so the legend stays in sync when the palette changes; only the human labels are
curated, since those cannot be derived from a Filter expression.

Idempotent: the first run caches the legend-free render alongside the target as
"<name>.pristine.png", and every run redraws from that cache, so re-running
never stacks legends. Re-rendering the map overwrites the target with a fresh
legend-free image, which is detected and refreshes the cache automatically.

  uv run scripts/add-legend.py --xml style.xml --list
  uv run scripts/add-legend.py --xml style.xml --png out.png --spec legend.json

Pillow is declared inline (PEP 723), so `uv run` fetches it into a throwaway
environment -- nothing to install and nothing added to the system Python. The
shebang does the same, so ./add-legend.py works directly where uv is present.
Without uv, plain `python3 add-legend.py` still works if Pillow is installed.
"""
import argparse
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont, PngImagePlugin
except ImportError:
    sys.exit("add-legend.py needs Pillow.\n"
             "  uv run scripts/add-legend.py ...   (fetches it automatically)\n"
             "  or: pip install pillow")

LEGEND_MARKER_KEY = "osmflat-legend-attached"
LEGEND_MARKER_VALUE = "v1"

KINDS = ("fill", "line", "line-multi", "dot")


# --------------------------------------------------------------------- fonts

def find_font_dir(explicit=None):
    """DejaVu lives with the render release; mirror osmflat-env.sh's lookup."""
    for cand in (explicit, os.environ.get("MAPNIK_FONT_DIR")):
        if cand and Path(cand).is_dir():
            return Path(cand)
    home = os.environ.get("OSMFLAT_HOME") or os.path.join(
        os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "osmflat")
    hits = sorted(glob.glob(os.path.join(home, "pkg", "osmflat-render-*", "fonts")))
    if hits:
        return Path(hits[-1])
    return None


def load_fonts(font_dir, title_size, label_size):
    if font_dir:
        regular, bold = font_dir / "DejaVuSans.ttf", font_dir / "DejaVuSans-Bold.ttf"
        if regular.exists() and bold.exists():
            return (ImageFont.truetype(str(bold), title_size),
                    ImageFont.truetype(str(regular), label_size))
    print("warning: DejaVu not found; falling back to Pillow's default bitmap font.\n"
          "         Pass --font-dir, or set MAPNIK_FONT_DIR.", file=sys.stderr)
    return ImageFont.load_default(), ImageFont.load_default()


# ---------------------------------------------------------------- style XML

def get_rule(root, style_name, index):
    style = root.find(f"./Style[@name='{style_name}']")
    if style is None:
        raise SystemExit(f"no <Style name='{style_name}'> in the XML")
    rules = style.findall("Rule")
    if index >= len(rules):
        raise SystemExit(
            f"<Style name='{style_name}'> has {len(rules)} rule(s); no Rule[{index}]")
    return rules[index]


def swatch_from_rule(rule, kind):
    """Pull the colors a swatch of `kind` needs out of a Rule's symbolizers."""
    if kind == "fill":
        poly, line = rule.find("PolygonSymbolizer"), rule.find("LineSymbolizer")
        return {"fill": poly.get("fill") if poly is not None else "#cccccc",
                "stroke": line.get("stroke") if line is not None else "#888888"}
    if kind == "line":
        line = rule.find("LineSymbolizer")
        if line is None:
            raise SystemExit(f"kind 'line' needs a LineSymbolizer in the rule")
        return {"stroke": line.get("stroke", "#000000"),
                "width": float(line.get("stroke-width", 2))}
    if kind == "line-multi":
        lines = rule.findall("LineSymbolizer")
        if not lines:
            raise SystemExit("kind 'line-multi' needs LineSymbolizers in the rule")
        # widest = casing; narrowest non-white = the line's true color.
        widest = max(lines, key=lambda l: float(l.get("stroke-width", 0)))
        colored = min((l for l in lines if l.get("stroke", "#000").lower() != "#ffffff"),
                      key=lambda l: float(l.get("stroke-width", 0)), default=lines[-1])
        return {"casing": widest.get("stroke", "#ffffff"),
                "casing-width": float(widest.get("stroke-width", 5)),
                "stroke": colored.get("stroke", "#000000"),
                "width": float(colored.get("stroke-width", 2))}
    if kind == "dot":
        markers = rule.find("MarkersSymbolizer")
        if markers is None:
            raise SystemExit("kind 'dot' needs a MarkersSymbolizer in the rule")
        return {"fill": markers.get("fill", "#666666"),
                "stroke": markers.get("stroke", "#ffffff")}
    raise SystemExit(f"unknown swatch kind {kind!r}; expected one of {', '.join(KINDS)}")


def list_styles(xml_path):
    """Print the <Style>/Rule structure, so a spec can be written from fact."""
    root = ET.parse(xml_path).getroot()
    print(f"{xml_path}  background-color={root.get('background-color', '(none)')}\n")
    for style in root.findall("./Style"):
        print(f'Style "{style.get("name")}"')
        for i, rule in enumerate(style.findall("Rule")):
            filt = rule.find("Filter")
            bits = []
            for sym in rule:
                tag = sym.tag.replace("Symbolizer", "")
                attrs = {k: v for k, v in sym.attrib.items()
                         if k in ("fill", "stroke", "stroke-width")}
                if attrs:
                    bits.append(f"{tag}({', '.join(f'{k}={v}' for k, v in attrs.items())})")
            hint = ""
            if rule.find("PolygonSymbolizer") is not None:
                hint = "fill"
            elif len(rule.findall("LineSymbolizer")) > 1:
                hint = "line-multi"
            elif rule.find("LineSymbolizer") is not None:
                hint = "line"
            elif rule.find("MarkersSymbolizer") is not None:
                hint = "dot"
            print(f"  Rule[{i}]" + (f"  kind={hint}" if hint else ""))
            if filt is not None and filt.text:
                print(f"    filter: {' '.join(filt.text.split())[:96]}")
            for b in bits:
                print(f"    {b}")
        print()


# ------------------------------------------------------------------ drawing

def hex_to_rgba(h, alpha=255):
    h = (h or "#cccccc").lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alpha)


def draw_swatch(draw, kind, colors, x0, y0, x1, ymid):
    if kind == "fill":
        draw.rectangle([x0, y0, x1, y0 + (ymid - y0) * 2],
                       fill=hex_to_rgba(colors["fill"]),
                       outline=hex_to_rgba(colors["stroke"]), width=1)
    elif kind == "line":
        draw.line([(x0, ymid), (x1, ymid)], fill=hex_to_rgba(colors["stroke"]),
                  width=max(2, round(colors["width"] * 1.6)))
    elif kind == "line-multi":
        draw.line([(x0, ymid), (x1, ymid)], fill=hex_to_rgba(colors["casing"]),
                  width=max(3, round(colors["casing-width"] * 1.1)))
        draw.line([(x0, ymid), (x1, ymid)], fill=hex_to_rgba(colors["stroke"]),
                  width=max(2, round(colors["width"] * 1.3)))
    elif kind == "dot":
        r = 5
        cx = (x0 + x1) // 2
        draw.ellipse([cx - r, ymid - r, cx + r, ymid + r],
                     fill=hex_to_rgba(colors["fill"]),
                     outline=hex_to_rgba(colors["stroke"]), width=1)


def render_legend(base_img, items, bg_hex, title, position, fonts):
    title_font, label_font = fonts
    overlay = Image.new("RGBA", base_img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    swatch_w, row_h, pad, gap = 26, 20, 12, 8
    title_h = 22 if title else 0

    label_w = max(draw.textlength(label, font=label_font) for _, label, _ in items)
    content_w = swatch_w + gap + label_w
    if title:
        # The title is bold and a size up, so it outruns the rows more often
        # than not; without this it spills over the map beyond the panel edge.
        content_w = max(content_w, draw.textlength(title, font=title_font))
    panel_w = round(pad * 2 + content_w)
    panel_h = round(pad * 2 + title_h + row_h * len(items))

    margin = 16
    east = "e" in position
    south = "s" in position
    px0 = base_img.width - margin - panel_w if east else margin
    py0 = base_img.height - margin - panel_h if south else margin

    draw.rounded_rectangle([px0, py0, px0 + panel_w, py0 + panel_h], radius=8,
                           fill=hex_to_rgba(bg_hex, alpha=235),
                           outline=(90, 84, 70, 255), width=1)
    if title:
        draw.text((px0 + pad, py0 + pad - 2), title, font=title_font, fill=(40, 38, 30, 255))

    y = py0 + pad + title_h
    for kind, label, colors in items:
        x0, x1 = px0 + pad, px0 + pad + swatch_w
        ymid = y + row_h // 2
        draw_swatch(draw, kind, colors, x0, y + 3, x1, ymid)
        draw.text((x1 + gap, ymid - 6), label, font=label_font, fill=(40, 38, 30, 255))
        y += row_h

    return Image.alpha_composite(base_img.convert("RGBA"), overlay)


# ------------------------------------------------------------- idempotency

def has_legend_marker(png_path):
    with Image.open(png_path) as im:
        return im.info.get(LEGEND_MARKER_KEY) == LEGEND_MARKER_VALUE


def save_with_marker(img, path):
    meta = PngImagePlugin.PngInfo()
    meta.add_text(LEGEND_MARKER_KEY, LEGEND_MARKER_VALUE)
    img.save(path, pnginfo=meta)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--xml", required=True, type=Path, help="the Mapnik style the map was rendered from")
    ap.add_argument("--png", type=Path, help="the rendered PNG to draw onto (modified in place)")
    ap.add_argument("--spec", type=Path, help="JSON legend spec; see --list")
    ap.add_argument("--list", action="store_true", help="print the style's Styles/Rules and exit")
    ap.add_argument("--title", default=None, help="panel title (default: from spec, else 'Legend')")
    ap.add_argument("--position", default=None, choices=["sw", "se", "nw", "ne"],
                    help="panel corner (default: from spec, else sw)")
    ap.add_argument("--font-dir", default=None, help="directory holding DejaVuSans.ttf")
    args = ap.parse_args()

    if not args.xml.exists():
        sys.exit(f"no such style: {args.xml}")
    if args.list:
        list_styles(args.xml)
        return
    if not args.png or not args.spec:
        sys.exit("--png and --spec are required (or use --list to inspect the style)")
    if not args.png.exists():
        sys.exit(f"no such PNG: {args.png} -- render the map first")

    spec = json.loads(args.spec.read_text())
    entries = spec.get("entries", spec if isinstance(spec, list) else [])
    if not entries:
        sys.exit(f"{args.spec} has no entries")
    title = args.title if args.title is not None else spec.get("title", "Legend") if isinstance(spec, dict) else "Legend"
    position = args.position or (spec.get("position", "sw") if isinstance(spec, dict) else "sw")

    root = ET.parse(args.xml).getroot()
    items = []
    for e in entries:
        rule = get_rule(root, e["style"], int(e.get("rule", 0)))
        items.append((e["kind"], e["label"], swatch_from_rule(rule, e["kind"])))

    pristine = args.png.with_suffix("").with_suffix(".pristine.png")
    if has_legend_marker(args.png):
        if not pristine.exists():
            print(f"warning: {args.png} already carries a legend but {pristine} is gone; "
                  f"using it as-is, so the result may stack legends.", file=sys.stderr)
            pristine = args.png
    else:
        # Legend-free: first run, or the map was just re-rendered. Refresh cache.
        with Image.open(args.png) as im:
            im.convert("RGBA").save(pristine)

    bg = spec.get("background", root.get("background-color", "#f6f1e7")) if isinstance(spec, dict) \
        else root.get("background-color", "#f6f1e7")
    fonts = load_fonts(find_font_dir(args.font_dir), 14, 11)
    with Image.open(pristine) as base:
        result = render_legend(base, items, bg, title, position, fonts)
    save_with_marker(result, args.png)
    print(f"legend attached to {args.png} (base cached at {pristine})")


if __name__ == "__main__":
    main()
