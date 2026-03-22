extends CharacterBody3D

const ArmorMgr = preload("res://scripts/armor_manager.gd")

# Paramètres de mouvement
@export var speed: float = 5.0
@export var sprint_speed: float = 8.5
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
var is_sprinting: bool = false
const SPRINT_FOV = 80.0
const NORMAL_FOV = 70.0
const FOV_LERP_SPEED = 8.0
const ZOOM_FOV_MIN = 70.0
const ZOOM_FOV_MAX = 110.0
const ZOOM_FOV_STEP = 5.0
var zoom_fov: float = 70.0

# ============================================================
# VUE CAMÉRA (F5)
# ============================================================
# 0 = 1ère personne, 1 = 3ème personne dos, 2 = 3ème personne face
var camera_mode: int = 0
const CAMERA_3RD_DISTANCE = 4.0
const CAMERA_3RD_HEIGHT = 1.8
const CAMERA_HEAD_Y = 1.6
var _cam_pitch: float = 0.0  # Pitch stocké pour la 3ème personne
var _player_model: Node3D = null
var _player_anim: AnimationPlayer = null
const STEVE_GLB = "res://assets/PlayerModel/steve.glb"
const STEVE_SKIN = "res://assets/PlayerModel/steve_skin.png"
static var _steve_packed: PackedScene = null
var _player_skeleton: Skeleton3D = null

# Armure equipee sur le joueur
var equipped_armor: Dictionary = {}  # piece_name -> material_name
const ARMOR_MATERIALS_CYCLE = ["", "leather", "chain", "iron", "gold", "diamond"]
var _armor_cycle_index: int = 0

# Boussole HUD
var _compass_label: Label = null

# Effet sous l'eau
var _water_overlay: ColorRect = null
var _water_canvas: CanvasLayer = null
var _was_in_water: bool = false
var _underwater_player: AudioStreamPlayer = null
var _swim_timer: float = 0.0
const SWIM_SOUND_INTERVAL = 0.8
var _drown_timer: float = 0.0
const DROWN_TIME = 15.0  # secondes avant de commencer a se noyer
const DROWN_DAMAGE_INTERVAL = 1.0
var _drown_damage_timer: float = 0.0
var _air_supply: float = 15.0  # secondes d'air restantes

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
var village_inv_open: bool = false
var inventory_ui = null
var crafting_ui = null
var village_inventory_ui = null
var pause_menu = null

# ============================================================
# SYSTÈME DE MINAGE
# ============================================================
var is_mining: bool = false
var mining_progress: float = 0.0
var mining_block_pos: Vector3 = Vector3.ZERO
var mining_block_type: BlockRegistry.BlockType = BlockRegistry.BlockType.AIR
var mining_time_required: float = 1.0

var block_highlighter: BlockHighlighter = null
var look_block_type: BlockRegistry.BlockType = BlockRegistry.BlockType.AIR


# ============================================================
# SYSTÈME DE VIE
# ============================================================
var max_health: int = 20
var current_health: int = 20
var _fall_start_y: float = 0.0
var _was_on_floor: bool = true
var damage_cooldown: float = 0.0
const DAMAGE_COOLDOWN_TIME = 0.5
const FALL_DAMAGE_THRESHOLD = 4.0  # Blocs de chute avant dégâts
const FALL_DAMAGE_MULTIPLIER = 1.0  # Dégâts par bloc au-delà du seuil
const CACTUS_DAMAGE = 1
const MELEE_RANGE = 3.5
const MELEE_COOLDOWN_TIME = 0.5
const MELEE_KNOCKBACK = 8.0
const MELEE_LIFT = 3.0
var melee_cooldown: float = 0.0
var is_dead: bool = false
var in_water: bool = false
var respawn_timer: float = 0.0
const RESPAWN_DELAY = 2.0
var spawn_position: Vector3 = Vector3(0, 80, 0)

# Audio
var audio_manager: AudioManager = null
var footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL = 0.4  # Secondes entre chaque pas
var mining_hit_timer: float = 0.0
const MINING_HIT_INTERVAL = 0.25  # Secondes entre chaque frappe

# Multiplicateur global du temps de minage
# temps = dureté_bloc × BASE_MINING_TIME / multiplicateur_outil
# Ex: tronc (dureté 1.0) × 10.0 / 1.0 (mains nues) = 10.0 secondes
# Modifier cette valeur pour accélérer/ralentir TOUT le minage
const BASE_MINING_TIME = 5.0

# Bras / Item en main
var hand_renderer = null
const HandItemRendererScript = preload("res://scripts/hand_item_renderer.gd")

# Outils — slots parallèles à la hotbar (NONE = bloc, sinon outil)
var hotbar_tool_slots: Array = []

# Nourriture — slots parallèles (true = ce slot contient de la nourriture)
var hotbar_food_slots: Array = []
const APPLE_MODEL_PATH = "res://assets/Deco/apple.glb"
const ArrowEntityScript = preload("res://scripts/arrow_entity.gd")

# ============================================================
# SYSTÈME D'ARC
# ============================================================
var is_drawing_bow: bool = false
var bow_charge_time: float = 0.0
const BOW_MAX_CHARGE: float = 1.0  # Secondes pour charge max (MC: 1s = 20 ticks)
const BOW_ARROW_OFFSET = Vector3(0, 1.5, 0)  # Hauteur des yeux

