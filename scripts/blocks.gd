class_name Blocks
extends RefCounted
## Block registry: the single source of truth for voxel type ids, names,
## and colors. The terrain generator, the block library, and the hotbar all
## read from here, so adding a block type is a one-line change.
##
## Id 0 is always air (the empty model). Models are plain colored cubes for
## now; a texture atlas replaces the flat colors in a later phase.

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

# id -> [name, color]
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
}

# Hotbar slots in display order (number keys 1-9).
const HOTBAR: Array[int] = [GRASS, DIRT, STONE, COBBLE, LOG, PLANKS, LEAVES, SAND, BRICK]


static func block_name(id: int) -> String:
	if DEFS.has(id):
		return DEFS[id][0]
	return "Air"


static func block_color(id: int) -> Color:
	if DEFS.has(id):
		return DEFS[id][1]
	return Color(0, 0, 0, 0)


static func build_library() -> VoxelBlockyLibrary:
	var library := VoxelBlockyLibrary.new()
	library.add_model(VoxelBlockyModelEmpty.new())
	# Models must be added in id order so the model index equals the id.
	var ids := DEFS.keys()
	ids.sort()
	for id in ids:
		var model := VoxelBlockyModelCube.new()
		model.color = DEFS[id][1]
		library.add_model(model)
	library.bake()
	return library
