extends Node
## Headless smoke test for VoxelGame (Phase 1).
##
## Run by CI as: godot --headless --path . res://scenes/smoke_test.tscn
## Loads the real game scene and verifies, in order: the Voxel Tools
## classes exist, the terrain streams data and mesh blocks around the
## player, the player falls and lands on the generated terrain (collision
## streaming works), and a block edit round-trips through VoxelTool.
## Prints SMOKE PASS / SMOKE FAIL and exits with code 0 / 1.

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


func _ready() -> void:
	for voxel_class in REQUIRED_CLASSES:
		if not ClassDB.class_exists(voxel_class):
			_fail("Voxel Tools class missing: " + voxel_class)
			return

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if main_scene == null:
		_fail("Could not load res://scenes/main.tscn")
		return
	var main := main_scene.instantiate()
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

	# 3. Block edit round-trip through VoxelTool near the spawn column.
	var tool := terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var ground := TerrainGen.surface_height(8, 8)
	var cell := Vector3i(8, ground + 6, 8)
	tool.set_voxel(cell, Blocks.BRICK)
	var read_back: int = tool.get_voxel(cell)
	tool.set_voxel(cell, Blocks.AIR)
	if read_back != Blocks.BRICK:
		_fail("Edit round-trip failed: set BRICK, read back %d" % read_back)
		return

	print("SMOKE PASS data_blocks=", data_blocks, " mesh_blocks=", mesh_blocks, " player_landed=true edit_roundtrip=true")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	printerr("SMOKE FAIL: ", reason)
	get_tree().quit(1)
