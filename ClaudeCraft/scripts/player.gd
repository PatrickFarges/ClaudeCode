extends CharacterBody3D

# Paramètres de mouvement
@export var speed: float = 5.0
@export var jump_velocity: float = 5.5
@export var mouse_sensitivity: float = 0.002
@export var reach_distance: float = 5.0
@export var max_step_height: float = 0.6

# Références
@onready var camera: Camera3D = $Camera3D
@onready var raycast: RayCast3D = $Camera3D/RayCast3D

# Variables de mouvement
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var world_manager: WorldManager
var jump_boost: float = 1.0

# ============================================================
# INVENTAIRE
# ============================================================
var inventory: Dictionary = {}
var hotbar_slots: Array = [
	BlockRegistry.BlockType.DIRT,
	BlockRegistry.BlockType.GRASS,
	BlockRegistry.BlockType.STONE,
	BlockRegistry.BlockType.SAND,
	BlockRegistry.BlockType.WOOD,
	BlockRegistry.BlockType.PLANKS,
	BlockRegistry.BlockType.BRICK,
	BlockRegistry.BlockType.SANDSTONE,
	BlockRegistry.BlockType.CRAFTING_TABLE
]
var selected_slot: int = 0
var selected_block_type: BlockRegistry.BlockType = BlockRegistry.BlockType.DIRT

# État des UIs
var inventory_open: bool = false
var crafting_open: bool = false
var inventory_ui = null
var crafting_ui = null

# ============================================================
# SYSTÈME DE MINAGE
# ============================================================
var is_mining: bool = false
var mining_progress: float = 0.0
var mining_block_pos: Vector3 = Vector3.ZERO
var mining_block_type: BlockRegistry.BlockType = BlockRegistry.BlockType.AIR
var mining_time_required: float = 1.0

var block_highlighter: BlockHighlighter = null

# Détection table de craft
const TABLE_DETECT_RANGE = 4.0

# Audio
var audio_manager: AudioManager = null
var footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL = 0.4  # Secondes entre chaque pas
var mining_hit_timer: float = 0.0
const MINING_HIT_INTERVAL = 0.25  # Secondes entre chaque frappe

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world_manager = get_tree().get_first_node_in_group("world_manager")
	
	if raycast:
		raycast.target_position = Vector3(0, 0, -reach_distance)
		raycast.enabled = true
	
	add_to_group("player")
	_update_selected_block()
	_init_inventory()
	_create_block_highlighter()
	
	await get_tree().process_frame
	inventory_ui = get_tree().get_first_node_in_group("inventory_ui")
	crafting_ui = get_tree().get_first_node_in_group("crafting_ui")
	audio_manager = get_tree().get_first_node_in_group("audio_manager")

func _init_inventory():
	inventory[BlockRegistry.BlockType.DIRT] = 32
	inventory[BlockRegistry.BlockType.GRASS] = 0
	inventory[BlockRegistry.BlockType.STONE] = 16
	inventory[BlockRegistry.BlockType.SAND] = 0
	inventory[BlockRegistry.BlockType.WOOD] = 16
	inventory[BlockRegistry.BlockType.LEAVES] = 0
	inventory[BlockRegistry.BlockType.SNOW] = 0
	inventory[BlockRegistry.BlockType.GRAVEL] = 0
	inventory[BlockRegistry.BlockType.CACTUS] = 0
	inventory[BlockRegistry.BlockType.DARK_GRASS] = 0
	inventory[BlockRegistry.BlockType.PLANKS] = 0
	inventory[BlockRegistry.BlockType.CRAFTING_TABLE] = 0
	inventory[BlockRegistry.BlockType.BRICK] = 0
	inventory[BlockRegistry.BlockType.SANDSTONE] = 0

func _create_block_highlighter():
	block_highlighter = BlockHighlighter.new()
	get_tree().root.call_deferred("add_child", block_highlighter)

func get_inventory_count(block_type: BlockRegistry.BlockType) -> int:
	if inventory.has(block_type):
		return inventory[block_type]
	return 0

func get_all_inventory() -> Dictionary:
	return inventory

func _add_to_inventory(block_type: BlockRegistry.BlockType, count: int = 1):
	if inventory.has(block_type):
		inventory[block_type] += count
	else:
		inventory[block_type] = count

func _remove_from_inventory(block_type: BlockRegistry.BlockType, count: int = 1) -> bool:
	if not inventory.has(block_type) or inventory[block_type] < count:
		return false
	inventory[block_type] -= count
	return true