# ============================================================
# SYSTÈME DE NOURRITURE
# ============================================================
var is_eating: bool = false
var eating_progress: float = 0.0
const EATING_TIME: float = 2.0
var eating_particle_timer: float = 0.0
const EATING_PARTICLE_INTERVAL: float = 0.3
var eating_sound_timer: float = 0.0
const EATING_SOUND_INTERVAL: float = 0.5
const EATING_HEAL_AMOUNT: int = 4

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world_manager = get_tree().get_first_node_in_group("world_manager")
	
	if raycast:
		raycast.target_position = Vector3(0, 0, -reach_distance)
		raycast.enabled = true
	
	add_to_group("player")
	spawn_position = global_position
	_init_tool_slots()
	_init_inventory()
	_create_block_highlighter()
	_create_hand_renderer()
	_update_selected_block()
	# Modèle 3e personne chargé en différé
	call_deferred("_create_player_model")
	_create_compass()
	_create_water_overlay()
	
	await get_tree().process_frame
	inventory_ui = get_tree().get_first_node_in_group("inventory_ui")
	crafting_ui = get_tree().get_first_node_in_group("crafting_ui")
	village_inventory_ui = get_tree().get_first_node_in_group("village_inventory_ui")
	audio_manager = get_tree().get_first_node_in_group("audio_manager")
	pause_menu = get_tree().get_first_node_in_group("pause_menu")

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
	inventory[BlockRegistry.BlockType.COAL_ORE] = 0
	inventory[BlockRegistry.BlockType.IRON_ORE] = 0
	inventory[BlockRegistry.BlockType.GOLD_ORE] = 0
	inventory[BlockRegistry.BlockType.IRON_INGOT] = 0
	inventory[BlockRegistry.BlockType.GOLD_INGOT] = 0
	inventory[BlockRegistry.BlockType.FURNACE] = 0
	inventory[BlockRegistry.BlockType.STONE_TABLE] = 0
	inventory[BlockRegistry.BlockType.IRON_TABLE] = 0
	inventory[BlockRegistry.BlockType.GOLD_TABLE] = 0
	# Nouveaux blocs
	inventory[BlockRegistry.BlockType.COBBLESTONE] = 0
	inventory[BlockRegistry.BlockType.MOSSY_COBBLESTONE] = 0
	inventory[BlockRegistry.BlockType.ANDESITE] = 0
	inventory[BlockRegistry.BlockType.GRANITE] = 0
	inventory[BlockRegistry.BlockType.DIORITE] = 0
	inventory[BlockRegistry.BlockType.DEEPSLATE] = 0
	inventory[BlockRegistry.BlockType.SMOOTH_STONE] = 0
	inventory[BlockRegistry.BlockType.SPRUCE_LOG] = 0
	inventory[BlockRegistry.BlockType.BIRCH_LOG] = 0
	inventory[BlockRegistry.BlockType.JUNGLE_LOG] = 0
	inventory[BlockRegistry.BlockType.ACACIA_LOG] = 0
	inventory[BlockRegistry.BlockType.DARK_OAK_LOG] = 0
	inventory[BlockRegistry.BlockType.SPRUCE_PLANKS] = 0
	inventory[BlockRegistry.BlockType.BIRCH_PLANKS] = 0
	inventory[BlockRegistry.BlockType.JUNGLE_PLANKS] = 0
	inventory[BlockRegistry.BlockType.ACACIA_PLANKS] = 0
	inventory[BlockRegistry.BlockType.DARK_OAK_PLANKS] = 0
	inventory[BlockRegistry.BlockType.CHERRY_LOG] = 0
	inventory[BlockRegistry.BlockType.CHERRY_PLANKS] = 0
	inventory[BlockRegistry.BlockType.SPRUCE_LEAVES] = 0
	inventory[BlockRegistry.BlockType.BIRCH_LEAVES] = 0
	inventory[BlockRegistry.BlockType.JUNGLE_LEAVES] = 0
	inventory[BlockRegistry.BlockType.ACACIA_LEAVES] = 0
	inventory[BlockRegistry.BlockType.DARK_OAK_LEAVES] = 0
	inventory[BlockRegistry.BlockType.CHERRY_LEAVES] = 0
	inventory[BlockRegistry.BlockType.DIAMOND_ORE] = 0
	inventory[BlockRegistry.BlockType.COPPER_ORE] = 0
	inventory[BlockRegistry.BlockType.DIAMOND_BLOCK] = 0
	inventory[BlockRegistry.BlockType.COPPER_BLOCK] = 0
	inventory[BlockRegistry.BlockType.COPPER_INGOT] = 0
	inventory[BlockRegistry.BlockType.COAL_BLOCK] = 0
	inventory[BlockRegistry.BlockType.CLAY] = 0
	inventory[BlockRegistry.BlockType.PODZOL] = 0
	inventory[BlockRegistry.BlockType.ICE] = 0
	inventory[BlockRegistry.BlockType.PACKED_ICE] = 0
	inventory[BlockRegistry.BlockType.MOSS_BLOCK] = 0
	inventory[BlockRegistry.BlockType.GLASS] = 0
	inventory[BlockRegistry.BlockType.BOOKSHELF] = 0
	inventory[BlockRegistry.BlockType.HAY_BLOCK] = 0
	inventory[BlockRegistry.BlockType.BARREL] = 0
	# Végétation décorative
	inventory[BlockRegistry.BlockType.SHORT_GRASS] = 0
	inventory[BlockRegistry.BlockType.FERN] = 0
	inventory[BlockRegistry.BlockType.DEAD_BUSH] = 0
	inventory[BlockRegistry.BlockType.DANDELION] = 0
	inventory[BlockRegistry.BlockType.POPPY] = 0
	inventory[BlockRegistry.BlockType.CORNFLOWER] = 0
	# Blocs architecturaux
	inventory[BlockRegistry.BlockType.STONE_BRICKS] = 0
	inventory[BlockRegistry.BlockType.OAK_STAIRS] = 0
	inventory[BlockRegistry.BlockType.COBBLESTONE_STAIRS] = 0
	inventory[BlockRegistry.BlockType.STONE_BRICK_STAIRS] = 0
	inventory[BlockRegistry.BlockType.OAK_SLAB] = 0
	inventory[BlockRegistry.BlockType.COBBLESTONE_SLAB] = 0
	inventory[BlockRegistry.BlockType.STONE_SLAB] = 0
	inventory[BlockRegistry.BlockType.OAK_DOOR] = 0
	inventory[BlockRegistry.BlockType.OAK_FENCE] = 0
	inventory[BlockRegistry.BlockType.GLASS_PANE] = 0
	inventory[BlockRegistry.BlockType.LADDER] = 0
	inventory[BlockRegistry.BlockType.OAK_TRAPDOOR] = 0
	inventory[BlockRegistry.BlockType.IRON_DOOR] = 0
	inventory[BlockRegistry.BlockType.LANTERN] = 0
	inventory[BlockRegistry.BlockType.IRON_BARS] = 0
	inventory[BlockRegistry.BlockType.OAK_DOOR] = 2  # TEST TEMPORAIRE — supprimer après test
	inventory[BlockRegistry.BlockType.IRON_DOOR] = 1  # TEST TEMPORAIRE — supprimer après test
	inventory[BlockRegistry.BlockType.GLASS_PANE] = 2  # TEST TEMPORAIRE — supprimer après test

func _create_block_highlighter():
	block_highlighter = BlockHighlighter.new()
	get_tree().root.call_deferred("add_child", block_highlighter)

func _init_tool_slots():
	hotbar_tool_slots.clear()
	hotbar_food_slots.clear()
	for i in range(hotbar_slots.size()):
		hotbar_tool_slots.append(ToolRegistry.ToolType.NONE)
		hotbar_food_slots.append(false)
	# Outils sur les slots du milieu — 4 tiers de haches pour tester le minage
	hotbar_tool_slots[3] = ToolRegistry.ToolType.WOOD_AXE       # 6s sur tronc
	hotbar_tool_slots[4] = ToolRegistry.ToolType.STONE_AXE      # 5s sur tronc
	hotbar_tool_slots[5] = ToolRegistry.ToolType.IRON_AXE       # 4s sur tronc
	hotbar_tool_slots[6] = ToolRegistry.ToolType.DIAMOND_AXE    # 3s sur tronc
	hotbar_tool_slots[7] = ToolRegistry.ToolType.DIAMOND_PICKAXE
	hotbar_tool_slots[8] = ToolRegistry.ToolType.BOW
	# Pas de slot nourriture dans la hotbar actuelle

func _create_hand_renderer():
	hand_renderer = HandItemRendererScript.new()
	hand_renderer.name = "HandItemRenderer"
	camera.add_child(hand_renderer)
	# Activer le layer 2 sur la caméra pour voir le bras
	camera.cull_mask = camera.cull_mask | 2

