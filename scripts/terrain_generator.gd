extends VoxelGeneratorScript
## Rolling-hills terrain generator for the blocky mesher.
##
## Voxel Tools' built-in heightmap generators write the SDF channel (they
## target the smooth terrain mesher), so a blocky world needs a generator
## that writes the TYPE channel. This one fills each column by height:
## grass on the surface, dirt under it, stone below that. It is used through
## the VoxelGeneratorScript resource (the scriptable generator class).

const GRASS_TYPE := 1
const STONE_TYPE := 2
const DIRT_TYPE := 3

var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.seed = 20261107
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 0.012
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_noise.fractal_gain = 0.5


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var scale := 1 << lod
	var size := out_buffer.get_size()
	for local_x in size.x:
		for local_z in size.z:
			var world_x := (origin.x + local_x) * scale
			var world_z := (origin.z + local_z) * scale
			var hill := _noise.get_noise_2d(float(world_x), float(world_z))
			var surface := int(round(hill * 14.0))
			for local_y in size.y:
				var world_y := (origin.y + local_y) * scale + scale / 2
				var type := 0
				if world_y <= surface - 3 * scale:
					type = STONE_TYPE
				elif world_y <= surface - 1:
					type = DIRT_TYPE
				elif world_y <= surface:
					type = GRASS_TYPE
				if type != 0:
					out_buffer.set_voxel(type, local_x, local_y, local_z, VoxelBuffer.CHANNEL_TYPE)
