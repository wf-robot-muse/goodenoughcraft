#!/usr/bin/env python3
"""Generate the GoodEnoughCraft texture atlas procedurally.

Deterministic (fixed seeds per tile), no external assets. Output:
assets/textures/atlas.png — 8x4 tiles of 32x32 px (256x128).

Tile positions (x, y) must match scripts/blocks.gd TILES.
Regenerate with: python3 tools/make_atlas.py
"""
import random
from PIL import Image, ImageDraw

TILE = 32
COLS, ROWS = 8, 4


def vary(base, rng, amt=14):
    return tuple(max(0, min(255, c + rng.randint(-amt, amt))) for c in base)


def fill_noise(img, xy, base, rng, amt=14):
    px = img.load()
    x0, y0 = xy
    for y in range(TILE):
        for x in range(TILE):
            px[x0 + x, y0 + y] = vary(base, rng, amt) + (255,)


def speckle(img, xy, colors, count, rng, size=1):
    px = img.load()
    x0, y0 = xy
    for _ in range(count):
        x = rng.randrange(TILE - size + 1)
        y = rng.randrange(TILE - size + 1)
        c = rng.choice(colors) + (255,)
        for dy in range(size):
            for dx in range(size):
                px[x0 + x + dx, y0 + y + dy] = c


def tile_origin(name, tiles):
    return (tiles[name][0] * TILE, tiles[name][1] * TILE)


TILES = {
    "grass_top": (0, 0), "grass_side": (1, 0), "dirt": (2, 0),
    "stone": (3, 0), "cobblestone": (4, 0), "log_side": (5, 0),
    "log_top": (6, 0), "planks": (7, 0),
    "leaves": (0, 1), "sand": (1, 1), "brick": (2, 1),
    "glass": (3, 1), "snow_top": (4, 1), "snow_side": (5, 1),
    "coal_ore": (6, 1), "iron_ore": (7, 1),
    "gold_ore": (0, 2), "cactus_side": (1, 2), "cactus_top": (2, 2),
    "water": (3, 2),
}

GRASS = (86, 158, 62)
GRASS_DARK = (64, 128, 46)
GRASS_LIGHT = (110, 182, 82)
DIRT = (122, 88, 56)
DIRT_DARK = (96, 66, 40)
STONE = (136, 136, 140)
STONE_DARK = (108, 108, 112)
SAND = (216, 188, 122)


