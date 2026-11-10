class_name Blocks
extends RefCounted
## Block registry: the single source of truth for voxel type ids, names,
## colors, and texture tiles. The terrain generator, the block library,
## the HUD, and the title logo all read from here.
##
## Id 0 is always air (the empty model). Models are textured cubes whose
## faces sample assets/textures/atlas.png (generated procedurally by
## tools/make_atlas.py). Tile coordinates below are in tiles, matching
## that script's TILES map; the atlas is 8x4 tiles of 32x32.
##
## Flat colors are kept for the HUD hotbar swatches and UI accents.

const AIR := 0
const GRASS := 1
const STONE := 2
const DIRT := 3
const COBBLE := 4
const LOG := 5
const PLANKS := 6
const LEAVES := 7
const SAND := 8
const BRICK := 9
const WATER := 10
const COAL_ORE := 11
const IRON_ORE := 12
const GOLD_ORE := 13
const SNOW_GRASS := 14
const GLASS := 15
const CACTUS := 16

const ATLAS_PATH := "res://assets/textures/atlas.png"
const ATLAS_SIZE := Vector2i(8, 4)

# Tile coordinates (in tiles) inside the atlas.
const T_GRASS_TOP := Vector2i(0, 0)
const T_GRASS_SIDE := Vector2i(1, 0)
const T_DIRT := Vector2i(2, 0)
const T_STONE := Vector2i(3, 0)
const T_COBBLE := Vector2i(4, 0)
const T_LOG_SIDE := Vector2i(5, 0)
const T_LOG_TOP := Vector2i(6, 0)
const T_PLANKS := Vector2i(7, 0)
const T_LEAVES := Vector2i(0, 1)
const T_SAND := Vector2i(1, 1)
const T_BRICK := Vector2i(2, 1)
const T_GLASS := Vector2i(3, 1)
const T_SNOW_TOP := Vector2i(4, 1)
const T_SNOW_SIDE := Vector2i(5, 1)
const T_COAL_ORE := Vector2i(6, 1)
const T_IRON_ORE := Vector2i(7, 1)
const T_GOLD_ORE := Vector2i(0, 2)
const T_CACTUS_SIDE := Vector2i(1, 2)
const T_CACTUS_TOP := Vector2i(2, 2)
const T_WATER := Vector2i(3, 2)

# id -> [name, hud color]
const DEFS := {
	GRASS: ["Grass", Color(0.30, 0.60, 0.25)],
	STONE: ["Stone", Color(0.55, 0.55, 0.58)],
	DIRT: ["Dirt", Color(0.45, 0.32, 0.20)],
	COBBLE: ["Cobblestone", Color(0.36, 0.36, 0.38)],
	LOG: ["Log", Color(0.38, 0.27, 0.14)],
	PLANKS: ["Planks", Color(0.65, 0.49, 0.29)],
	LEAVES: ["Leaves", Color(0.20, 0.44, 0.17)],
	SAND: ["Sand", Color(0.82, 0.71, 0.46)],
	BRICK: ["Brick", Color(0.58, 0.27, 0.21)],
	WATER: ["Water", Color(0.20, 0.43, 0.78)],
	COAL_ORE: ["Coal Ore", Color(0.30, 0.30, 0.32)],
	IRON_ORE: ["Iron Ore", Color(0.72, 0.58, 0.46)],
	GOLD_ORE: ["Gold Ore", Color(0.85, 0.68, 0.25)],
	SNOW_GRASS: ["Snowy Grass", Color(0.90, 0.93, 0.95)],
	GLASS: ["Glass", Color(0.81, 0.91, 0.93)],
	CACTUS: ["Cactus", Color(0.23, 0.50, 0.21)],
}