func _create_player_model():
	# Charger le modèle Steve pour la vue 3ème personne (même pattern que NPC)
	if not _steve_packed:
		_steve_packed = load(STEVE_GLB) as PackedScene
		if not _steve_packed:
			var gltf_doc = GLTFDocument.new()
			var gltf_state = GLTFState.new()
			if gltf_doc.append_from_file(STEVE_GLB, gltf_state) == OK:
				var scene_root = gltf_doc.generate_scene(gltf_state)
				if scene_root:
					var packed = PackedScene.new()
					packed.pack(scene_root)
					_steve_packed = packed
					scene_root.queue_free()
	if not _steve_packed:
		print("Player: IMPOSSIBLE de charger steve.glb pour vue 3e personne")
		return
	_player_model = _steve_packed.instantiate()
	_player_model.scale = Vector3(0.85, 0.85, 0.85)
	_player_model.visible = false  # Caché en 1ère personne
	add_child(_player_model)
	# Appliquer le skin Steve (même méthode que npc_villager.gd)
	_apply_steve_skin()
	# Trouver l'AnimationPlayer
	_player_anim = _find_anim_player(_player_model)
	if _player_anim:
		_player_anim.deterministic = true
		print("Player: modèle 3e personne prêt (%d anims)" % _player_anim.get_animation_list().size())
	# Trouver le skeleton pour le systeme d'armure
	_player_skeleton = _find_skeleton(_player_model)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found:
			return found
	return null

func equip_armor_set(armor_material: String) -> void:
	if not _player_skeleton:
		return
	if armor_material.is_empty():
		ArmorMgr.unequip_all(_player_skeleton)
		equipped_armor.clear()
		print("Player: armure retirée")
	else:
		ArmorMgr.equip_set(_player_skeleton, armor_material)
		for piece in ["helmet", "chestplate", "leggings", "boots"]:
			equipped_armor[piece] = armor_material
		print("Player: armure %s équipée" % armor_material)

func equip_armor_piece(piece_name: String, armor_material: String) -> void:
	if not _player_skeleton:
		return
	if armor_material.is_empty():
		ArmorMgr.unequip(_player_skeleton, piece_name)
		equipped_armor.erase(piece_name)
	else:
		ArmorMgr.equip(_player_skeleton, piece_name, armor_material)
		equipped_armor[piece_name] = armor_material

func _apply_steve_skin():
	if not _player_model:
		return
	var skin_path = STEVE_SKIN
	if not FileAccess.file_exists(skin_path):
		return
	var img = Image.new()
	if img.load(skin_path) != OK:
		return
	var tex = ImageTexture.create_from_image(img)
	# Même méthode que npc_villager.gd : dupliquer le matériau du mesh et remplacer la texture
	_apply_skin_recursive(_player_model, tex)

func _apply_skin_recursive(node: Node, tex: Texture2D):
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				var base_mat = mi.mesh.surface_get_material(i)
				if base_mat is StandardMaterial3D:
					var mat = base_mat.duplicate() as StandardMaterial3D
					mat.albedo_texture = tex
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_skin_recursive(child, tex)

func _find_anim_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var found = _find_anim_player(child)
		if found:
			return found
	return null

func _cycle_camera_mode():
	camera_mode = (camera_mode + 1) % 3
	var mode_names = ["1ère personne", "3ème personne (dos)", "3ème personne (face)"]
	print("Caméra: %s" % mode_names[camera_mode])
	match camera_mode:
		0:  # 1ère personne
			camera.position = Vector3(0, CAMERA_HEAD_Y, 0)
			camera.rotation.x = _cam_pitch
			camera.rotation.y = 0
			camera.rotation.z = 0
			if _player_model:
				_player_model.visible = false
			if hand_renderer:
				hand_renderer.visible = true
		1:  # 3ème personne dos
			if _player_model:
				_player_model.visible = true
			if hand_renderer:
				hand_renderer.visible = false
		2:  # 3ème personne face
			if _player_model:
				_player_model.visible = true
			if hand_renderer:
				hand_renderer.visible = false

func _update_third_person_camera():
	if camera_mode == 0:
		return
	# En Godot, -Z = devant le joueur, +Z = derrière
	var sign_z = -1.0 if camera_mode == 2 else 1.0
	# Position caméra basée sur le pitch stocké
	var cam_y = CAMERA_HEAD_Y + CAMERA_3RD_DISTANCE * sin(-_cam_pitch) + 0.3
	var cam_z = sign_z * CAMERA_3RD_DISTANCE * cos(_cam_pitch)
	var target_pos = Vector3(0, cam_y, cam_z)
	# Empêcher la caméra de passer sous le terrain
	var cam_world = global_position + transform.basis * target_pos
	if world_manager:
		var ground_y = global_position.y  # fallback
		var check_pos = cam_world.floor()
		var block_at_cam = world_manager.get_block_at_position(check_pos)
		if block_at_cam != BlockRegistry.BlockType.AIR and block_at_cam != BlockRegistry.BlockType.WATER:
			# La caméra est dans un bloc solide — remonter au-dessus
			target_pos.y = maxf(target_pos.y, CAMERA_HEAD_Y + 0.5)
			cam_world = global_position + transform.basis * target_pos

	# Collision caméra — raycast du joueur vers la position caméra cible
	var space = get_world_3d().direct_space_state
	var head_world = global_position + Vector3(0, CAMERA_HEAD_Y, 0)
	var query = PhysicsRayQueryParameters3D.create(head_world, cam_world)
	query.exclude = [get_rid()]
	var result = space.intersect_ray(query)
	if result:
		var hit_dist = head_world.distance_to(result.position) - 0.3
		var full_dist = head_world.distance_to(cam_world)
		if full_dist > 0.01 and hit_dist < full_dist:
			target_pos = target_pos * maxf(0.3, hit_dist / full_dist)
	camera.position = target_pos
	# Orienter la caméra
	if camera_mode == 2:
		# Vue face : regarder la tête du joueur
		var look_world = global_position + Vector3(0, CAMERA_HEAD_Y, 0)
		if cam_world.distance_to(look_world) > 0.1:
			camera.look_at(look_world, Vector3.UP)
	else:
		# Vue dos : regarder devant le joueur
		var forward_world = global_position + transform.basis * Vector3(0, CAMERA_HEAD_Y + CAMERA_3RD_DISTANCE * sin(-_cam_pitch), -10.0)
		camera.look_at(forward_world, Vector3.UP)

func _update_player_model_anim():
	if not _player_model or not _player_anim or camera_mode == 0:
		return
	var hvel = Vector2(velocity.x, velocity.z).length()
	if hvel > 1.0:
		if _player_anim.current_animation != "walk":
			_player_anim.play("walk")
	else:
		if _player_anim.current_animation != "idle":
			_player_anim.play("idle")

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
		# Retirer l'outil et la nourriture du slot remplacé
		if slot_index < hotbar_tool_slots.size():
			hotbar_tool_slots[slot_index] = ToolRegistry.ToolType.NONE
		if slot_index < hotbar_food_slots.size():
			hotbar_food_slots[slot_index] = false
		if slot_index == selected_slot:
			_update_selected_block()

