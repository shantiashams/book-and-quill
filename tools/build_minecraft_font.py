"""Build a local TTF from Minecraft's ascii.png bitmap font.

The source texture is supplied by the user's own Minecraft installation. This
script can also create an original fallback pixel font when --fallback is used.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from PIL import Image, ImageDraw, ImageFont


UNITS_PER_EM = 1024
PIXEL_UNIT = 128


def fallback_sheet() -> Image.Image:
    sheet = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    # Draw every fallback character into its own temporary cell. Pillow's
    # default font is taller than eight pixels on recent releases; drawing it
    # directly onto the atlas lets glyphs spill into neighbouring cells and
    # corrupts the character map (for example B can contain pieces of A).
    font = ImageFont.load_default(size=7)
    for codepoint in range(32, 127):
        cell = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
        draw = ImageDraw.Draw(cell)
        character = chr(codepoint)
        left, _, right, _ = draw.textbbox((0, 0), character, font=font)
        x = (8 - (right - left)) // 2 - left
        # Size-seven Pillow glyphs share a baseline at y=-1 and fit within the
        # cell, including descenders. The temporary image hard-clips anything
        # outside that cell as an additional safety guarantee.
        draw.text((x, -1), character, font=font, fill=(255, 255, 255, 255))
        x = (codepoint % 16) * 8
        y = (codepoint // 16) * 8
        sheet.alpha_composite(cell, (x, y))
    return sheet


def rectangle_glyph(pixel_rectangles: list[tuple[int, int, int, int]]):
    pen = TTGlyphPen(None)
    for left, bottom, right, top in pixel_rectangles:
        pen.moveTo((left, bottom))
        pen.lineTo((right, bottom))
        pen.lineTo((right, top))
        pen.lineTo((left, top))
        pen.closePath()
    return pen.glyph()


def glyph_from_cell(cell: Image.Image, monospaced: bool = False):
    rgba = cell.convert("RGBA")
    width, height = rgba.size
    visible: list[tuple[int, int]] = []
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = rgba.getpixel((x, y))
            if alpha >= 48 and max(red, green, blue) >= 32:
                visible.append((x, y))

    if not visible:
        advance = UNITS_PER_EM if monospaced else 4 * PIXEL_UNIT
        return rectangle_glyph([]), advance

    min_x = min(x for x, _ in visible)
    max_x = max(x for x, _ in visible)
    glyph_width = (max_x - min_x + 1) * PIXEL_UNIT
    left_padding = max(0, (UNITS_PER_EM - glyph_width) // 2) if monospaced else 0
    rectangles: list[tuple[int, int, int, int]] = []
    for x, y in visible:
        normalized_x = (x - min_x) * PIXEL_UNIT + left_padding
        bottom = (height - y - 1) * PIXEL_UNIT
        rectangles.append(
            (
                normalized_x,
                bottom,
                normalized_x + PIXEL_UNIT,
                bottom + PIXEL_UNIT,
            )
        )

    advance = UNITS_PER_EM if monospaced else (max_x - min_x + 2) * PIXEL_UNIT
    return rectangle_glyph(rectangles), advance


def build_font(
    sheet: Image.Image,
    output: Path,
    family_name: str,
    monospaced: bool = False,
) -> None:
    if sheet.width % 16 or sheet.height % 16:
        raise ValueError("Font texture dimensions must be divisible by 16")

    cell_width = sheet.width // 16
    cell_height = sheet.height // 16
    glyph_order = [".notdef"]
    glyphs = {".notdef": rectangle_glyph([])}
    default_advance = UNITS_PER_EM if monospaced else 4 * PIXEL_UNIT
    metrics = {".notdef": (default_advance, 0)}
    character_map: dict[int, str] = {}

    for codepoint in range(32, 127):
        glyph_name = f"uni{codepoint:04X}"
        left = (codepoint % 16) * cell_width
        top = (codepoint // 16) * cell_height
        cell = sheet.crop((left, top, left + cell_width, top + cell_height))
        glyph, advance = glyph_from_cell(cell, monospaced=monospaced)
        glyph_order.append(glyph_name)
        glyphs[glyph_name] = glyph
        metrics[glyph_name] = (advance, 0)
        character_map[codepoint] = glyph_name

    builder = FontBuilder(UNITS_PER_EM, isTTF=True)
    builder.setupGlyphOrder(glyph_order)
    builder.setupCharacterMap(character_map)
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics(metrics)
    builder.setupHorizontalHeader(ascent=UNITS_PER_EM, descent=-256)
    version = "3.0" if monospaced else "2.0"
    builder.setupNameTable(
        {
            "familyName": family_name,
            "styleName": "Regular",
            "uniqueFontIdentifier": f"BookAndQuill:{family_name}:{version}",
            "fullName": family_name,
            "psName": family_name.replace(" ", ""),
            "version": f"Version {version}",
        }
    )
    builder.setupOS2(
        sTypoAscender=UNITS_PER_EM,
        sTypoDescender=-256,
        usWinAscent=UNITS_PER_EM,
        usWinDescent=256,
        yStrikeoutPosition=4 * PIXEL_UNIT,
        yStrikeoutSize=PIXEL_UNIT,
    )
    # Explicit decoration metrics keep underline below the baseline and put
    # strikethrough through the glyph body. Without these values, Flutter can
    # render both decorations at almost the same vertical position.
    builder.setupPost(
        underlinePosition=-PIXEL_UNIT,
        underlineThickness=PIXEL_UNIT,
    )
    builder.setupMaxp()
    output.parent.mkdir(parents=True, exist_ok=True)
    builder.save(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--fallback", action="store_true")
    parser.add_argument(
        "--monospace",
        action="store_true",
        help="Give every glyph, including spaces, one identical cell advance.",
    )
    args = parser.parse_args()

    if args.fallback:
        sheet = fallback_sheet()
        family = (
            "Book and Quill Grid V3"
            if args.monospace
            else "Book and Quill Pixel V2"
        )
    else:
        if not args.source or not args.source.exists():
            raise FileNotFoundError("Minecraft ascii.png was not found")
        sheet = Image.open(args.source).convert("RGBA")
        family = "Minecraft Book Grid V3" if args.monospace else "Minecraft Local V2"

    build_font(sheet, args.output, family, monospaced=args.monospace)
    print(f"Generated font: {args.output}")


if __name__ == "__main__":
    main()
