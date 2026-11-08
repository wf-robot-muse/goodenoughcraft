extends VoxelGeneratorScript
## Terrain generator for GoodEnoughCraft (Phase 2): rolling hills with
## three biomes (plains, desert, snow) chosen by a low-frequency
## temperature noise, beaches and simple water filling lowlands up to
## SEA_LEVEL, 3D-noise caves carved underground, and hash-scattered ore
## blocks (coal, iron, gold) inside the stone layer. Trees grow in plains
## (sparser in snow); cacti grow in the desert.
##
## Voxel Tools' built-in heightmap generators write the SDF channel (they
## target the smooth terrain mesher), so a blocky world needs a generator
## that writes the TYPE channel — this one. Block ids come from the Blocks
## registry (scripts/blocks.gd). The static helpers let gameplay code ask
## where the ground is and which biome a column belongs to.

const NOISE_SEED := 20261107
const AMPLITUDE := 14.0
const SAND_MAX_HEIGHT := 0
const TREE_DENSITY := 0.006
const CACTUS_DENSITY := 0.005
const SEA_LEVEL := 1
const CAVE_THRESHOLD := 0.45

const BIOME_PLAINS := 0
const BIOME_DESERT := 1
const BIOME_SNOW := 2

## The world seed in use. main.gd sets this from the active world's seed
## before the terrain is built; the default keeps the smoke test and any
## direct scene runs on the original Phase 1 world.
static var active_seed := NOISE_SEED

var _noise := FastNoiseLite.new()
var _cave_noise := FastNoiseLite.new()
static var _shared_noise: FastNoiseLite
static var _shared_temp: FastNoiseLite
static var _shared_seed := -1


func _init() -> void:
	_configure(_noise, active_seed)
	_cave_noise.seed = active_seed + 31337
	_cave_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_cave_noise.frequency = 0.045
	_cave_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_cave_noise.fractal_octaves = 2


static func _configure(noise: FastNoiseLite, seed_value: int) -> void:
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.012
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.5


static func _configure_temp(noise: FastNoiseLite, seed_value: int) -> void:
	noise.seed = seed_value + 777
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.004
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2


static func _get_shared_noise() -> FastNoiseLite:
	if _shared_noise == null or _shared_seed != active_seed:
		_shared_noise = FastNoiseLite.new()
		_configure(_shared_noise, active_seed)
		_shared_temp = FastNoiseLite.new()
		_configure_temp(_shared_temp, active_seed)
		_shared_seed = active_seed
	return _shared_noise


static func _get_temp_noise() -> FastNoiseLite:
	_get_shared_noise()
	return _shared_temp


static func surface_height(x: int, z: int) -> int:
	var hill := _get_shared_noise().get_noise_2d(float(x), float(z))
	return int(round(hill * AMPLITUDE))


static func biome_at(x: int, z: int) -> int:
	var temp := _get_temp_noise().get_noise_2d(float(x), float(z))
	if temp < -0.22:
		return BIOME_SNOW
	if temp > 0.28:
		return BIOME_DESERT
	return BIOME_PLAINS


static func _hash01(x: int, z: int, salt: int) -> float:
	var h := (x * 374761393 + z * 668265263 + salt * 974711) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / float(0xffffff)


static func _hash3(x: int, y: int, z: int, salt: int) -> float:
	var h := (x * 374761393 + y * 2246822519 + z * 668265263 + salt * 974711) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / float(0xffffff)


static func is_tree_column(x: int, z: int) -> bool:
	# No trees on sand or in the desert, and keep the spawn area clear.
	if surface_height(x, z) <= SAND_MAX_HEIGHT:
		return false
	if absi(x) <= 2 and absi(z) <= 2:
		return false
	var biome := biome_at(x, z)
	if biome == BIOME_DESERT:
		return false
	var density := TREE_DENSITY
	if biome == BIOME_SNOW:
		density *= 0.4
	return _hash01(x, z, 7) < density


