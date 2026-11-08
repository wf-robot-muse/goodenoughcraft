#!/usr/bin/env python3
"""Build the GoodEnoughCraft icon from the block-letter logo artwork.

"GE" spelled in the title logo's 5x7 block font, each block filled with
an actual atlas texture (brick for G, planks for E), on a dark slate
background. Outputs icon.png (256x256, the project icon) and icon.ico
(multi-size, for the Windows executable).

Regenerate with: python3 tools/make_icon.py  (after make_atlas.py)
"""
from PIL import Image, ImageDraw

ATLAS = "assets/textures/atlas.png"
TILE = 32

GLYPHS = {
    "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
}
LETTER_TILES = {"G": (2, 1), "E": (7, 0)}  # brick, planks


def main():
    atlas = Image.open(ATLAS).convert("RGBA")
    size = 256
    img = Image.new("RGBA", (size, size), (38, 42, 50, 255))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([4, 4, size - 5, size - 5], radius=28,
                           outline=(90, 100, 112, 255), width=4)

    cell = 22
    gap = 20
    total_w = 5 * cell * 2 + gap
    x0 = (size - total_w) // 2
    y0 = (size - 7 * cell) // 2
    for li, letter in enumerate("GE"):
        tx, ty = LETTER_TILES[letter]
        tile = atlas.crop((tx * TILE, ty * TILE, tx * TILE + TILE, ty * TILE + TILE))
        tile = tile.resize((cell, cell), Image.NEAREST)
        glyph = GLYPHS[letter]
        lx = x0 + li * (5 * cell + gap)
        for row in range(7):
            for col in range(5):
                if glyph[row][col] == "#":
                    img.paste(tile, (lx + col * cell, y0 + row * cell))

    img.save("icon.png")
    img.save("icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                                (64, 64), (128, 128), (256, 256)])
    print("wrote icon.png and icon.ico")


if __name__ == "__main__":
    main()
