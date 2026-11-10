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
const ACTION_DELAY := 0.30 # held placement repeat rate
const NEXT_BLOCK_DELAY := 0.25 # Minecraft's delay before the next held break
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
# Effects parity with the original game (Fire build issue #15):
# a visible swinging hand holding the selected block, per-material
# hit/break/place sounds, crack + burst particles, target marking,
# and decorative item drops (option A: pickup is visual only).
var _hand: Node3D
var _hand_base_pos := Vector3(0.46, -0.44, -0.8)
var _held_cube: MeshInstance3D
var _held_block_id := -1
var _tile_materials: Dictionary = {} # block id -> StandardMaterial3D
var _swing_t := 0.0
var _swing_hits := 0
var _place_swing_t := -1.0
var _outline: MeshInstance3D
var _highlight: MeshInstance3D
var _crack_particles: GPUParticles3D
var _burst_particles: GPUParticles3D
var _crack_particle_mat: StandardMaterial3D
var _burst_particle_mat: StandardMaterial3D
var _mine_face_point := Vector3.ZERO
var _drops: Array = [] # {node, vel, age, flying}
const SWING_PERIOD := 0.30
const MAX_DROPS := 24
var _crack: MeshInstance3D
var _crack_material: StandardMaterial3D
var _crack_textures: Array[Texture2D] = []
var _crack_stage := -1
var _touch_mining := false
var _touch_mine_pos := Vector2.ZERO
var _mine_cell := Vector3i.ZERO
var _mine_cell_valid := false
var _mine_progress := 0.0
var _mine_delay := 0.0
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

	_build_crack_overlay()
	_build_hand()
	_build_target_marking()
	_build_particles()
	selection_changed.connect(func(_i: int) -> void: _refresh_held_block())


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
		touch_mine_end()


func touch_look(relative: Vector2) -> void:
	rotate_y(-relative.x * 0.0042)
	if _head != null:
		_head.rotation.x = clampf(_head.rotation.x - relative.y * 0.0042, -1.55, 1.55)


func touch_action(mine: bool) -> void:
	# Mining is timed now (issue #10), so this legacy one-shot hook only
	# places. Timed touch mining uses touch_mine_begin/update/end.
	if not mine:
		_try_action(false)
		_cooldown = ACTION_DELAY


## Place at an arbitrary screen position (touch tap, Fire build issue
## #3), or begin timed mining at that position when mine is true.
func touch_action_at(mine: bool, screen_pos: Vector2) -> void:
	if mine:
		touch_mine_begin(screen_pos)
		return
	if _camera == null:
		return
	var origin := _camera.project_ray_origin(screen_pos)
	var direction := _camera.project_ray_normal(screen_pos)
	_try_action_ray(false, origin, direction)
	_cooldown = ACTION_DELAY


## Begin Minecraft-style timed mining at a touch point. The player
## resolves the block under that screen position every physics tick;
## sliding the finger therefore retargets (and resets) the break, just
## as releasing the hold does.
func touch_mine_begin(screen_pos: Vector2) -> void:
	_touch_mining = true
	_touch_mine_pos = screen_pos
	_reset_mining()


func touch_mine_update(screen_pos: Vector2) -> void:
	_touch_mine_pos = screen_pos


func touch_mine_end() -> void:
	_touch_mining = false
	_reset_mining()


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
		# No instant break on the press (issue #10): _update_mining
		# accumulates crack progress for as long as the input is held.
		pass
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

	# Held placement repeats at a fixed rate — mouse and keyboard
	# only. On a gamepad, placement remains one block per press (the
	# v0.2.1 fix). Mining is separate: _update_mining applies timed,
	# per-block breaking for mouse, gamepad, and touch holds alike.
	_cooldown -= delta
	if not _pad_mode and (_touch_mode or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) and _cooldown <= 0.0:
		if Input.is_action_pressed("place"):
			_try_action(false)
			_cooldown = ACTION_DELAY
	_update_mining(delta)

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

	_update_target_marking()

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


