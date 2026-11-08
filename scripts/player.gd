extends CharacterBody3D
## First-person player: walk/jump with terrain collision, an optional fly
## mode, mouse-look, and block interaction (mine/place) through Voxel
## Tools' VoxelTool raycast. Creative-style: every hotbar block is
## available in unlimited quantity (survival/inventory is a later phase).
##
## The node is built entirely in code by main.gd; this script creates its
## own collision shape, head/camera, and VoxelViewer in _ready.

signal selection_changed(index: int)

const TerrainGen := preload("res://scripts/terrain_generator.gd")

const WALK_SPEED := 6.0
const SPRINT_SPEED := 10.0
const FLY_SPEED := 22.0
const JUMP_VELOCITY := 8.6
const GRAVITY := 28.0
const REACH := 8.0
const ACTION_DELAY := 0.22
const MAX_FALL_SPEED := 45.0
const GROUND_WAIT_TIMEOUT := 5.0

var terrain: VoxelLodTerrain
var selected_index := 0
var flying := false

var _head: Node3D
var _camera: Camera3D
var _tool: VoxelTool
var _cooldown := 0.0
# At spawn, terrain collisions near the player may not exist yet. The
# player hovers (no gravity) until a downward ray finds generated ground,
# so it can never fall through a still-loading world.
var _awaiting_ground := true
var _ground_wait := 0.0


func _ready() -> void:
	floor_snap_length = 0.5
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

	_head = Node3D.new()
	_head.position = Vector3(0, 1.62, 0)
	add_child(_head)
	_camera = Camera3D.new()
	_camera.current = true
	_head.add_child(_camera)

	# The viewer makes the terrain stream (and generate collisions) here.
	var viewer := VoxelViewer.new()
	viewer.view_distance = 96
	add_child(viewer)


func selected_block() -> int:
	return Blocks.HOTBAR[selected_index]


func get_camera() -> Camera3D:
	return _camera


func get_pitch() -> float:
	if _head == null:
		return 0.0
	return _head.rotation.x


func set_look(yaw: float, pitch: float) -> void:
	rotation.y = yaw
	if _head != null:
		_head.rotation.x = clampf(pitch, -1.55, 1.55)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# First click just captures the mouse; it must not also mine.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_selection(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_selection(1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_try_action(true)
			_cooldown = ACTION_DELAY
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_try_action(false)
			_cooldown = ACTION_DELAY
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_F:
			flying = not flying
			velocity = Vector3.ZERO
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var index: int = event.keycode - KEY_1
			if index < Blocks.HOTBAR.size():
				selected_index = index
				selection_changed.emit(selected_index)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.0025)
		_head.rotation.x = clampf(_head.rotation.x - event.relative.y * 0.0025, -1.55, 1.55)


func _change_selection(direction: int) -> void:
	selected_index = (selected_index + direction + Blocks.HOTBAR.size()) % Blocks.HOTBAR.size()
	selection_changed.emit(selected_index)


func _physics_process(delta: float) -> void:
	if _awaiting_ground:
		velocity = Vector3.ZERO
		_ground_wait += delta
		if flying or _ground_wait > GROUND_WAIT_TIMEOUT or _ground_below():
			_awaiting_ground = false
		else:
			return

	# Safety net: if the player ever ends up below the world, respawn.
	if global_position.y < -80.0:
		position = Vector3(8.5, TerrainGen.surface_height(8, 8) + 1.05, 8.5)
		velocity = Vector3.ZERO
		_awaiting_ground = true
		_ground_wait = 0.0
		return

	# Held-button mining/placing repeats at a fixed rate.
	_cooldown -= delta
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _cooldown <= 0.0:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_try_action(true)
			_cooldown = ACTION_DELAY
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_try_action(false)
			_cooldown = ACTION_DELAY

	var input_dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input_dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1.0

	if flying:
		var basis := _camera.global_transform.basis
		var wish := basis * Vector3(input_dir.x, 0.0, input_dir.z)
		if Input.is_physical_key_pressed(KEY_SPACE):
			wish += Vector3.UP
		if Input.is_physical_key_pressed(KEY_CTRL):
			wish -= Vector3.UP
		if wish.length() > 1.0:
			wish = wish.normalized()
		velocity = wish * FLY_SPEED
	else:
		if not is_on_floor():
			velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL_SPEED)
		elif Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP_VELOCITY
		var basis := global_transform.basis
		var wish := basis * Vector3(input_dir.x, 0.0, input_dir.z)
		wish.y = 0.0
		if wish.length() > 1.0:
			wish = wish.normalized()
		var speed := SPRINT_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
		velocity.x = wish.x * speed
		velocity.z = wish.z * speed
	move_and_slide()


func _ground_below() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.2, 0), global_position + Vector3(0, -3.0, 0))
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


func _try_action(mine: bool) -> void:
	if terrain == null or _camera == null:
		return
	if _tool == null:
		_tool = terrain.get_voxel_tool()
		_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var origin := _camera.global_position
	var direction := -_camera.global_transform.basis.z
	var hit := _tool.raycast(origin, direction, REACH)
	if hit == null:
		return
	if mine:
		_tool.set_voxel(hit.position, Blocks.AIR)
	else:
		var cell: Vector3i = hit.previous_position
		# Never place a block inside the player's own body.
		var player_box := AABB(global_position - Vector3(0.35, 0.0, 0.35), Vector3(0.7, 1.8, 0.7))
		var cell_box := AABB(Vector3(cell), Vector3.ONE)
		if player_box.intersects(cell_box):
			return
		_tool.set_voxel(cell, selected_block())