func _is_any_ui_open() -> bool:
	return inventory_open or crafting_open or (pause_menu and pause_menu.is_open)

func _close_all_ui():
	if inventory_open:
		_toggle_inventory()
	if crafting_open:
		_toggle_crafting()
	if village_inv_open:
		_toggle_village_inventory()

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
func _toggle_crafting(tier: int = 0, furnace: bool = false):
	if inventory_open:
		_toggle_inventory()  # Fermer l'inventaire d'abord

	crafting_open = not crafting_open
	if crafting_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if crafting_ui:
			crafting_ui.visible = true
			crafting_ui.open_crafting(tier, furnace)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if crafting_ui:
			crafting_ui.visible = false
			crafting_ui.close_crafting()

# ============================================================
# VILLAGE INVENTORY TOGGLE
# ============================================================
func _toggle_village_inventory():
	if inventory_open:
		_toggle_inventory()
	if crafting_open:
		_toggle_crafting()

	village_inv_open = not village_inv_open
	if village_inv_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if village_inventory_ui:
			village_inventory_ui.open_inventory()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if village_inventory_ui:
			village_inventory_ui.close_inventory()

func _get_interact_tier(block_type) -> int:
	"""Retourne le tier de craft pour un bloc interactif, ou -1 si pas interactif"""
	match block_type:
		BlockRegistry.BlockType.CRAFTING_TABLE: return 1
		BlockRegistry.BlockType.STONE_TABLE: return 2
		BlockRegistry.BlockType.IRON_TABLE: return 3
		BlockRegistry.BlockType.GOLD_TABLE: return 4
		BlockRegistry.BlockType.FURNACE: return 0  # tier 0 + furnace flag
		_: return -1

func _input(event):
	# Bloquer E/C si pause menu ouvert
	var pause_open = pause_menu and pause_menu.is_open

	# Touche I — inventaire (pas si pause)
	if event is InputEventKey and event.pressed and not event.echo and not pause_open:
		if event.physical_keycode == KEY_I:
			_toggle_inventory()
			return
		# Touche C — crafting (pas si pause)
		if event.physical_keycode == KEY_C:
			_toggle_crafting()
			return
		# Touche F1 — inventaire du village
		if event.physical_keycode == KEY_F1:
			_toggle_village_inventory()
			return
		# Touche F5 — cycle vue caméra (1ère/3ème dos/3ème face)
		if event.physical_keycode == KEY_F5:
			_cycle_camera_mode()
			return
		# Touche P — cycler armures (aucune → cuir → chaine → fer → or → diamant)
		if event.physical_keycode == KEY_P:
			_armor_cycle_index = (_armor_cycle_index + 1) % ARMOR_MATERIALS_CYCLE.size()
			equip_armor_set(ARMOR_MATERIALS_CYCLE[_armor_cycle_index])
			return

	# Gestion Escape : 3 cas
	if event.is_action_pressed("ui_cancel"):
		# Cas 1 : pause menu ouvert -> fermer pause
		if pause_open:
			pause_menu.close_pause()
			return
		# Cas 2 : inventaire/craft/village ouvert -> fermer UI
		if inventory_open or crafting_open or village_inv_open:
			_close_all_ui()
			return
		# Cas 3 : rien d'ouvert + souris capturée -> ouvrir pause
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if pause_menu:
				pause_menu.open_pause()
			return
		# Souris visible sans UI -> recapturer
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# Sélection de slot (1-9) — autorisé même quand inventaire/craft ouvert
	if not pause_open:
		for i in range(5):
			if event.is_action_pressed("slot_%d" % (i + 1)):
				selected_slot = i
				_update_selected_block()
				return
		if event is InputEventKey and event.pressed and not event.echo:
			match event.physical_keycode:
				KEY_6:
					selected_slot = 5
					_update_selected_block()
					return
				KEY_7:
					selected_slot = 6
					_update_selected_block()
					return
				KEY_8:
					selected_slot = 7
					_update_selected_block()
					return
				KEY_9:
					selected_slot = 8
					_update_selected_block()
					return

	# Si une UI est ouverte (inventaire/craft/pause), bloquer le reste
	if _is_any_ui_open():
		return

	# Rotation de la caméra
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if camera_mode == 0:
			camera.rotate_x(-event.relative.y * mouse_sensitivity)
			camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)
			_cam_pitch = camera.rotation.x
		elif camera_mode == 1:
			# Vue dos : pitch limité (légèrement au-dessus, pas sous terre)
			_cam_pitch = clamp(_cam_pitch - event.relative.y * mouse_sensitivity, -0.15, 0.5)
		else:
			# Vue face : pitch plus libre mais pas sous le sol
			_cam_pitch = clamp(_cam_pitch - event.relative.y * mouse_sensitivity, -0.3, PI/3)

	# Molette souris
	if event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Alt+Molette = zoom FOV
		if event.alt_pressed and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_fov = maxf(ZOOM_FOV_MIN, zoom_fov - ZOOM_FOV_STEP)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_fov = minf(ZOOM_FOV_MAX, zoom_fov + ZOOM_FOV_STEP)
				get_viewport().set_input_as_handled()
				return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			selected_slot = (selected_slot - 1 + hotbar_slots.size()) % hotbar_slots.size()
			_update_selected_block()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			selected_slot = (selected_slot + 1) % hotbar_slots.size()
			_update_selected_block()

func _create_compass():
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_compass_label = Label.new()
	_compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_label.anchor_left = 0.5
	_compass_label.anchor_right = 0.5
	_compass_label.anchor_top = 0.0
	_compass_label.anchor_bottom = 0.0
	_compass_label.offset_left = -200
	_compass_label.offset_right = 200
	_compass_label.offset_top = 8
	_compass_label.offset_bottom = 40
	_compass_label.add_theme_font_size_override("font_size", 18)
	_compass_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	_compass_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	_compass_label.add_theme_constant_override("shadow_offset_x", 1)
	_compass_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(_compass_label)

func _update_compass():
	if not _compass_label:
		return
	# Heading : rotation Y du joueur (radians → degres, 0=Nord/-Z)
	var yaw_deg = fmod(rad_to_deg(-rotation.y) + 360.0, 360.0)
	# Directions cardinales
	const DIRS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var idx = int(round(yaw_deg / 45.0)) % 8
	var cardinal = DIRS[idx]
	# Bande horizontale avec marqueurs
	var bar = ""
	for i in range(-3, 4):
		var angle = fmod(yaw_deg + i * 45.0 + 360.0, 360.0)
		var dir_idx = int(round(angle / 45.0)) % 8
		var d = DIRS[dir_idx]
		if i == 0:
			bar += "[ %s ]" % d
		else:
			bar += "  %s  " % d
	_compass_label.text = bar