## Minecraft-style timed breaking (Fire build issue #10): while a mine
## input is held, crack progress accumulates against the targeted
## block at that block's bare-hand rate (Blocks.break_seconds). The
## block breaks only when progress reaches its full time. Releasing
## the input, losing the target, or moving to another block resets
## progress. After a break, Minecraft's short delay applies before the
## next block starts cracking.
func _update_mining(delta: float) -> void:
	if terrain == null or _camera == null:
		_reset_mining()
		return
	var origin := Vector3.ZERO
	var direction := Vector3.ZERO
	var held := false
	if _touch_mining:
		origin = _camera.project_ray_origin(_touch_mine_pos)
		direction = _camera.project_ray_normal(_touch_mine_pos)
		held = true
	elif Input.is_action_pressed("mine") and (_pad_mode or _touch_mode \
			or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		origin = _camera.global_position
		direction = -_camera.global_transform.basis.z
		held = true
	if not held:
		_reset_mining()
		return

	if _tool == null:
		_tool = terrain.get_voxel_tool()
		_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var hit := _tool.raycast(origin, direction, REACH)
	if hit == null:
		_reset_mining()
		return
	var block_id: int = _tool.get_voxel(hit.position)
	if block_id == Blocks.AIR or block_id == Blocks.WATER:
		_reset_mining()
		return

	if not _mine_cell_valid or hit.position != _mine_cell:
		_mine_cell = hit.position
		_mine_cell_valid = true
		_mine_progress = 0.0

	if _mine_delay > 0.0:
		_mine_delay -= delta
		_hide_crack()
		if _crack_particles != null:
			_crack_particles.emitting = false
		return

	# Effects (#15): the hand swings on a steady rhythm while mining;
	# each swing lands a per-material hit sound, and crack particles
	# chip off the struck face.
	_swing_t += delta
	var swing_index := int(_swing_t / SWING_PERIOD)
	if swing_index != _swing_hits:
		_swing_hits = swing_index
		Game.play_block_sfx("hit", block_id)
	_mine_face_point = Vector3(hit.position) + Vector3(0.5, 0.5, 0.5) \
		+ Vector3(hit.previous_position - hit.position) * 0.52
	if _crack_particles != null:
		_crack_particle_mat.albedo_color = Blocks.block_color(block_id)
		_crack_particles.global_position = _mine_face_point
		_crack_particles.emitting = true

	_mine_progress += delta
	var needed := Blocks.break_seconds(block_id)
	if _mine_progress >= needed:
		_tool.set_voxel(hit.position, Blocks.AIR)
		Game.play_block_sfx("break", block_id)
		_burst_at(hit.position, block_id)
		_spawn_drop(block_id, hit.position)
		_mine_progress = 0.0
		_mine_delay = NEXT_BLOCK_DELAY
		_mine_cell_valid = false
		_hide_crack()
		if _crack_particles != null:
			_crack_particles.emitting = false
		return
	_show_crack(hit.position, int(_mine_progress / needed * 10.0))


func _reset_mining() -> void:
	_mine_progress = 0.0
	_mine_delay = 0.0
	_mine_cell_valid = false
	_swing_t = 0.0
	_swing_hits = 0
	_hide_crack()
	if _crack_particles != null:
		_crack_particles.emitting = false


func _build_crack_overlay() -> void:
	_crack_textures = _make_crack_textures()
	_crack_material = StandardMaterial3D.new()
	_crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_material.albedo_texture = _crack_textures[0]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.01, 1.01, 1.01)
	mesh.material = _crack_material
	_crack = MeshInstance3D.new()
	_crack.mesh = mesh
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crack.top_level = true
	_crack.visible = false
	add_child(_crack)