def main():
    img = Image.new("RGBA", (COLS * TILE, ROWS * TILE), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)

    def rng_for(name):
        return random.Random("gec-" + name)

    # grass_top
    xy = tile_origin("grass_top", TILES)
    r = rng_for("grass_top")
    fill_noise(img, xy, GRASS, r, 12)
    speckle(img, xy, [GRASS_DARK, GRASS_LIGHT], 130, r)

    # dirt
    xy = tile_origin("dirt", TILES)
    r = rng_for("dirt")
    fill_noise(img, xy, DIRT, r, 12)
    speckle(img, xy, [DIRT_DARK, (150, 116, 78)], 60, r)
    speckle(img, xy, [(170, 170, 170)], 8, r)

    # grass_side: dirt with a grass strip hanging from the top
    xy = tile_origin("grass_side", TILES)
    r = rng_for("grass_side")
    fill_noise(img, xy, DIRT, r, 12)
    speckle(img, xy, [DIRT_DARK], 40, r)
    px = img.load()
    for x in range(TILE):
        depth = 7 + r.randint(0, 4)
        for y in range(depth):
            px[xy[0] + x, xy[1] + y] = vary(GRASS, r, 12) + (255,)

    # stone
    xy = tile_origin("stone", TILES)
    r = rng_for("stone")
    fill_noise(img, xy, STONE, r, 9)
    speckle(img, xy, [STONE_DARK], 46, r)

    # cobblestone: rounded cells with dark mortar
    xy = tile_origin("cobblestone", TILES)
    r = rng_for("cobblestone")
    fill_noise(img, xy, (74, 74, 78), r, 6)
    for cy in range(4):
        for cx in range(4):
            ox, oy = xy[0] + cx * 8, xy[1] + cy * 8
            tone = 132 + r.randint(-14, 26)
            draw.rounded_rectangle([ox, oy, ox + 7, oy + 7], radius=3,
                                   fill=(tone, tone, tone + 4, 255))
            draw.rounded_rectangle([ox + 2, oy + 1, ox + 5, oy + 3], radius=1,
                                   fill=(tone + 18, tone + 18, tone + 20, 255))
    speckle(img, xy, [STONE_DARK], 30, r)

    # log_side: vertical bark stripes
    xy = tile_origin("log_side", TILES)
    r = rng_for("log_side")
    px = img.load()
    stripe_tones = [(104, 78, 46), (90, 66, 38), (118, 92, 56), (84, 60, 34)]
    for x in range(TILE):
        tone = stripe_tones[(x // 3) % len(stripe_tones)]
        for y in range(TILE):
            px[xy[0] + x, xy[1] + y] = vary(tone, r, 8) + (255,)
    speckle(img, xy, [(70, 50, 26)], 30, r)

    # log_top: growth rings
    xy = tile_origin("log_top", TILES)
    r = rng_for("log_top")
    px = img.load()
    for y in range(TILE):
        for x in range(TILE):
            d = max(abs(x - 15.5), abs(y - 15.5))
            if d > 13:
                c = (96, 70, 40)
            elif int(d) % 4 < 2:
                c = (176, 138, 90)
            else:
                c = (150, 112, 66)
            px[xy[0] + x, xy[1] + y] = vary(c, r, 7) + (255,)

    # planks: horizontal boards
    xy = tile_origin("planks", TILES)
    r = rng_for("planks")
    fill_noise(img, xy, (168, 128, 76), r, 10)
    px = img.load()
    for y in (7, 15, 23, 31):
        for x in range(TILE):
            px[xy[0] + x, xy[1] + y] = (120, 88, 48, 255)
    for i, vx in enumerate((10, 26, 18, 4)):
        for y in range(i * 8, i * 8 + 7):
            px[xy[0] + vx, xy[1] + y] = (120, 88, 48, 255)
    speckle(img, xy, [(140, 104, 58)], 40, r)

    # leaves: dense dark green with holes of darker shade
    xy = tile_origin("leaves", TILES)
    r = rng_for("leaves")
    fill_noise(img, xy, (52, 104, 40), r, 16)
    speckle(img, xy, [(30, 66, 24), (24, 52, 18)], 120, r)
    speckle(img, xy, [(76, 132, 56)], 60, r)

    # sand
    xy = tile_origin("sand", TILES)
    r = rng_for("sand")
    fill_noise(img, xy, SAND, r, 8)
    speckle(img, xy, [(196, 166, 100), (232, 206, 148)], 70, r)

    # brick: offset rows with mortar. Drawn on its own tile image and
    # pasted in, so wrap-around bricks cannot bleed into neighbours.
    xy = tile_origin("brick", TILES)
    r = rng_for("brick")
    btile = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 255))
    fill_noise(btile, (0, 0), (168, 160, 152), r, 6)
    bdraw = ImageDraw.Draw(btile)
    for row in range(4):
        y0 = row * 8
        offset = 8 if row % 2 else 0
        for bx in range(-1, 3):
            bx0 = bx * 16 + offset
            for wrap in (-TILE, 0, TILE):
                bdraw.rectangle([bx0 + 1 + wrap, y0 + 1, bx0 + 14 + wrap, y0 + 6],
                                fill=vary((150, 74, 56), r, 10) + (255,))
    img.paste(btile, xy)

    # glass: pale translucent-look tile (rendered opaque) with a frame
    xy = tile_origin("glass", TILES)
    r = rng_for("glass")
    fill_noise(img, xy, (206, 232, 238), r, 4)
    draw.rectangle([xy[0], xy[1], xy[0] + TILE - 1, xy[1] + TILE - 1],
                   outline=(150, 190, 200, 255), width=2)
    for i in range(9):
        img.putpixel((xy[0] + 5 + i, xy[1] + 20 - i), (255, 255, 255, 255))
        img.putpixel((xy[0] + 6 + i, xy[1] + 20 - i), (255, 255, 255, 255))

    # snow_top
    xy = tile_origin("snow_top", TILES)
    r = rng_for("snow_top")
    fill_noise(img, xy, (238, 242, 246), r, 5)
    speckle(img, xy, [(214, 224, 234)], 30, r)

    # snow_side: dirt with a thick snow cap
    xy = tile_origin("snow_side", TILES)
    r = rng_for("snow_side")
    fill_noise(img, xy, DIRT, r, 12)
    px = img.load()
    for x in range(TILE):
        depth = 10 + r.randint(0, 3)
        for y in range(depth):
            px[xy[0] + x, xy[1] + y] = vary((238, 242, 246), r, 5) + (255,)

    # ores: stone base with mineral blobs
    def ore(name, blob_colors):
        xy = tile_origin(name, TILES)
        r = rng_for(name)
        fill_noise(img, xy, STONE, r, 9)
        speckle(img, xy, [STONE_DARK], 30, r)
        for _ in range(5):
            cx, cy = r.randrange(3, 27), r.randrange(3, 27)
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1), (2, 1), (1, 2)):
                img.putpixel((xy[0] + cx + dx, xy[1] + cy + dy),
                             vary(r.choice(blob_colors), r, 8) + (255,))
    ore("coal_ore", [(32, 32, 34), (44, 44, 48)])
    ore("iron_ore", [(216, 175, 147), (196, 152, 120)])
    ore("gold_ore", [(250, 214, 64), (238, 192, 44)])

    # cactus_side: green column shading with spine dots
    xy = tile_origin("cactus_side", TILES)
    r = rng_for("cactus_side")
    px = img.load()
    for x in range(TILE):
        tone = (58, 128, 54) if x % 8 < 6 else (44, 104, 42)
        for y in range(TILE):
            px[xy[0] + x, xy[1] + y] = vary(tone, r, 8) + (255,)
    speckle(img, xy, [(226, 232, 190)], 26, r)

    # cactus_top
    xy = tile_origin("cactus_top", TILES)
    r = rng_for("cactus_top")
    fill_noise(img, xy, (58, 128, 54), r, 9)
    speckle(img, xy, [(226, 232, 190)], 12, r)

    # water: layered blue waves (rendered opaque)
    xy = tile_origin("water", TILES)
    r = rng_for("water")
    px = img.load()
    for y in range(TILE):
        for x in range(TILE):
            wave = 10 if (x + y * 2) % 16 < 2 else 0
            px[xy[0] + x, xy[1] + y] = vary((52, 110, 200), r, 7) + (255,)
            if wave:
                px[xy[0] + x, xy[1] + y] = (84, 140, 220, 255)

    out = "assets/textures/atlas.png"
    img.save(out)
    print("wrote", out, img.size)


if __name__ == "__main__":
    main()
