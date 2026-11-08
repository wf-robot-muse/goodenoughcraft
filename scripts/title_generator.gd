extends VoxelGeneratorScript
## Title-screen backdrop generator: a floating grass island with the
## "GoodEnoughCraft" logo spelled out in game blocks, floating above it.
## Letters use a 5x7 pixel font; each letter is built from a different
## block type from the Blocks registry, so the logo is literally made of
## the game's blocks. Pure generation (no saved edits), like the world
## generator.

const LOGO_Z := -14
const LINE1 := "GOODENOUGH"
const LINE2 := "CRAFT"
const LINE1_TOP := 18
const LINE2_TOP := 10
const LETTER_PITCH := 6
const LETTER_PALETTE: Array[int] = [
	Blocks.BRICK, Blocks.PLANKS, Blocks.STONE, Blocks.COBBLE, Blocks.LOG,
	Blocks.GRASS, Blocks.SAND, Blocks.DIRT, Blocks.LEAVES, Blocks.BRICK,
	Blocks.PLANKS, Blocks.STONE, Blocks.COBBLE, Blocks.LOG, Blocks.GRASS,
]

const GLYPHS := {
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"N": ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
}


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var scale := 1 << lod
	var size := out_buffer.get_size()
	for local_x in size.x:
		for local_z in size.z:
			var world_x := (origin.x + local_x) * scale
			var world_z := (origin.z + local_z) * scale
			var on_island := _is_island(world_x, world_z)
			for local_y in size.y:
				var world_y := (origin.y + local_y) * scale + scale / 2
				var type := 0
				if on_island:
					if world_y <= 0:
						type = Blocks.STONE
					elif world_y == 1:
						type = Blocks.DIRT
					elif world_y == 2:
						type = Blocks.GRASS
				if scale == 1 and world_z == LOGO_Z:
					var letter := _letter_at(world_x, world_y)
					if letter != 0:
						type = letter
				if type != 0:
					out_buffer.set_voxel(type, local_x, local_y, local_z, VoxelBuffer.CHANNEL_TYPE)
	if scale == 1:
		_stamp_tree(out_buffer, origin, size, -32, -4)
		_stamp_tree(out_buffer, origin, size, 30, -24)
		_stamp_tree(out_buffer, origin, size, 34, 0)


func _is_island(x: int, z: int) -> bool:
	var dx := float(x) / 44.0
	var dz := float(z + 14) / 24.0
	return dx * dx + dz * dz <= 1.0


func _letter_at(x: int, y: int) -> int:
	var line := ""
	var top := 0
	var start_x := 0
	if y <= LINE1_TOP and y > LINE1_TOP - 7:
		line = LINE1
		top = LINE1_TOP
		start_x = -29
	elif y <= LINE2_TOP and y > LINE2_TOP - 7:
		line = LINE2
		top = LINE2_TOP
		start_x = -14
	else:
		return 0
	var rel_x := x - start_x
	if rel_x < 0 or rel_x >= line.length() * LETTER_PITCH:
		return 0
	var char_index := rel_x / LETTER_PITCH
	var col := rel_x % LETTER_PITCH
	if col >= 5:
		return 0 # spacing column
	var row := top - y
	var glyph: Array = GLYPHS[line[char_index]]
	if glyph[row][col] == "#":
		var palette_index := char_index
		if line == LINE2:
			palette_index += LINE1.length()
		return LETTER_PALETTE[palette_index % LETTER_PALETTE.size()]
	return 0


func _stamp_tree(out_buffer: VoxelBuffer, origin: Vector3i, size: Vector3i, world_x: int, world_z: int) -> void:
	if not _is_island(world_x, world_z):
		return
	var base := 2
	for dy in range(1, 5):
		_set_world(out_buffer, origin, size, world_x, base + dy, world_z, Blocks.LOG, true)
	for dy in [3, 4]:
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				if absi(dx) == 2 and absi(dz) == 2:
					continue
				_set_world(out_buffer, origin, size, world_x + dx, base + dy, world_z + dz, Blocks.LEAVES, false)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if absi(dx) + absi(dz) <= 1:
				_set_world(out_buffer, origin, size, world_x + dx, base + 5, world_z + dz, Blocks.LEAVES, false)


func _set_world(out_buffer: VoxelBuffer, origin: Vector3i, size: Vector3i, x: int, y: int, z: int, type: int, overwrite: bool) -> void:
	var local := Vector3i(x - origin.x, y - origin.y, z - origin.z)
	if local.x < 0 or local.y < 0 or local.z < 0:
		return
	if local.x >= size.x or local.y >= size.y or local.z >= size.z:
		return
	if not overwrite and out_buffer.get_voxel(local.x, local.y, local.z, VoxelBuffer.CHANNEL_TYPE) != 0:
		return
	out_buffer.set_voxel(type, local.x, local.y, local.z, VoxelBuffer.CHANNEL_TYPE)