## Ten cumulative crack stages, generated procedurally like the game's
## other textures: branching dark walks spread from the center, in the
## spirit of Minecraft's destroy-stage overlay.
func _make_crack_textures() -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261110
	var walkers: Array = []
	for stage in range(10):
		for i in range(3):
			walkers.append([Vector2(32, 32), Vector2.RIGHT.rotated(rng.randf() * TAU)])
		for walker in walkers:
			var pos: Vector2 = walker[0]
			var dir: Vector2 = walker[1]
			for step in range(4):
				dir = dir.rotated(rng.randf_range(-0.7, 0.7))
				pos += dir * 2.0
				for dx in range(2):
					for dy in range(2):
						var px := int(pos.x) + dx
						var py := int(pos.y) + dy
						if px >= 0 and px < 64 and py >= 0 and py < 64:
							image.set_pixel(px, py, Color(0, 0, 0, 0.6))
			walker[0] = pos
			walker[1] = dir
		var snapshot := image.duplicate() as Image
		textures.append(ImageTexture.create_from_image(snapshot))
	return textures


# ------------------------------------------------------ effects (#15)

## The material used for the held block and the decorative drops:
## the block's atlas side tile on a small cube.
func _tile_material(block_id: int) -> Material:
	if _tile_materials.has(block_id):
		return _tile_materials[block_id]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(Blocks.ATLAS_PATH) as Texture2D
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.roughness = 1.0
	var tiles: Array = Blocks.TILES.get(block_id, [Vector2i.ZERO])
	var tile: Vector2i = tiles[0]
	mat.uv1_scale = Vector3(1.0 / Blocks.ATLAS_SIZE.x, 1.0 / Blocks.ATLAS_SIZE.y, 1.0)
	mat.uv1_offset = Vector3(float(tile.x) / Blocks.ATLAS_SIZE.x,
		float(tile.y) / Blocks.ATLAS_SIZE.y, 0.0)
	_tile_materials[block_id] = mat
	return mat


func _build_hand() -> void:
	_hand = Node3D.new()
	_hand.position = _hand_base_pos
	_hand.rotation = Vector3(0.12, -0.22, 0.0)
	_camera.add_child(_hand)
	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.17, 0.17, 0.52)
	arm.mesh = arm_mesh
	arm.position = Vector3(0.06, -0.07, 0.22)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78, 0.58, 0.42)
	skin.roughness = 1.0
	arm_mesh.material = skin
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand.add_child(arm)
	_held_cube = MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(0.34, 0.34, 0.34)
	_held_cube.mesh = cube
	_held_cube.position = Vector3(-0.03, 0.04, -0.30)
	_held_cube.rotation = Vector3(0.3, 0.5, 0.0)
	_held_cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand.add_child(_held_cube)
	_refresh_held_block()


func _refresh_held_block() -> void:
	if _held_cube == null:
		return
	var id := selected_block()
	if id == _held_block_id:
		return
	_held_block_id = id
	(_held_cube.mesh as BoxMesh).material = _tile_material(id)


## Hand animation: an idle sway, a repeating swing while mining
## (driven by _swing_t, which also times the hit sounds), and a
## single swing for each placement.
func _process(delta: float) -> void:
	_update_drops(delta)
	if _hand == null:
		return
	_refresh_held_block()
	var phase := -1.0
	if _place_swing_t >= 0.0:
		_place_swing_t += delta
		phase = _place_swing_t / 0.22
		if phase >= 1.0:
			_place_swing_t = -1.0
			phase = -1.0
	elif _mine_cell_valid and _mine_delay <= 0.0:
		phase = fmod(_swing_t, SWING_PERIOD) / SWING_PERIOD
	var sway := sin(Time.get_ticks_msec() / 1000.0 * 1.6) * 0.006
	_hand.position = _hand_base_pos + Vector3(sway, sway * 0.6, 0.0)
	_hand.rotation = Vector3(0.12, -0.22, 0.0)
	if phase >= 0.0:
		var arc := sin(phase * PI)
		_hand.rotation.x = 0.12 - arc * 0.85
		_hand.position += Vector3(0.0, -arc * 0.10, -arc * 0.18)