func assign_hotbar_slot(slot_index: int, block_type: BlockRegistry.BlockType):
	if slot_index >= 0 and slot_index < hotbar_slots.size():
		hotbar_slots[slot_index] = block_type
		if slot_index == selected_slot:
			_update_selected_block()

func _is_any_ui_open() -> bool:
	return inventory_open or crafting_open

func _close_all_ui():
	if inventory_open:
		_toggle_inventory()
	if crafting_open:
		_toggle_crafting()

# ============================================================
# INVENTAIRE TOGGLE
# ============================================================
func _toggle_inventory():
	if crafting_open:
		_toggle_crafting()  # Fermer le craft d'abord
	
	inventory_open = not inventory_open
	if inventory_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if inventory_ui:
			inventory_ui.visible = true
			inventory_ui.open_inventory()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if inventory_ui:
			inventory_ui.visible = false
			inventory_ui.close_inventory()

# ============================================================
# CRAFTING TOGGLE
# ============================================================
func _toggle_crafting():
	if inventory_open:
		_toggle_inventory()  # Fermer l'inventaire d'abord
	
	crafting_open = not crafting_open
	if crafting_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var near_table = _is_near_crafting_table()
		if crafting_ui:
			crafting_ui.visible = true
			crafting_ui.open_crafting(near_table)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if crafting_ui:
			crafting_ui.visible = false
			crafting_ui.close_crafting()

func _is_near_crafting_table() -> bool:
	"""Vérifier s'il y a une table de craft à proximité"""
	if not world_manager:
		return false
	
	var pos = global_position
	var check_range = TABLE_DETECT_RANGE
	
	# Scanner les blocs autour du joueur
	for dx in range(-int(check_range), int(check_range) + 1):
		for dy in range(-2, 3):
			for dz in range(-int(check_range), int(check_range) + 1):
				var check_pos = Vector3(floor(pos.x) + dx, floor(pos.y) + dy, floor(pos.z) + dz)
				var block = world_manager.get_block_at_position(check_pos)
				if block == BlockRegistry.BlockType.CRAFTING_TABLE:
					return true
	return false

func _input(event):
	# Touche E — inventaire
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			_toggle_inventory()
			return
		# Touche C — crafting
		if event.physical_keycode == KEY_C:
			_toggle_crafting()
			return
	
	# Si une UI est ouverte, Echap la ferme
	if _is_any_ui_open():
		if event.is_action_pressed("ui_cancel"):
			_close_all_ui()
		return
	
	# Rotation de la caméra
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)
	
	# Échap souris
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Slots 1-5
	for i in range(5):
		if event.is_action_pressed("slot_%d" % (i + 1)):
			selected_slot = i
			_update_selected_block()
	
	# Slots 6-9
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_6:
				selected_slot = 5
				_update_selected_block()
			KEY_7:
				selected_slot = 6
				_update_selected_block()
			KEY_8:
				selected_slot = 7
				_update_selected_block()
			KEY_9:
				selected_slot = 8
				_update_selected_block()
	
	# Molette souris
	if event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			selected_slot = (selected_slot - 1 + hotbar_slots.size()) % hotbar_slots.size()
			_update_selected_block()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			selected_slot = (selected_slot + 1) % hotbar_slots.size()
			_update_selected_block()

func _physics_process(delta):
	# Gravité toujours active
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Pas de mouvement si UI ouverte
	if _is_any_ui_open():
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		move_and_slide()
		return
	
	# Saut
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity * jump_boost
	
	# Mouvement
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	
	_handle_auto_step(direction)
	move_and_slide()
	_handle_block_interaction(delta)
	_handle_footsteps(delta, direction)

func _handle_auto_step(direction: Vector3):
	if not is_on_floor() or direction.length() == 0:
		return
	var test_position = global_position + direction * 0.5
	var test_position_high = test_position + Vector3(0, max_step_height, 0)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		test_position_high,
		test_position_high + Vector3(0, -max_step_height - 0.1, 0)
	)
	var result = space_state.intersect_ray(query)
	if result and result.position.y > global_position.y and result.position.y <= global_position.y + max_step_height:
		global_position.y += result.position.y - global_position.y + 0.1

