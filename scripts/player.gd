extends CharacterBody3D
## First-person player: walk/jump with terrain collision, an optional fly
## mode, mouse or right-stick look, a toggleable flashlight, and block
## interaction (mine/place) through Voxel Tools' VoxelTool raycast.
## Creative-style: every hotbar block is available in unlimited quantity
## (survival/inventory is a later phase).
##
## All input goes through the named InputMap actions installed by the
## Game autoload, so every control can be remapped per user (keyboard,
## mouse, and gamepad) from the settings screen.
##
## The node is built entirely in code by main.gd; this script creates its
## own collision shape, head/camera/flashlight, and VoxelViewer in _ready.

signal selection_changed(index: int)
signal pause_requested

const TerrainGen := preload("res://scripts/terrain_generator.gd")

const WALK_SPEED := 6.0
const SPRINT_SPEED := 10.0
const FLY_SPEED := 22.0
const JUMP_VELOCITY := 8.6
const GRAVITY := 28.0
const REACH := 8.0
const ACTION_DELAY := 0.30
const MAX_FALL_SPEED := 45.0
const GROUND_WAIT_TIMEOUT := 5.0
const STICK_LOOK_SPEED := 2.4

var terrain: VoxelLodTerrain
var selected_index := 0
var flying := false
var flashlight_on := false
# Touch controls (Fire OS / Android tablets): set by the touch layer.
# While touch mode is on, held mine/place repeats without a captured
# mouse, and movement can come from the virtual joystick (touch_move)
# instead of the InputMap move actions.
var touch_move := Vector2.ZERO

var _touch_mode := false

var _head: Node3D
var _camera: Camera3D
var _lamp: SpotLight3D
var _tool: VoxelTool
var _cooldown := 0.0
var _autojump_cd := 0.0
var _pad_mode := false
var _step_acc := 0.0
var _was_in_water := false
var _last_pos := Vector3.ZERO
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

	# Flashlight: a spotlight that follows the look direction.
	_lamp = SpotLight3D.new()
	_lamp.spot_range = 34.0
	_lamp.spot_angle = 30.0
	_lamp.light_energy = 2.6
	_lamp.shadow_enabled = false
	_lamp.visible = flashlight_on
	_head.add_child(_lamp)

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


func set_flashlight(on: bool) -> void:
	flashlight_on = on
	if _lamp != null:
		_lamp.visible = on


# --- Touch control hooks (called by scripts/touch_controls.gd) ---

func set_touch_mode(on: bool) -> void:
	_touch_mode = on
	if not on:
		touch_move = Vector2.ZERO


func touch_look(relative: Vector2) -> void:
	rotate_y(-relative.x * 0.0042)
	if _head != null:
		_head.rotation.x = clampf(_head.rotation.x - relative.y * 0.0042, -1.55, 1.55)


func touch_action(mine: bool) -> void:
	_try_action(mine)
	_cooldown = ACTION_DELAY


## Mine/place at an arbitrary screen position (touch gestures, Fire
## build issue #3): raycast from the camera through that pixel instead
## of through the crosshair.
func touch_action_at(mine: bool, screen_pos: Vector2) -> void:
	if _camera == null:
		return
	var origin := _camera.project_ray_origin(screen_pos)
	var direction := _camera.project_ray_normal(screen_pos)
	_try_action_ray(mine, origin, direction)
	_cooldown = ACTION_DELAY


func toggle_fly() -> void:
	flying = not flying
	velocity = Vector3.ZERO