func _create_water_overlay():
	_water_canvas = CanvasLayer.new()
	_water_canvas.layer = 5
	add_child(_water_canvas)
	_water_overlay = ColorRect.new()
	_water_overlay.color = Color(0.05, 0.15, 0.4, 0.45)
	_water_overlay.anchor_right = 1.0
	_water_overlay.anchor_bottom = 1.0
	_water_overlay.visible = false
	_water_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_canvas.add_child(_water_overlay)
	# Son ambiant sous-marin (loop)
	_underwater_player = AudioStreamPlayer.new()
	var water_snd = load("res://assets/Audio/Minecraft/liquid/water.mp3")
	if water_snd:
		_underwater_player.stream = water_snd
		_underwater_player.volume_db = -8.0
	add_child(_underwater_player)

func _update_underwater(delta: float):
	var head_underwater = false
	if world_manager:
		var head_pos = (global_position + Vector3(0, 1.5, 0)).floor()
		head_underwater = world_manager.get_block_at_position(head_pos) == BlockRegistry.BlockType.WATER

	if head_underwater:
		_water_overlay.visible = true
		# Son ambiant
		if not _underwater_player.playing:
			_underwater_player.play()
		# Reduire le fog de la camera pour effet murky
		if camera:
			camera.attributes = null  # Reset
			var env = get_viewport().world_3d.environment
			if env:
				env.fog_enabled = true
				env.fog_light_color = Color(0.05, 0.15, 0.35)
				env.fog_density = 0.08
				env.fog_sky_affect = 0.0
		# Son de nage quand on bouge
		if velocity.length() > 1.0:
			_swim_timer += delta
			if _swim_timer >= SWIM_SOUND_INTERVAL:
				_swim_timer = 0.0
				_play_swim_sound()
		# Noyade — timer d'air
		_air_supply -= delta
		if _air_supply <= 0.0:
			_drown_damage_timer += delta
			if _drown_damage_timer >= DROWN_DAMAGE_INTERVAL:
				_drown_damage_timer = 0.0
				take_damage(2)
		# Splash a l'entree dans l'eau
		if not _was_in_water:
			_play_splash_sound()
	else:
		_water_overlay.visible = false
		_air_supply = DROWN_TIME  # Reset air
		_drown_damage_timer = 0.0
		_swim_timer = 0.0
		if _underwater_player.playing:
			_underwater_player.stop()
		# Restaurer le fog normal
		var env = get_viewport().world_3d.environment
		if env and env.fog_density > 0.01:
			env.fog_enabled = false
			env.fog_density = 0.0
	_was_in_water = head_underwater

func _play_swim_sound():
	var idx = randi_range(1, 18)
	var path = "res://assets/Audio/Minecraft/liquid/swim%d.mp3" % idx
	var snd = load(path)
	if snd:
		var asp = AudioStreamPlayer.new()
		asp.stream = snd
		asp.volume_db = -12.0
		add_child(asp)
		asp.play()
		asp.finished.connect(asp.queue_free)

func _play_splash_sound():
	var path = "res://assets/Audio/Minecraft/liquid/splash.mp3"
	var snd = load(path)
	if snd:
		var asp = AudioStreamPlayer.new()
		asp.stream = snd
		asp.volume_db = -6.0
		add_child(asp)
		asp.play()
		asp.finished.connect(asp.queue_free)

