extends Node
## Headless smoke test for GoodEnoughCraft (Phase 2).
##
## Run by CI as: godot --headless --path . res://scenes/smoke_test.tscn
## Sets up a throwaway profile/world/save slot through the Game autoload,
## loads the real game scene against it, and verifies, in order: the
## Voxel Tools classes exist, the terrain streams data and mesh blocks
## around the player, the player falls and lands on the generated terrain
## (collision streaming works), a block edit round-trips through
## VoxelTool, the Phase 2 world features are present in the generated
## terrain (an ore block underground, a carved cave pocket, water filling
## a lowland column), and a block edit survives a full save + scene
## reload through the profile's region files (persistence). The
## throwaway profile is deleted again at the end. Prints SMOKE PASS /
## SMOKE FAIL and exits with code 0 / 1.

const REQUIRED_CLASSES := [
	"VoxelLodTerrain",
	"VoxelMesherBlocky",
	"VoxelBlockyLibrary",
	"VoxelBlockyModelCube",
	"VoxelGeneratorScript",
	"VoxelStreamRegionFiles",
	"VoxelViewer",
]
const TerrainGen := preload("res://scripts/terrain_generator.gd")
const MAX_WAIT_SECONDS := 60.0
const ORES := [Blocks.COAL_ORE, Blocks.IRON_ORE, Blocks.GOLD_ORE]


