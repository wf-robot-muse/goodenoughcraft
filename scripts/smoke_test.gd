extends Node
## Headless smoke test for the voxel foundation.
##
## Run by CI as: godot --headless --path . res://scenes/smoke_test.tscn
## Loads the real demo scene, waits for the voxel terrain to generate and
## mesh blocks around the viewer, then prints SMOKE PASS / SMOKE FAIL and
## exits with code 0 / 1.

const REQUIRED_CLASSES := [
	"VoxelLodTerrain",
	"VoxelMesherBlocky",
	"VoxelBlockyLibrary",
	"VoxelBlockyModelCube",
	"VoxelGeneratorFlat",
	"VoxelViewer",
]
const MAX_WAIT_SECONDS := 30.0


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
		_fail("Demo scene did not create the VoxelTerrain node")
		return

	var waited := 0.0
	while waited < MAX_WAIT_SECONDS:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		var data_blocks := terrain.debug_get_data_block_count()
		var mesh_blocks := terrain.debug_get_mesh_block_count()
		if data_blocks > 0 and mesh_blocks > 0:
			print("SMOKE PASS data_blocks=", data_blocks, " mesh_blocks=", mesh_blocks)
			get_tree().quit(0)
			return

	_fail("Terrain generated no blocks within %s seconds" % MAX_WAIT_SECONDS)


func _fail(reason: String) -> void:
	printerr("SMOKE FAIL: ", reason)
	get_tree().quit(1)