func _physics_process(delta):
	_update_compass()
	# Gestion de la mort
	if is_dead:
		respawn_timer -= delta
		if respawn_timer <= 0:
			_respawn()
		return

	# Détection eau et échelle
	in_water = false
	var on_ladder: bool = false
	if world_manager:
		var feet_pos = global_position.floor()
		var head_pos = (global_position + Vector3(0, 1.5, 0)).floor()
		var feet_block = world_manager.get_block_at_position(feet_pos)
		var head_block = world_manager.get_block_at_position(head_pos)
		in_water = feet_block == BlockRegistry.BlockType.WATER or head_block == BlockRegistry.BlockType.WATER
		on_ladder = feet_block == BlockRegistry.BlockType.LADDER or head_block == BlockRegistry.BlockType.LADDER

	# Effet visuel + sonore sous l'eau + noyade
	_update_underwater(delta)

	# Sécurité : si le joueur tombe sous le monde, le remonter en surface
	if global_position.y < -20.0:
		global_position.y = 100.0
		velocity = Vector3.ZERO
		print("Player: chute sous le monde — téléport de sécurité à Y=100")

	# Gravité (réduite dans l'eau et sur échelle)
	if not is_on_floor():
		if in_water or on_ladder:
			velocity.y -= gravity * 0.3 * delta
			if on_ladder and velocity.y < -2.0:
				velocity.y = -2.0  # Descente lente sur échelle
		else:
			velocity.y -= gravity * delta
			# Limiter la vitesse de chute (terminal velocity)
			velocity.y = maxf(velocity.y, -50.0)

	# Reset fall tracking dans l'eau / échelle
	if in_water or on_ladder:
		_fall_start_y = global_position.y

	# Pas de mouvement si UI ouverte
	if _is_any_ui_open():
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		move_and_slide()
		_update_damage(delta)
		return

	# Saut / Nage / Échelle
	if on_ladder:
		if Input.is_action_pressed("jump"):
			velocity.y = 3.5
		elif Input.is_action_pressed("move_backward"):
			velocity.y = -2.0
	elif in_water:
		if Input.is_action_pressed("jump"):
			velocity.y = 3.0
	else:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity * jump_boost

	# Sprint (pas dans l'eau)
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	is_sprinting = not in_water and Input.is_key_pressed(KEY_SHIFT) and input_dir.y < 0 and is_on_floor()
	var current_speed = speed * 0.5 if in_water else (sprint_speed if is_sprinting else speed)

	# Mouvement
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	# FOV dynamique (intègre le zoom Alt+Molette)
	var target_fov = zoom_fov + (SPRINT_FOV - NORMAL_FOV) if is_sprinting else zoom_fov
	camera.fov = lerpf(camera.fov, target_fov, FOV_LERP_SPEED * delta)

	_handle_auto_step(direction)
	move_and_slide()
	_update_damage(delta)
	_handle_bow(delta)
	_handle_melee(delta)
	_handle_block_interaction(delta)
	_handle_eating(delta)
	_handle_footsteps(delta, direction)
	# Vue 3ème personne
	_update_third_person_camera()
	_update_player_model_anim()

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
	var step_interval = FOOTSTEP_INTERVAL * 0.6 if is_sprinting else FOOTSTEP_INTERVAL
	if footstep_timer >= step_interval:
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

	# Raywalk manuel pour detecter les cross-mesh (pas de collision physique)
	var cross_pos = _find_cross_mesh_along_ray()
	var hitting_cross = cross_pos.x > -9000

	raycast.force_raycast_update()

	if not raycast.is_colliding() and not hitting_cross:
		_cancel_mining()
		look_block_type = BlockRegistry.BlockType.AIR
		if block_highlighter:
			block_highlighter.hide_highlight()
		return

	var break_pos: Vector3
	var place_pos: Vector3

	if hitting_cross:
		# Cross-mesh detecte par raywalk — priorite sur le raycast
		var ray_dist_cross = camera.global_position.distance_to(cross_pos + Vector3(0.5, 0.5, 0.5))
		var ray_dist_solid = 9999.0
		if raycast.is_colliding():
			ray_dist_solid = camera.global_position.distance_to(raycast.get_collision_point())
		if ray_dist_cross <= ray_dist_solid:
			break_pos = cross_pos
			place_pos = cross_pos  # Pas de placement sur cross-mesh
		else:
			# Le bloc solide est plus proche que le cross-mesh
			hitting_cross = false

	if not hitting_cross:
		if not raycast.is_colliding():
			_cancel_mining()
			if block_highlighter:
				block_highlighter.hide_highlight()
			return
		var collision_point = raycast.get_collision_point()
		var normal = raycast.get_collision_normal()
		break_pos = (collision_point - normal * 0.01).floor()
		place_pos = Vector3(break_pos) + normal

	# Si le bloc devant la face visée est une torche/lanterne/porte, cibler ce bloc
	if not hitting_cross:
		var front_type = world_manager.get_block_at_position(place_pos)
		if front_type == BlockRegistry.BlockType.TORCH or front_type == BlockRegistry.BlockType.LANTERN or BlockRegistry.is_door(front_type):
			break_pos = place_pos

	var break_block_type = world_manager.get_block_at_position(break_pos)
	look_block_type = break_block_type
	var can_break = break_block_type != BlockRegistry.BlockType.AIR and break_block_type != BlockRegistry.BlockType.WATER and (BlockRegistry.is_solid(break_block_type) or break_block_type == BlockRegistry.BlockType.TORCH or break_block_type == BlockRegistry.BlockType.LANTERN or BlockRegistry.is_cross_mesh(break_block_type))
	
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
			# temps = dureté × BASE_MINING_TIME / multiplicateur_outil
			mining_time_required = BlockRegistry.get_block_hardness(break_block_type) * BASE_MINING_TIME
			var tool_mult = ToolRegistry.get_mining_multiplier(_get_selected_tool(), break_block_type)
			if tool_mult > 0:
				mining_time_required /= tool_mult
			if mining_time_required <= 0:
				mining_time_required = 0.1
		
		mining_progress += delta / mining_time_required
		
		# Son de frappe périodique + animation swing
		mining_hit_timer += delta
		if mining_hit_timer >= MINING_HIT_INTERVAL:
			mining_hit_timer = 0.0
			if audio_manager:
				audio_manager.play_mining_hit(mining_block_type, mining_block_pos)
			if hand_renderer:
				hand_renderer.play_swing()
		
		if block_highlighter:
			block_highlighter.set_mining_progress(mining_progress)
		
		if mining_progress >= 1.0:
			_break_block(break_pos, break_block_type)
	else:
		if is_mining:
			_cancel_mining()
	
	# Clic droit : manger / interaction avec bloc / placement
	if Input.is_action_pressed("place_block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Arc géré par _handle_bow() — ne pas interférer
		if is_drawing_bow or _get_selected_tool() == ToolRegistry.ToolType.BOW:
			return
		# Si on tient de la nourriture, manger (maintenir clic droit)
		if _is_food_slot() and current_health < max_health:
			if not is_eating:
				is_eating = true
				eating_progress = 0.0
				eating_particle_timer = 0.0
				eating_sound_timer = 0.0
				if audio_manager:
					audio_manager.play_eat_sound()
			return

	if Input.is_action_just_pressed("place_block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Arc — ne pas placer
		if _get_selected_tool() == ToolRegistry.ToolType.BOW:
			return
		# Nourriture — ne pas placer
		if _is_food_slot():
			return

		# Shift+clic droit : rotation de bloc (vitres, barreaux)
		if Input.is_key_pressed(KEY_SHIFT):
			if break_block_type == BlockRegistry.BlockType.GLASS_PANE or break_block_type == BlockRegistry.BlockType.IRON_BARS:
				var rkey = Vector3i(int(floor(break_pos.x)), int(floor(break_pos.y)), int(floor(break_pos.z)))
				var cur = world_manager.pane_orientation.get(rkey, 0)
				world_manager.pane_orientation[rkey] = 1 - cur  # toggle 0↔1
				world_manager.rebuild_chunk_at(break_pos)
				return

		# Vérifier si on regarde une porte → ouvrir/fermer (les 2 blocs d'un coup)
		if BlockRegistry.is_door(break_block_type):
			world_manager.toggle_door_pair(break_pos)
			return

		# Vérifier si on regarde un bloc interactif (table de craft, fourneau)
		var interact_tier = _get_interact_tier(break_block_type)
		if interact_tier >= 0:
			var is_furnace = break_block_type == BlockRegistry.BlockType.FURNACE
			_toggle_crafting(interact_tier, is_furnace)
			return

		# Sinon, placement normal
		var place_block_type = world_manager.get_block_at_position(place_pos)
		var is_flora = BlockRegistry.is_cross_mesh(place_block_type)
		# Check simple comme Minecraft : interdire seulement de poser dans le bloc
		# exact des pieds ou de la tete (pas d'AABB complexe qui bloque les ponts)
		var player_feet = global_position.floor()
		var player_head = (global_position + Vector3(0, 1, 0)).floor()
		var blocks_player = place_pos == player_feet or place_pos == player_head
		var can_place = (place_block_type == BlockRegistry.BlockType.AIR or place_block_type == BlockRegistry.BlockType.WATER or is_flora) and not blocks_player

		if can_place and get_inventory_count(selected_block_type) > 0:
			# Placement spécial : portes = 2 blocs de haut avec orientation
			if BlockRegistry.is_door(selected_block_type):
				var above_pos = place_pos + Vector3(0, 1, 0)
				var above_type = world_manager.get_block_at_position(above_pos)
				var above_blocked = above_pos.floor() == player_feet or above_pos.floor() == player_head
				if (above_type == BlockRegistry.BlockType.AIR or above_type == BlockRegistry.BlockType.WATER) and not above_blocked:
					# Déterminer l'orientation : direction dans laquelle le joueur regarde
					var yaw = camera.global_rotation.y
					var facing: int
					if abs(sin(yaw)) > abs(cos(yaw)):
						facing = 3 if sin(yaw) > 0 else 2  # W ou E
					else:
						facing = 0 if cos(yaw) > 0 else 1  # N ou S
					# Ctrl = inverser (front au lieu de back)
					if Input.is_key_pressed(KEY_CTRL):
						facing = [1, 0, 3, 2][facing]  # N↔S, E↔W
					# Déterminer la charnière : auto-miroir si porte adjacente
					var hinge = "left"
					var bottom_key = Vector3i(int(floor(place_pos.x)), int(floor(place_pos.y)), int(floor(place_pos.z)))
					var adj = world_manager._find_adjacent_door(bottom_key, facing)
					if adj.x != -9999:
						var adj_hinge = world_manager.get_door_hinge(adj.x, adj.y, adj.z)
						hinge = "right" if adj_hinge == "left" else "left"
					world_manager.place_door(place_pos, selected_block_type, facing, hinge)
					_remove_from_inventory(selected_block_type)
					if audio_manager:
						audio_manager.play_place_sound(selected_block_type, place_pos)
					if hand_renderer:
						hand_renderer.play_swing()
				return

			# Auto-orientation vitre : détection blocs adjacents
			if selected_block_type == BlockRegistry.BlockType.GLASS_PANE or selected_block_type == BlockRegistry.BlockType.IRON_BARS:
				var pkey = Vector3i(int(floor(place_pos.x)), int(floor(place_pos.y)), int(floor(place_pos.z)))
				# Vérifier blocs solides sur les 4 côtés
				var has_x_plus = BlockRegistry.is_solid(world_manager.get_block_at_position(place_pos + Vector3(1, 0, 0)))
				var has_x_minus = BlockRegistry.is_solid(world_manager.get_block_at_position(place_pos + Vector3(-1, 0, 0)))
				var has_z_plus = BlockRegistry.is_solid(world_manager.get_block_at_position(place_pos + Vector3(0, 0, 1)))
				var has_z_minus = BlockRegistry.is_solid(world_manager.get_block_at_position(place_pos + Vector3(0, 0, -1)))
				var x_neighbors = int(has_x_plus) + int(has_x_minus)
				var z_neighbors = int(has_z_plus) + int(has_z_minus)
				# Aligner avec les blocs adjacents : si blocs sur X → s'étendre le long de X (0), si blocs sur Z → s'étendre le long de Z (1)
				var orient: int
				if x_neighbors > z_neighbors:
					orient = 0  # N-S (s'étend le long de X, entre les blocs à gauche/droite)
				elif z_neighbors > x_neighbors:
					orient = 1  # E-W (s'étend le long de Z, entre les blocs devant/derrière)
				else:
					orient = 0  # défaut
				world_manager.pane_orientation[pkey] = orient
			world_manager.place_block_at_position(place_pos, selected_block_type)
			_remove_from_inventory(selected_block_type)
			if audio_manager:
				audio_manager.play_place_sound(selected_block_type, place_pos)
			if hand_renderer:
				hand_renderer.play_swing()

	# Arrêter de manger si clic droit relâché
	if not Input.is_action_pressed("place_block") and is_eating:
		_cancel_eating()

func _find_cross_mesh_along_ray() -> Vector3:
	"""Raywalk manuel pour detecter les cross-mesh le long du regard."""
	var origin = camera.global_position
	var dir = -camera.global_basis.z
	var last_block = Vector3i(-9999, -9999, -9999)
	for i in range(int(reach_distance * 8)):
		var t = i * 0.125  # pas de 1/8 de bloc
		var pos = origin + dir * t
		var block_pos = Vector3i(int(floor(pos.x)), int(floor(pos.y)), int(floor(pos.z)))
		if block_pos == last_block:
			continue
		last_block = block_pos
		var bt = world_manager.get_block_at_position(Vector3(block_pos))
		if BlockRegistry.is_cross_mesh(bt):
			return Vector3(block_pos)
		if bt != BlockRegistry.BlockType.AIR and bt != BlockRegistry.BlockType.WATER and BlockRegistry.is_solid(bt):
			break  # Touche un bloc solide, arret
	return Vector3(-9999, -9999, -9999)

func _break_block(pos: Vector3, block_type: BlockRegistry.BlockType):
	var is_door = BlockRegistry.is_door(block_type)
	world_manager.break_block_at_position(pos)
	if not is_door:
		# Drops speciaux pour la vegetation cross-mesh (comme Minecraft)
		if block_type == BlockRegistry.BlockType.SHORT_GRASS or block_type == BlockRegistry.BlockType.FERN:
			# 12.5% de chance de dropper des graines de ble
			if randf() < 0.125:
				_add_to_inventory(BlockRegistry.BlockType.WHEAT_ITEM)
			# Sinon : rien (l'herbe disparait)
		elif block_type == BlockRegistry.BlockType.DEAD_BUSH:
			pass  # Buisson mort ne donne rien
		elif BlockRegistry.is_cross_mesh(block_type):
			# Fleurs : droppent elles-memes (pissenlit, coquelicot, bleuet)
			_add_to_inventory(block_type)
		else:
			_add_to_inventory(block_type)
	_spawn_break_particles(pos, block_type)
	if audio_manager:
		audio_manager.play_break_sound(block_type, pos)
	# Récupérer la végétation/torches/portes détruites par le cassage du bloc
	var extras = world_manager.get_and_clear_broken_extras()
	for extra in extras:
		_add_to_inventory(extra)
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

# ============================================================
# NOURRITURE — Manger
# ============================================================
func _is_food_slot() -> bool:
	return selected_slot >= 0 and selected_slot < hotbar_food_slots.size() and hotbar_food_slots[selected_slot]

func _handle_eating(delta: float):
	if not is_eating:
		return

	eating_progress += delta / EATING_TIME

	# Particules rouges périodiques
	eating_particle_timer += delta
	if eating_particle_timer >= EATING_PARTICLE_INTERVAL:
		eating_particle_timer = 0.0
		_spawn_eating_particles()

	# Son de mâchage périodique
	eating_sound_timer += delta
	if eating_sound_timer >= EATING_SOUND_INTERVAL:
		eating_sound_timer = 0.0
		if audio_manager:
			audio_manager.play_eat_sound()

	# Animation swing périodique (bras qui porte vers la bouche)
	if hand_renderer and fmod(eating_progress * EATING_TIME, 0.4) < delta:
		hand_renderer.play_swing()

	# Fin du repas
	if eating_progress >= 1.0:
		heal(EATING_HEAL_AMOUNT)
		is_eating = false
		eating_progress = 0.0
		eating_particle_timer = 0.0
		eating_sound_timer = 0.0

func _cancel_eating():
	is_eating = false
	eating_progress = 0.0
	eating_particle_timer = 0.0
	eating_sound_timer = 0.0

# ============================================================
# ARC — Charge et tir
# ============================================================
func _handle_bow(delta: float):
	var is_bow = _get_selected_tool() == ToolRegistry.ToolType.BOW
	var right_held = Input.is_action_pressed("place_block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	# Relâché — tirer
	if is_drawing_bow and not right_held:
		_fire_arrow()
		return

	# Début de charge
	if is_bow and right_held and not is_drawing_bow:
		is_drawing_bow = true
		bow_charge_time = 0.0
		if hand_renderer:
			hand_renderer.start_bow_pull()

	# Mise à jour charge
	if is_drawing_bow:
		bow_charge_time += delta
		var pull = clampf(bow_charge_time / BOW_MAX_CHARGE, 0.0, 1.0)
		if hand_renderer:
			hand_renderer.update_bow_pull(pull)

func _fire_arrow():
	if not is_drawing_bow:
		return
	var charge = clampf(bow_charge_time / BOW_MAX_CHARGE, 0.0, 1.0)
	# MC formula: velocity factor = (f² + 2f) / 3
	var factor = (charge * charge + 2.0 * charge) / 3.0

	# Reset bow state
	is_drawing_bow = false
	bow_charge_time = 0.0
	if hand_renderer:
		hand_renderer.stop_bow_pull()
		hand_renderer.play_swing()

	# Trop court — pas de flèche
	if factor < 0.1:
		return

	# Créer la flèche
	var arrow = ArrowEntityScript.new()
	get_tree().root.add_child(arrow)
	var cam_dir = -camera.global_basis.z
	var origin = camera.global_position
	arrow.initialize(origin, cam_dir, factor, self)

func _spawn_eating_particles():
	var particles = CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.amount = 6
	particles.lifetime = 0.4
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.1
	particles.direction = -camera.global_basis.z
	particles.spread = 30.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 2.5
	particles.gravity = Vector3(0, -6, 0)
	particles.scale_amount_min = 0.04
	particles.scale_amount_max = 0.08
	particles.color = Color(0.85, 0.15, 0.15)  # Rouge pomme
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1, 1, 1)
	particles.mesh = box_mesh
	particles.emitting = false
	get_tree().root.add_child(particles)
	# Position devant la caméra (zone de la bouche)
	particles.global_position = camera.global_position + camera.global_basis.z * -0.5 + Vector3(0, -0.15, 0)
	particles.restart()
	get_tree().create_timer(1.0).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)

func _update_selected_block():
	if selected_slot >= 0 and selected_slot < hotbar_slots.size():
		selected_block_type = hotbar_slots[selected_slot]
		_update_hand_display()

func _update_hand_display():
	if not hand_renderer:
		return
	# Annuler l'arc si on change de slot
	if is_drawing_bow:
		is_drawing_bow = false
		bow_charge_time = 0.0
		hand_renderer.stop_bow_pull()
	# Nourriture ?
	if _is_food_slot():
		var scene = load(APPLE_MODEL_PATH) as PackedScene
		if scene:
			var node = scene.instantiate()
			hand_renderer.update_held_tool_node(node, Vector3(0, -45, 0), 0.20)
		else:
			hand_renderer.update_held_item(BlockRegistry.BlockType.AIR)
		return
	# Outil ? → flat sprite depuis la texture d'item du pack
	var tool_type = _get_selected_tool()
	if tool_type != ToolRegistry.ToolType.NONE:
		hand_renderer.update_held_item_sprite(tool_type)
	else:
		hand_renderer.update_held_item(selected_block_type)

func _get_selected_tool() -> ToolRegistry.ToolType:
	if selected_slot >= 0 and selected_slot < hotbar_tool_slots.size():
		return hotbar_tool_slots[selected_slot]
	return ToolRegistry.ToolType.NONE

# ============================================================
# COMBAT MÊLÉE
# ============================================================
func _handle_melee(delta: float):
	# is_action_pressed (pas just_pressed) = mode turbo, attaque en continu
	if not Input.is_action_pressed("break_block") or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if melee_cooldown > 0 or is_drawing_bow or _is_any_ui_open():
		return

	# Chercher le mob le plus proche devant la caméra
	var cam_pos = camera.global_position
	var cam_dir = -camera.global_basis.z
	var best_mob: Node3D = null
	var best_dist = MELEE_RANGE + 1.0

	for group_name in ["passive_mobs", "npc_villagers"]:
		for mob in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(mob) or not mob is Node3D:
				continue
			var to_mob = mob.global_position + Vector3(0, 0.5, 0) - cam_pos
			var dist = to_mob.length()
			if dist > MELEE_RANGE:
				continue
			# Vérifier que le mob est devant la caméra (dot product > 0)
			var dot = cam_dir.dot(to_mob.normalized())
			if dot < 0.5:  # ~60° de chaque côté
				continue
			if dist < best_dist:
				best_dist = dist
				best_mob = mob

	if best_mob == null:
		return

	# Appliquer les dégâts
	var tool_type = _get_selected_tool()
	var damage = ToolRegistry.get_attack_damage(tool_type)
	var knockback_dir = (best_mob.global_position - global_position).normalized()
	knockback_dir.y = 0
	var kb = knockback_dir * MELEE_KNOCKBACK + Vector3(0, MELEE_LIFT, 0)

	if best_mob.has_method("take_hit"):
		best_mob.take_hit(damage, kb)

	# Swing animation + cooldown
	melee_cooldown = MELEE_COOLDOWN_TIME
	if hand_renderer:
		hand_renderer.play_swing()

# ============================================================
# GESTION DE LA VIE
# ============================================================
func _update_damage(delta: float):
	if damage_cooldown > 0:
		damage_cooldown -= delta
	if melee_cooldown > 0:
		melee_cooldown -= delta
	_check_fall_damage()
	_check_cactus_damage()

func _check_fall_damage():
	var on_floor_now = is_on_floor()
	if _was_on_floor and not on_floor_now:
		_fall_start_y = global_position.y
	if not _was_on_floor and on_floor_now and not in_water:
		var fall_distance = _fall_start_y - global_position.y
		if fall_distance > FALL_DAMAGE_THRESHOLD:
			var damage = int((fall_distance - FALL_DAMAGE_THRESHOLD) * FALL_DAMAGE_MULTIPLIER)
			if damage > 0:
				take_damage(damage)
	_was_on_floor = on_floor_now

func _check_cactus_damage():
	if not world_manager or damage_cooldown > 0:
		return
	# Vérifier les blocs adjacents au joueur (rayon > collision pour détecter au contact)
	var bx = int(floor(global_position.x))
	var bz = int(floor(global_position.z))
	var by = int(floor(global_position.y))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for dy in range(0, 3):
				var check_pos = Vector3(bx + dx, by + dy, bz + dz)
				if world_manager.get_block_at_position(check_pos) == BlockRegistry.BlockType.CACTUS:
					# Vérifier la proximité réelle (distance AABB joueur ↔ bloc)
					var block_center = check_pos + Vector3(0.5, 0.5, 0.5)
					var dist_x = absf(global_position.x - block_center.x) - 0.5
					var dist_z = absf(global_position.z - block_center.z) - 0.5
					var dist_y = global_position.y + 0.9 - block_center.y  # Centre joueur
					if dist_x < 0.5 and dist_z < 0.5 and absf(dist_y) < 1.4:
						take_damage(CACTUS_DAMAGE)
						return

func take_damage(amount: int, knockback: Vector3 = Vector3.ZERO):
	if damage_cooldown > 0 or is_dead:
		return
	current_health = maxi(0, current_health - amount)
	damage_cooldown = DAMAGE_COOLDOWN_TIME
	if knockback.length_squared() > 0.01:
		velocity += knockback
	if current_health <= 0:
		_die()

func heal(amount: int):
	current_health = mini(max_health, current_health + amount)

func _die():
	is_dead = true
	respawn_timer = RESPAWN_DELAY
	velocity = Vector3.ZERO
	_cancel_mining()
	if is_drawing_bow:
		is_drawing_bow = false
		bow_charge_time = 0.0
		if hand_renderer:
			hand_renderer.stop_bow_pull()

func _respawn():
	is_dead = false
	current_health = max_health
	global_position = spawn_position
	velocity = Vector3.ZERO
	_was_on_floor = true
	damage_cooldown = DAMAGE_COOLDOWN_TIME

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