func _build_target_marking() -> void:
	# Wireframe cube outline (crosshair modes), built from line strips.
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var c := 0.53
	var corners: Array[Vector3] = []
	for x in [-c, c]:
		for y in [-c, c]:
			for z in [-c, c]:
				corners.append(Vector3(x, y, z))
	var edges := [[0, 1], [0, 2], [0, 4], [1, 3], [1, 5], [2, 3],
		[2, 6], [3, 7], [4, 5], [4, 6], [5, 7], [6, 7]]
	for edge in edges:
		mesh.surface_add_vertex(corners[edge[0]])
		mesh.surface_add_vertex(corners[edge[1]])
	mesh.surface_end()
	var outline_mat := StandardMaterial3D.new()
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.albedo_color = Color(1, 1, 1, 0.9)
	outline_mat.no_depth_test = false
	_outline = MeshInstance3D.new()
	_outline.mesh = mesh
	_outline.material_override = outline_mat
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline.top_level = true
	_outline.visible = false
	add_child(_outline)
	# Translucent highlight cube (touch mode — the block brightens).
	var hi_mat := StandardMaterial3D.new()
	hi_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hi_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hi_mat.albedo_color = Color(1, 1, 1, 0.16)
	var hi_mesh := BoxMesh.new()
	hi_mesh.size = Vector3(1.03, 1.03, 1.03)
	hi_mesh.material = hi_mat
	_highlight = MeshInstance3D.new()
	_highlight.mesh = hi_mesh
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.top_level = true
	_highlight.visible = false
	add_child(_highlight)


## Minecraft's target marking, styled by the Interface setting:
## touch play highlights the block; crosshair play outlines it.
func _update_target_marking() -> void:
	if _outline == null or terrain == null or _camera == null:
		return
	var style := str(Game.settings.get("target_marking", "auto"))
	if style == "off":
		_outline.visible = false
		_highlight.visible = false
		return
	var cell := Vector3i.ZERO
	var have := false
	var touch_context := _touch_mode
	if _touch_mining and _mine_cell_valid:
		cell = _mine_cell
		have = true
	elif not _touch_mode:
		if _tool == null:
			_tool = terrain.get_voxel_tool()
			_tool.channel = VoxelBuffer.CHANNEL_TYPE
		var hit := _tool.raycast(_camera.global_position,
			-_camera.global_transform.basis.z, REACH)
		if hit != null:
			var id: int = _tool.get_voxel(hit.position)
			if id != Blocks.AIR and id != Blocks.WATER:
				cell = hit.position
				have = true
	if not have:
		_outline.visible = false
		_highlight.visible = false
		return
	var use_highlight := style == "highlight" or (style == "auto" and touch_context)
	var center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	_outline.visible = not use_highlight
	_highlight.visible = use_highlight
	if use_highlight:
		_highlight.global_position = center
	else:
		_outline.global_position = center


func _make_particle_node(amount: int, lifetime: float, one_shot: bool,
		explosiveness: float, velocity_min: float, velocity_max: float,
		gravity: float, fragment: float) -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.amount = amount
	node.lifetime = lifetime
	node.one_shot = one_shot
	node.explosiveness = explosiveness
	node.local_coords = false
	node.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 60.0
	proc.initial_velocity_min = velocity_min
	proc.initial_velocity_max = velocity_max
	proc.gravity = Vector3(0, gravity, 0)
	proc.scale_min = 0.7
	proc.scale_max = 1.4
	node.process_material = proc
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(fragment, fragment, fragment)
	mesh.material = mat
	node.draw_pass_1 = mesh
	node.emitting = false
	node.top_level = true
	add_child(node)
	return node


func _build_particles() -> void:
	_crack_particles = _make_particle_node(18, 0.38, false, 0.0, 0.7, 1.6, -5.0, 0.05)
	_crack_particle_mat = (_crack_particles.draw_pass_1 as BoxMesh).material as StandardMaterial3D
	_burst_particles = _make_particle_node(30, 0.55, true, 0.88, 1.8, 3.4, -9.8, 0.06)
	_burst_particle_mat = (_burst_particles.draw_pass_1 as BoxMesh).material as StandardMaterial3D


func _burst_at(cell: Vector3i, block_id: int) -> void:
	if _burst_particles == null:
		return
	_burst_particle_mat.albedo_color = Blocks.block_color(block_id)
	_burst_particles.global_position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	_burst_particles.restart()