func _ready() -> void:
	for voxel_class in REQUIRED_CLASSES:
		if not ClassDB.class_exists(voxel_class):
			_fail("Voxel Tools class missing: " + voxel_class)
			return

	# Throwaway profile context (also removes leftovers of earlier runs).
	for existing in Game.profiles.duplicate():
		if str(existing.get("name", "")) == "SmokeTest":
			Game.delete_user(existing["id"])
	var user := Game.create_user("SmokeTest")
	var world := Game.create_world(user["id"], "Smoke World", TerrainGen.NOISE_SEED)
	Game.set_context(user, world, "smoke")

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if main_scene == null:
		_fail("Could not load res://scenes/main.tscn")
		return
	var main = main_scene.instantiate() # untyped: the test calls main._save_state()
	add_child(main)

	var terrain := main.get_node_or_null("VoxelTerrain") as VoxelLodTerrain
	if terrain == null:
		_fail("Game scene did not create the VoxelTerrain node")
		return
	var player := main.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		_fail("Game scene did not create the Player node")
		return

	# 1. Terrain streams blocks around the player.
	var waited := 0.0
	var data_blocks := 0
	var mesh_blocks := 0
	while waited < MAX_WAIT_SECONDS:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		data_blocks = terrain.debug_get_data_block_count()
		mesh_blocks = terrain.debug_get_mesh_block_count()
		if data_blocks > 0 and mesh_blocks > 0:
			break
	if data_blocks == 0 or mesh_blocks == 0:
		_fail("Terrain generated no blocks within %s seconds" % MAX_WAIT_SECONDS)
		return

	# 2. The player lands on the terrain (collision streaming works).
	waited = 0.0
	while waited < MAX_WAIT_SECONDS:
		if player.is_on_floor():
			break
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if not player.is_on_floor():
		_fail("Player never landed on the terrain")
		return

	var tool := terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var spawn_x := int(floor(player.global_position.x))
	var spawn_z := int(floor(player.global_position.z))

	# 3. Block edit round-trip through VoxelTool near the spawn column.
	var ground := TerrainGen.surface_height(8, 8)
	var cell := Vector3i(8, ground + 6, 8)
	tool.set_voxel(cell, Blocks.BRICK)
	var read_back: int = tool.get_voxel(cell)
	tool.set_voxel(cell, Blocks.AIR)
	if read_back != Blocks.BRICK:
		_fail("Edit round-trip failed: set BRICK, read back %d" % read_back)
		return

	# 4. Phase 2 world features near spawn: an ore block underground and
	# a carved cave pocket (air deep below the surface, walled by rock).
	var ore_found := false
	var cave_found := false
	for x in range(spawn_x - 24, spawn_x + 25):
		if ore_found and cave_found:
			break
		for z in range(spawn_z - 24, spawn_z + 25):
			if ore_found and cave_found:
				break
			var surface := TerrainGen.surface_height(x, z)
			for y in range(-24, surface - 3):
				var v: int = tool.get_voxel(Vector3i(x, y, z))
				if not ore_found and ORES.has(v):
					ore_found = true
				if not cave_found and v == Blocks.AIR and y < surface - 5 and y > -40:
					if _solid_neighbours(tool, Vector3i(x, y, z)) >= 4:
						cave_found = true
				if ore_found and cave_found:
					break
	if not ore_found:
		_fail("No ore block found underground near spawn")
		return
	if not cave_found:
		_fail("No cave pocket found underground near spawn")
		return

	# 5. Persistence: edit a block, save through the game's own save
	# path, reload the scene, and read the edit back from region files.
	var persist_cell := Vector3i(spawn_x + 2, TerrainGen.surface_height(spawn_x + 2, spawn_z + 2) + 5, spawn_z + 2)
	tool.set_voxel(persist_cell, Blocks.BRICK)
	main._save_state(false)
	remove_child(main)
	main.free()
	await get_tree().create_timer(1.0).timeout

	var main2 := main_scene.instantiate()
	add_child(main2)
	var terrain2 := main2.get_node_or_null("VoxelTerrain") as VoxelLodTerrain
	if terrain2 == null:
		_fail("Reloaded game scene did not create the VoxelTerrain node")
		return
	var tool2 := terrain2.get_voxel_tool()
	tool2.channel = VoxelBuffer.CHANNEL_TYPE
	waited = 0.0
	var persisted: int = Blocks.AIR
	while waited < 30.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		persisted = tool2.get_voxel(persist_cell)
		if persisted == Blocks.BRICK:
			break
	if persisted != Blocks.BRICK:
		_fail("Persistence failed: edit read back %d after save + reload" % persisted)
		return

	# 6. Water: find the nearest lowland column, move the player there,
	# and wait for its water cell to stream in.
	var player2 := main2.get_node_or_null("Player") as CharacterBody3D
	var water_cell := Vector3i(9999, TerrainGen.SEA_LEVEL, 9999)
	var best := 1 << 30
	for x in range(spawn_x - 80, spawn_x + 81):
		for z in range(spawn_z - 80, spawn_z + 81):
			if TerrainGen.surface_height(x, z) < TerrainGen.SEA_LEVEL:
				var d := (x - spawn_x) * (x - spawn_x) + (z - spawn_z) * (z - spawn_z)
				if d < best:
					best = d
					water_cell = Vector3i(x, TerrainGen.SEA_LEVEL, z)
	if water_cell.x == 9999:
		_fail("No lowland column (surface below sea level) near spawn")
		return
	player2.global_position = Vector3(water_cell.x + 0.5, 14.0, water_cell.z + 0.5)
	waited = 0.0
	var water_read: int = Blocks.AIR
	while waited < 30.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		water_read = tool2.get_voxel(water_cell)
		if water_read == Blocks.WATER:
			break
	if water_read != Blocks.WATER:
		_fail("No water in lowland column %s (read %d)" % [str(water_cell), water_read])
		return

	Game.delete_user(user["id"])
	print("SMOKE PASS data_blocks=", data_blocks, " mesh_blocks=", mesh_blocks,
		" player_landed=true edit_roundtrip=true ore=true cave=true persisted=true water=true")
	get_tree().quit(0)


func _solid_neighbours(tool: VoxelTool, cell: Vector3i) -> int:
	var count := 0
	for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
			Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var v: int = tool.get_voxel(cell + offset)
		if v != Blocks.AIR and v != Blocks.WATER:
			count += 1
	return count


func _fail(reason: String) -> void:
	printerr("SMOKE FAIL: ", reason)
	get_tree().quit(1)