static func is_cactus_column(x: int, z: int) -> bool:
	if biome_at(x, z) != BIOME_DESERT:
		return false
	if surface_height(x, z) <= SEA_LEVEL:
		return false
	if absi(x) <= 2 and absi(z) <= 2:
		return false
	return _hash01(x, z, 31) < CACTUS_DENSITY


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var scale := 1 << lod
	var size := out_buffer.get_size()
	for local_x in size.x:
		for local_z in size.z:
			var world_x := (origin.x + local_x) * scale
			var world_z := (origin.z + local_z) * scale
			var surface := surface_height(world_x, world_z)
			var biome := biome_at(world_x, world_z)
			var top_type := Blocks.GRASS
			var sub_type := Blocks.DIRT
			if biome == BIOME_DESERT or surface <= SAND_MAX_HEIGHT:
				top_type = Blocks.SAND
				sub_type = Blocks.SAND
			elif biome == BIOME_SNOW:
				top_type = Blocks.SNOW_GRASS
			elif surface <= SEA_LEVEL + 1:
				top_type = Blocks.SAND
				sub_type = Blocks.SAND
			for local_y in size.y:
				var world_y := (origin.y + local_y) * scale + scale / 2
				var cell_y := int(floor(world_y))
				var type := 0
				if world_y <= surface:
					if world_y > surface - 3:
						type = sub_type if world_y < surface else top_type
					else:
						type = Blocks.STONE
						# Caves carve the stone layer (never near the surface).
						if world_y < surface - 3 and cell_y > -48:
							var cave := _cave_noise.get_noise_3d(
								float(world_x), float(cell_y), float(world_z))
							if cave > CAVE_THRESHOLD:
								type = 0
						# Ores scatter inside surviving stone.
						if type == Blocks.STONE:
							var depth := surface - cell_y
							if depth >= 4 and _hash3(world_x, cell_y, world_z, 21) < 0.012:
								type = Blocks.COAL_ORE
							elif depth >= 7 and _hash3(world_x, cell_y, world_z, 22) < 0.006:
								type = Blocks.IRON_ORE
							elif cell_y <= -14 and _hash3(world_x, cell_y, world_z, 23) < 0.003:
								type = Blocks.GOLD_ORE
				elif surface < SEA_LEVEL and world_y <= SEA_LEVEL:
					type = Blocks.WATER
				if type != 0:
					out_buffer.set_voxel(type, local_x, local_y, local_z, VoxelBuffer.CHANNEL_TYPE)
	if scale == 1:
		_stamp_trees(out_buffer, origin, size)
		_stamp_cacti(out_buffer, origin, size)


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


func _stamp_cacti(out_buffer: VoxelBuffer, origin: Vector3i, size: Vector3i) -> void:
	for cx in range(0, size.x):
		for cz in range(0, size.z):
			var world_x := origin.x + cx
			var world_z := origin.z + cz
			if not is_cactus_column(world_x, world_z):
				continue
			var base := surface_height(world_x, world_z)
			var height := 2 + int(_hash01(world_x, world_z, 32) * 3.0)
			for dy in range(1, height + 1):
				_set_world(out_buffer, origin, size, world_x, base + dy, world_z, Blocks.CACTUS, true)


func _set_world(out_buffer: VoxelBuffer, origin: Vector3i, size: Vector3i, x: int, y: int, z: int, type: int, overwrite: bool) -> void:
	var local := Vector3i(x - origin.x, y - origin.y, z - origin.z)
	if local.x < 0 or local.y < 0 or local.z < 0:
		return
	if local.x >= size.x or local.y >= size.y or local.z >= size.z:
		return
	if not overwrite and out_buffer.get_voxel(local.x, local.y, local.z, VoxelBuffer.CHANNEL_TYPE) != 0:
		return
	out_buffer.set_voxel(type, local.x, local.y, local.z, VoxelBuffer.CHANNEL_TYPE)