func select_slot(index: int) -> void:
	if index < 0 or index >= Blocks.HOTBAR.size():
		return
	if index != selected_index:
		selected_index = index
		selection_changed.emit(selected_index)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pad_mode = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_pad_mode = false

	if event.is_action_pressed("pause"):
		pause_requested.emit()
		return

	# The first mine click just captures the mouse; it must not also mine.
	if event.is_action_pressed("mine") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _pad_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _pad_mode:
		return

	if event.is_action_pressed("mine"):
		_try_action(true)
		_cooldown = ACTION_DELAY
	elif event.is_action_pressed("place"):
		_try_action(false)
		_cooldown = ACTION_DELAY
	elif event.is_action_pressed("hotbar_next"):
		_change_selection(1)
	elif event.is_action_pressed("hotbar_prev"):
		_change_selection(-1)
	elif event.is_action_pressed("fly_toggle"):
		toggle_fly()
	elif event.is_action_pressed("flashlight"):
		set_flashlight(not flashlight_on)
	else:
		for i in range(1, Blocks.HOTBAR.size() + 1):
			if event.is_action_pressed("hotbar_" + str(i)):
				selected_index = i - 1
				selection_changed.emit(selected_index)
				break

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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

	# Right-stick look (gamepad).
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.1:
		rotate_y(-look.x * STICK_LOOK_SPEED * delta)
		_head.rotation.x = clampf(_head.rotation.x - look.y * STICK_LOOK_SPEED * delta, -1.55, 1.55)

	# Held-button mining/placing repeats at a fixed rate — mouse and
	# keyboard only. On a gamepad, one press is exactly one block
	# (v0.2.1 fix: a single trigger pull used to mine/place ~3 blocks,
	# because the press event fired once and this repeat fired twice
	# more during the same pull). Gamepad actions fire from the press
	# event in _unhandled_input only.
	_cooldown -= delta
	if not _pad_mode and (_touch_mode or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) and _cooldown <= 0.0:
		if Input.is_action_pressed("mine"):
			_try_action(true)
			_cooldown = ACTION_DELAY
		elif Input.is_action_pressed("place"):
			_try_action(false)
			_cooldown = ACTION_DELAY

	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _touch_mode and touch_move.length() > 0.05:
		move = touch_move
	var input_dir := Vector3(move.x, 0.0, move.y)

	if flying:
		var basis := _camera.global_transform.basis
		var wish := basis * input_dir
		if Input.is_action_pressed("fly_up"):
			wish += Vector3.UP
		if Input.is_action_pressed("fly_down"):
			wish -= Vector3.UP
		if wish.length() > 1.0:
			wish = wish.normalized()
		velocity = wish * FLY_SPEED
	else:
		var in_water := _voxel_at(global_position + Vector3(0.0, 0.4, 0.0)) == Blocks.WATER \
			or _voxel_at(global_position + Vector3(0.0, 1.4, 0.0)) == Blocks.WATER
		if in_water and not _was_in_water:
			Game.play_sfx("splash")
		_was_in_water = in_water
		var basis := global_transform.basis
		var wish := basis * input_dir
		wish.y = 0.0
		if wish.length() > 1.0:
			wish = wish.normalized()
		# Sprint: the sprint action, or — Minecraft-style — the touch
		# joystick pushed fully forward to its rim (issue #3).
		var sprinting := Input.is_action_pressed("sprint") \
			or (_touch_mode and touch_move.y <= -0.92)
		var speed := SPRINT_SPEED if sprinting else WALK_SPEED
		if in_water:
			# Swimming: slow sink, hold jump to swim up, slower movement.
			speed *= 0.55
			if Input.is_action_pressed("jump"):
				velocity.y = minf(velocity.y + 42.0 * delta, 4.2)
			else:
				velocity.y = maxf(velocity.y - 12.0 * delta, -2.6)
		else:
			_autojump_cd = maxf(_autojump_cd - delta, 0.0)
			if not is_on_floor():
				velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL_SPEED)
			elif Input.is_action_pressed("jump"):
				velocity.y = JUMP_VELOCITY
			elif Game.auto_jump_enabled() and _autojump_cd <= 0.0 \
					and _step_up_ahead(wish):
				# Auto-jump (issue #8): hop one-block step-ups while
				# walking, Minecraft-style. Grounded and dry only —
				# never while flying or swimming.
				velocity.y = JUMP_VELOCITY
				_autojump_cd = 0.3
		velocity.x = wish.x * speed
		velocity.z = wish.z * speed
	move_and_slide()

	# Footsteps while walking on solid ground.
	var flat_distance := Vector2(
		global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	if is_on_floor() and not flying:
		_step_acc += flat_distance
		if _step_acc > 2.3:
			_step_acc = 0.0
			Game.play_sfx("step", randf_range(0.9, 1.1))
	_last_pos = global_position


func _voxel_at(pos: Vector3) -> int:
	if terrain == null:
		return Blocks.AIR
	if _tool == null:
		_tool = terrain.get_voxel_tool()
		_tool.channel = VoxelBuffer.CHANNEL_TYPE
	return _tool.get_voxel(Vector3i(floori(pos.x), floori(pos.y), floori(pos.z)))


func _ground_below() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.2, 0), global_position + Vector3(0, -3.0, 0))
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


## True when the player is walking into a step exactly one block high
## with clear space above it — the auto-jump trigger condition.
func _step_up_ahead(wish: Vector3) -> bool:
	var dir := Vector3(wish.x, 0.0, wish.z)
	if dir.length() < 0.2:
		return false
	dir = dir.normalized()
	var feet := floori(global_position.y + 0.05)
	var probe := global_position + dir * 0.8
	var step_block := _voxel_at(Vector3(probe.x, feet + 0.5, probe.z))
	if step_block == Blocks.AIR or step_block == Blocks.WATER:
		return false
	return _voxel_at(Vector3(probe.x, feet + 1.5, probe.z)) == Blocks.AIR \
		and _voxel_at(Vector3(probe.x, feet + 2.5, probe.z)) == Blocks.AIR


func _try_action(mine: bool) -> void:
	if terrain == null or _camera == null:
		return
	var origin := _camera.global_position
	var direction := -_camera.global_transform.basis.z
	_try_action_ray(mine, origin, direction)


func _try_action_ray(mine: bool, origin: Vector3, direction: Vector3) -> void:
	if terrain == null:
		return
	if _tool == null:
		_tool = terrain.get_voxel_tool()
		_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var hit := _tool.raycast(origin, direction, REACH)
	if hit == null:
		return
	if mine:
		_tool.set_voxel(hit.position, Blocks.AIR)
		Game.play_sfx("break", randf_range(0.92, 1.08))
	else:
		var cell: Vector3i = hit.previous_position
		# Never place a block inside the player's own body.
		var player_box := AABB(global_position - Vector3(0.35, 0.0, 0.35), Vector3(0.7, 1.8, 0.7))
		var cell_box := AABB(Vector3(cell), Vector3.ONE)
		if player_box.intersects(cell_box):
			return
		_tool.set_voxel(cell, selected_block())
		Game.play_sfx("place", randf_range(0.95, 1.05))