func _handle_footsteps(delta: float, direction: Vector3):
	"""Jouer des sons de pas quand on marche"""
	if not audio_manager or not is_on_floor() or direction.length() == 0:
		footstep_timer = 0.0
		return
	
	footstep_timer += delta
	if footstep_timer >= FOOTSTEP_INTERVAL:
		footstep_timer = 0.0
		# Détecter le type de surface sous les pieds
		var foot_pos = global_position - Vector3(0, 0.1, 0)
		var surface_block = BlockRegistry.BlockType.STONE
		if world_manager:
			surface_block = world_manager.get_block_at_position(foot_pos.floor())
			if surface_block == BlockRegistry.BlockType.AIR:
				# Essayer un bloc plus bas
				surface_block = world_manager.get_block_at_position((foot_pos - Vector3(0, 1, 0)).floor())
		audio_manager.play_footstep(surface_block)

func _handle_block_interaction(delta: float):
	if not world_manager or not raycast:
		return
	
	raycast.force_raycast_update()
	
	if not raycast.is_colliding():
		_cancel_mining()
		if block_highlighter:
			block_highlighter.hide_highlight()
		return
	
	var collision_point = raycast.get_collision_point()
	var normal = raycast.get_collision_normal()
	var break_pos = (collision_point - normal * 0.5).floor()
	var place_pos = (collision_point + normal * 0.5).floor()
	
	var break_block_type = world_manager.get_block_at_position(break_pos)
	var can_break = break_block_type != BlockRegistry.BlockType.AIR and BlockRegistry.is_solid(break_block_type)
	
	# Highlighter
	if block_highlighter and can_break:
		block_highlighter.update_position(break_pos, true, Color(1, 1, 1, 0.6))
	elif block_highlighter:
		block_highlighter.hide_highlight()
	
	# Minage progressif
	if Input.is_action_pressed("break_block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and can_break:
		if is_mining and break_pos != mining_block_pos:
			_cancel_mining()
		
		if not is_mining:
			is_mining = true
			mining_progress = 0.0
			mining_block_pos = break_pos
			mining_block_type = break_block_type
			mining_time_required = BlockRegistry.get_block_hardness(break_block_type)
			if mining_time_required <= 0:
				mining_time_required = 0.1
		
		mining_progress += delta / mining_time_required
		
		# Son de frappe périodique
		mining_hit_timer += delta
		if mining_hit_timer >= MINING_HIT_INTERVAL and audio_manager:
			mining_hit_timer = 0.0
			audio_manager.play_mining_hit(mining_block_type, mining_block_pos)
		
		if block_highlighter:
			block_highlighter.set_mining_progress(mining_progress)
		
		if mining_progress >= 1.0:
			_break_block(break_pos, break_block_type)
	else:
		if is_mining:
			_cancel_mining()
	
	# Placement
	if Input.is_action_just_pressed("place_block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var place_block_type = world_manager.get_block_at_position(place_pos)
		var player_aabb = AABB(global_position - Vector3(0.4, 0, 0.4), Vector3(0.8, 1.8, 0.8))
		var block_aabb = AABB(place_pos, Vector3.ONE)
		var can_place = place_block_type == BlockRegistry.BlockType.AIR and not player_aabb.intersects(block_aabb)
		
		if can_place and get_inventory_count(selected_block_type) > 0:
			world_manager.place_block_at_position(place_pos, selected_block_type)
			_remove_from_inventory(selected_block_type)
			if audio_manager:
				audio_manager.play_place_sound(selected_block_type, place_pos)

func _break_block(pos: Vector3, block_type: BlockRegistry.BlockType):
	world_manager.break_block_at_position(pos)
	_add_to_inventory(block_type)
	_spawn_break_particles(pos, block_type)
	if audio_manager:
		audio_manager.play_break_sound(block_type, pos)
	_cancel_mining()

func _cancel_mining():
	is_mining = false
	mining_progress = 0.0
	mining_block_pos = Vector3.ZERO
	mining_block_type = BlockRegistry.BlockType.AIR
	mining_hit_timer = 0.0
	if block_highlighter:
		block_highlighter.set_mining_progress(0.0)

func _spawn_break_particles(pos: Vector3, block_type: BlockRegistry.BlockType):
	var block_color = BlockRegistry.get_block_color(block_type)
	var center = pos + Vector3(0.5, 0.5, 0.5)
	var particles = CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 12
	particles.lifetime = 0.6
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(0.3, 0.3, 0.3)
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 4.0
	particles.gravity = Vector3(0, -12, 0)
	particles.scale_amount_min = 0.08
	particles.scale_amount_max = 0.15
	particles.color = block_color
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1, 1, 1)
	particles.mesh = box_mesh
	particles.emitting = false
	get_tree().root.add_child(particles)
	particles.global_position = center
	particles.restart()
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)

func _update_selected_block():
	if selected_slot >= 0 and selected_slot < hotbar_slots.size():
		selected_block_type = hotbar_slots[selected_slot]

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