# id -> [side tile, top tile, bottom tile]
const TILES := {
	GRASS: [T_GRASS_SIDE, T_GRASS_TOP, T_DIRT],
	STONE: [T_STONE, T_STONE, T_STONE],
	DIRT: [T_DIRT, T_DIRT, T_DIRT],
	COBBLE: [T_COBBLE, T_COBBLE, T_COBBLE],
	LOG: [T_LOG_SIDE, T_LOG_TOP, T_LOG_TOP],
	PLANKS: [T_PLANKS, T_PLANKS, T_PLANKS],
	LEAVES: [T_LEAVES, T_LEAVES, T_LEAVES],
	SAND: [T_SAND, T_SAND, T_SAND],
	BRICK: [T_BRICK, T_BRICK, T_BRICK],
	WATER: [T_WATER, T_WATER, T_WATER],
	COAL_ORE: [T_COAL_ORE, T_COAL_ORE, T_COAL_ORE],
	IRON_ORE: [T_IRON_ORE, T_IRON_ORE, T_IRON_ORE],
	GOLD_ORE: [T_GOLD_ORE, T_GOLD_ORE, T_GOLD_ORE],
	SNOW_GRASS: [T_SNOW_SIDE, T_SNOW_TOP, T_DIRT],
	GLASS: [T_GLASS, T_GLASS, T_GLASS],
	CACTUS: [T_CACTUS_SIDE, T_CACTUS_TOP, T_CACTUS_TOP],
}

# Hotbar slots in display order (hotbar_1 .. hotbar_10 actions).
const HOTBAR: Array[int] = [GRASS, DIRT, STONE, COBBLE, LOG, PLANKS, LEAVES, SAND, BRICK, GLASS]

## Bare-hand breaking times in seconds, using Minecraft's block values
## (Fire build issue #10). Minecraft derives hand-breaking time from
## hardness: hardness x 1.5 when the hand can harvest the block, or
## hardness x 5 when a pickaxe is the proper tool. Water has no entry
## because it cannot be mined.
const BREAK_SECONDS := {
	GRASS: 0.9,
	STONE: 7.5,
	DIRT: 0.75,
	COBBLE: 10.0,
	LOG: 3.0,
	PLANKS: 3.0,
	LEAVES: 0.3,
	SAND: 0.75,
	BRICK: 10.0,
	COAL_ORE: 15.0,
	IRON_ORE: 15.0,
	GOLD_ORE: 15.0,
	SNOW_GRASS: 0.9,
	GLASS: 0.45,
	CACTUS: 0.6,
}

static var _material: StandardMaterial3D


static func break_seconds(id: int) -> float:
	return float(BREAK_SECONDS.get(id, 1.0))


## Sound/feel family per block (Fire build issue #15): Minecraft gives
## each material its own hit, break, and place sounds. Ids map to the
## family names used by the generated SFX files (hit_<family>.wav ...).
const MATERIAL_FAMILIES := {
	GRASS: "earth",
	SNOW_GRASS: "earth",
	DIRT: "earth",
	SAND: "sand",
	STONE: "stone",
	COBBLE: "stone",
	BRICK: "stone",
	COAL_ORE: "stone",
	IRON_ORE: "stone",
	GOLD_ORE: "stone",
	LOG: "wood",
	PLANKS: "wood",
	LEAVES: "plant",
	CACTUS: "plant",
	GLASS: "glass",
}


static func material_family(id: int) -> String:
	return str(MATERIAL_FAMILIES.get(id, "earth"))


static func block_name(id: int) -> String:
	if DEFS.has(id):
		return DEFS[id][0]
	return "Air"


static func block_color(id: int) -> Color:
	if DEFS.has(id):
		return DEFS[id][1]
	return Color(0, 0, 0, 0)


static func is_water(id: int) -> bool:
	return id == WATER


## The shared terrain material: the atlas as albedo with nearest-neighbor
## filtering for a crisp pixel look. One instance is reused everywhere.
static func terrain_material() -> Material:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_texture = load(ATLAS_PATH) as Texture2D
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_material.roughness = 1.0
	return _material


static func build_library() -> VoxelBlockyLibrary:
	var library := VoxelBlockyLibrary.new()
	library.add_model(VoxelBlockyModelEmpty.new())
	# Models must be added in id order so the model index equals the id.
	var ids := DEFS.keys()
	ids.sort()
	for id in ids:
		var model := VoxelBlockyModelCube.new()
		model.atlas_size_in_tiles = ATLAS_SIZE
		var tiles: Array = TILES[id]
		model.tile_left = tiles[0]
		model.tile_right = tiles[0]
		model.tile_back = tiles[0]
		model.tile_front = tiles[0]
		model.tile_top = tiles[1]
		model.tile_bottom = tiles[2]
		if id == WATER:
			# Water is not solid: the player swims through it.
			model.collision_aabbs = []
		library.add_model(model)
	library.bake()
	return library