## Decorative drops (issue #15, Wade's option A): the mined block
## pops out as a small spinning cube, bounces, then flies to the
## player and vanishes with a pop. Purely visual — the hotbar stays
## unlimited; Phase 3 survival turns this into a real inventory.
func _spawn_drop(block_id: int, cell: Vector3i) -> void:
	if _drops.size() >= MAX_DROPS:
		var old: Dictionary = _drops.pop_front()
		(old["node"] as Node).queue_free()
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.32, 0.32, 0.32)
	mesh.material = _tile_material(block_id)
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.top_level = true
	add_child(node)
	node.global_position = Vector3(cell) + Vector3(0.5, 0.6, 0.5)
	var vel := Vector3(randf_range(-1.1, 1.1), 3.6, randf_range(-1.1, 1.1))
	_drops.append({"node": node, "vel": vel, "age": 0.0, "flying": false})


func _update_drops(delta: float) -> void:
	if _drops.is_empty():
		return
	var chest := global_position + Vector3(0, 1.0, 0)
	for i in range(_drops.size() - 1, -1, -1):
		var drop: Dictionary = _drops[i]
		var node := drop["node"] as MeshInstance3D
		drop["age"] = float(drop["age"]) + delta
		node.rotation.y += 2.6 * delta
		if bool(drop["flying"]):
			var to_player := chest - node.global_position
			if to_player.length() < 0.45:
				Game.play_sfx("pop", randf_range(0.95, 1.08))
				node.queue_free()
				_drops.remove_at(i)
				continue
			node.global_position += to_player.normalized() * 11.0 * delta
			continue
		if float(drop["age"]) > 0.55 and node.global_position.distance_to(chest) < 2.8:
			drop["flying"] = true
			continue
		var vel := drop["vel"] as Vector3
		vel.y -= 16.0 * delta
		var pos := node.global_position + vel * delta
		var probe_point := pos + Vector3(0, -0.22, 0)
		var below := _voxel_at(probe_point)
		if below != Blocks.AIR and below != Blocks.WATER and vel.y < 0.0:
			# Rest on top of the solid cell the probe point is inside.
			pos.y = floori(probe_point.y) + 1.0 + 0.18
			vel.y = -vel.y * 0.35 if vel.y < -1.6 else 0.0
			vel.x *= 0.7
			vel.z *= 0.7
		node.global_position = pos
		drop["vel"] = vel


## Progress through the current block's break time, for the touch
## progress ring (touch_controls.gd). 0 when not mining.
func mining_fraction() -> float:
	if not _mine_cell_valid:
		return 0.0
	if _tool == null or terrain == null:
		return 0.0
	var id: int = _tool.get_voxel(_mine_cell)
	var needed := Blocks.break_seconds(id)
	if needed <= 0.0:
		return 0.0
	return clampf(_mine_progress / needed, 0.0, 1.0)


func _show_crack(cell: Vector3i, stage: int) -> void:
	if _crack == null or _crack_material == null:
		return
	var clamped_stage := clampi(stage, 0, 9)
	if clamped_stage != _crack_stage:
		_crack_stage = clamped_stage
		_crack_material.albedo_texture = _crack_textures[clamped_stage]
	_crack.global_position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	_crack.visible = true


func _hide_crack() -> void:
	if _crack != null:
		_crack.visible = false
	_crack_stage = -1


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
		var mined_id: int = _tool.get_voxel(hit.position)
		_tool.set_voxel(hit.position, Blocks.AIR)
		Game.play_block_sfx("break", mined_id)
		_burst_at(hit.position, mined_id)
		_spawn_drop(mined_id, hit.position)
	else:
		var cell: Vector3i = hit.previous_position
		# Never place a block inside the player's own body.
		var player_box := AABB(global_position - Vector3(0.35, 0.0, 0.35), Vector3(0.7, 1.8, 0.7))
		var cell_box := AABB(Vector3(cell), Vector3.ONE)
		if player_box.intersects(cell_box):
			return
		_tool.set_voxel(cell, selected_block())
		Game.play_block_sfx("place", selected_block())
		_place_swing_t = 0.0
