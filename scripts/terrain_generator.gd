extends VoxelGeneratorScript
## Terrain generator for GoodEnoughCraft: rolling hills with layered columns
## (grass / dirt / stone), sandy lowlands, and sparse trees.
##
## Voxel Tools' built-in heightmap generators write the SDF channel (they
## target the smooth terrain mesher), so a blocky world needs a generator
## that writes the TYPE channel — this one. Block ids come from the Blocks
## registry (scripts/blocks.gd). The static surface_height() lets gameplay
## code (player spawn) ask where the ground is without duplicating the
## noise setup.

const NOISE_SEED := 20261107
const AMPLITUDE := 14.0
const SAND_MAX_HEIGHT := 0
const TREE_DENSITY := 0.006

## The world seed in use. main.gd sets this from the active world's seed
## before the terrain is built; the default keeps the smoke test and any
## direct scene runs on the original Phase 1 world.
static var active_seed := NOISE_SEED

var _noise := FastNoiseLite.new()
static var _shared_noise: FastNoiseLite
static var _shared_seed := -1


func _init() -> void:
	_configure(_noise, active_seed)


static func _configure(noise: FastNoiseLite, seed_value: int) -> void:
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.012
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.5


static func _get_shared_noise() -> FastNoiseLite:
	if _shared_noise == null or _shared_seed != active_seed:
		_shared_noise = FastNoiseLite.new()
		_configure(_shared_noise, active_seed)
		_shared_seed = active_seed
	return _shared_noise


static func surface_height(x: int, z: int) -> int:
	var hill := _get_shared_noise().get_noise_2d(float(x), float(z))
	return int(round(hill * AMPLITUDE))


static func _hash01(x: int, z: int, salt: int) -> float:
	var h := (x * 374761393 + z * 668265263 + salt * 974711) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / float(0xffffff)


static func is_tree_column(x: int, z: int) -> bool:
	# No trees on sand, and keep the spawn area clear.
	if surface_height(x, z) <= SAND_MAX_HEIGHT:
		return false
	if absi(x) <= 2 and absi(z) <= 2:
		return false
	return _hash01(x, z, 7) < TREE_DENSITY


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var scale := 1 << lod
	var size := out_buffer.get_size()
	for local_x in size.x:
		for local_z in size.z:
			var world_x := (origin.x + local_x) * scale
			var world_z := (origin.z + local_z) * scale
			var surface := surface_height(world_x, world_z)
			for local_y in size.y:
				var world_y := (origin.y + local_y) * scale + scale / 2
				var type := 0
				if surface <= SAND_MAX_HEIGHT:
					# Sandy lowland: three blocks of sand over stone.
					if world_y <= surface - 3 * scale:
						type = Blocks.STONE
					elif world_y <= surface:
						type = Blocks.SAND
				else:
					if world_y <= surface - 3 * scale:
						type = Blocks.STONE
					elif world_y <= surface - 1:
						type = Blocks.DIRT
					elif world_y <= surface:
						type = Blocks.GRASS
				if type != 0:
					out_buffer.set_voxel(type, local_x, local_y, local_z, VoxelBuffer.CHANNEL_TYPE)
	if scale == 1:
		_stamp_trees(out_buffer, origin, size)


# Trees are stamped in a second pass because a tree's canopy can reach
# into neighboring columns (and neighboring blocks). Trunks sit in their
# own column; leaves fill the canopy volume where the buffer is still air.
func _stamp_trees(out_buffer: VoxelBuffer, origin: Vector3i, size: Vector3i) -> void:
	for cx in range(-2, size.x + 2):
		for cz in range(-2, size.z + 2):
			var world_x := origin.x + cx
			var world_z := origin.z + cz
			if not is_tree_column(world_x, world_z):
				continue
			var base := surface_height(world_x, world_z)
			# Trunk: 4 logs above the surface.
			for dy in range(1, 5):
				_set_world(out_buffer, origin, size, world_x, base + dy, world_z, Blocks.LOG, true)
			# Canopy layers at +3 and +4 (5x5, corners partly skipped), cap at +5.
			for dy in [3, 4]:
				for dx in range(-2, 3):
					for dz in range(-2, 3):
						if absi(dx) == 2 and absi(dz) == 2:
							if _hash01(world_x + dx, world_z + dz, dy) < 0.6:
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
