extends CharacterBody3D
class_name NpcVillager

const VProfession = preload("res://scripts/villager_profession.gd")
const GC = preload("res://scripts/game_config.gd")

const INVALID_POS = Vector3i(-9999, -9999, -9999)

# Conversion minage : STONE → COBBLESTONE (comme Minecraft)
static func _mined_drop(block_type) -> int:
	if block_type == BlockRegistry.BlockType.STONE:
		return BlockRegistry.BlockType.COBBLESTONE
	return block_type

# Blocs inutiles cassés par le berserker — ne PAS ajouter au stockpile
static var _junk_blocks: Dictionary = {}
static func _is_junk_block(bt: int) -> bool:
	if _junk_blocks.is_empty():
		# Blocs inutiles pour le village — utiliser les enum pour éviter les erreurs d'ID
		for junk in [
			BlockRegistry.BlockType.GRASS,
			BlockRegistry.BlockType.DIRT,
			BlockRegistry.BlockType.LEAVES,
			BlockRegistry.BlockType.SNOW,
			BlockRegistry.BlockType.DARK_GRASS,
			BlockRegistry.BlockType.GRAVEL,
			BlockRegistry.BlockType.SPRUCE_LEAVES,
			BlockRegistry.BlockType.BIRCH_LEAVES,
			BlockRegistry.BlockType.JUNGLE_LEAVES,
			BlockRegistry.BlockType.ACACIA_LEAVES,
			BlockRegistry.BlockType.DARK_OAK_LEAVES,
			BlockRegistry.BlockType.CHERRY_LEAVES,
			BlockRegistry.BlockType.PODZOL,
			BlockRegistry.BlockType.MOSS_BLOCK,
			BlockRegistry.BlockType.FARMLAND,
			BlockRegistry.BlockType.SHORT_GRASS,
			BlockRegistry.BlockType.FERN,
			BlockRegistry.BlockType.DEAD_BUSH,
			BlockRegistry.BlockType.DANDELION,
			BlockRegistry.BlockType.POPPY,
			BlockRegistry.BlockType.CORNFLOWER,
		]:
			_junk_blocks[junk] = true
	return _junk_blocks.has(bt)

# Modèle Steve GLB unique — chaque villageois reçoit un skin de profession différent
const STEVE_GLB_PATH = "res://assets/PlayerModel/steve.glb"
static var _steve_scene: PackedScene = null
static var _skin_cache: Dictionary = {}  # cache des ImageTexture par chemin
static var _tool_mesh_cache: Dictionary = {}  # cache des ArrayMesh par texture path

# Constantes outils tenus par les PNJ
const NPC_TOOL_SIZE = 0.70
const NPC_TOOL_DEPTH = 0.04
const NPC_TOOL_GRID = 16

static func _preload_steve():
	if _steve_scene:
		return
	# Méthode 1 : load() classique (nécessite .import)
	_steve_scene = load(STEVE_GLB_PATH) as PackedScene
	if _steve_scene:
		print("NpcVillager: Steve GLB chargé via load()")
		return
	# Méthode 2 : chargement runtime via GLTFDocument (pas besoin d'import)
	print("NpcVillager: load() échoué, chargement GLB via GLTFDocument...")
	var gltf_doc = GLTFDocument.new()
	var gltf_state = GLTFState.new()
	var err = gltf_doc.append_from_file(STEVE_GLB_PATH, gltf_state)
	if err == OK:
		var scene = gltf_doc.generate_scene(gltf_state)
		if scene:
			# Convertir la scène en PackedScene pour la réutiliser
			var packed = PackedScene.new()
			packed.pack(scene)
			_steve_scene = packed
			scene.queue_free()
			print("NpcVillager: Steve GLB chargé via GLTFDocument (%d nodes)" % [packed.get_state().get_node_count()])
			return
	push_error("NpcVillager: IMPOSSIBLE de charger steve.glb (err=%s)" % str(err))

# === Identité ===
var villager_index: int = 0
var chunk_position: Vector3i = Vector3i.ZERO
var _spawn_pos: Vector3 = Vector3.ZERO
var profession: int = 0  # VProfession.Profession
var health: int = 20

# === Mouvement ===
var move_speed: float = 2.0
var wander_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var is_moving: bool = false
var gravity_val: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var world_manager = null
var _anim_player: AnimationPlayer = null
var _current_anim: String = ""
var _skeleton: Skeleton3D = null
var _model_instance: Node3D = null
var _right_tool: MeshInstance3D = null  # outil main droite
var _left_tool: MeshInstance3D = null   # outil main gauche
var _jump_velocity: float = 5.0
var _stuck_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO

# === Emploi du temps ===
var current_activity: int = 0  # VProfession.Activity
var home_position: Vector3 = Vector3.ZERO
var _schedule_timer: float = 0.0
var _day_night: Node = null

# === Navigation vers cible ===
var target_position: Vector3 = Vector3.ZERO
var has_target: bool = false
var _arrived_at_target: bool = false
var _target_stuck_timer: float = 0.0
var _total_stuck_time: float = 0.0  # temps total bloqué (cumulé)
var _detour_timer: float = 0.0
var _detour_direction: Vector3 = Vector3.ZERO
var _detour_count: int = 0  # nombre de détours effectués

# === POI / Travail ===
var claimed_poi: Vector3i = Vector3i(-9999, -9999, -9999)
var poi_manager = null  # POIManager reference, passée par WorldManager

const INVALID_POI = Vector3i(-9999, -9999, -9999)

# === Village Manager ===
var village_manager = null
var current_task: Dictionary = {}
var _mine_timer: float = 0.0
var _mine_target: Vector3i = INVALID_POS
var _build_timer: float = 0.0
var _build_walk_timer: float = 0.0  # temps passé à marcher vers un bloc de construction
var _path_block_type: int = 25  # type de bloc courant pour build_path (default COBBLESTONE)
var _task_status: String = ""  # texte affiché

# === Label3D au-dessus de la tête ===
var _head_label: Label3D = null
var _label_update_timer: float = 0.0

# === Faim ===
var hunger: float = 100.0
const HUNGER_MAX = 100.0
const HUNGER_DRAIN_WORK = 0.0    # DÉSACTIVÉ — réactiver quand la ferme fonctionne (ancien: 0.06)
const HUNGER_DRAIN_REST = 0.0    # DÉSACTIVÉ — réactiver quand la ferme fonctionne (ancien: 0.01)
const HUNGER_THRESHOLD_EAT = 40.0
const HUNGER_THRESHOLD_SLOW = 20.0
const HUNGER_BREAD_RESTORE = 50.0
const HUNGER_WHEAT_RESTORE = 20.0
var _is_starving: bool = false  # à 0 de faim
var _base_move_speed: float = 2.0

# === Cooldown pour éviter les scans coûteux en boucle ===
var _search_cooldown: float = 0.0
const SEARCH_COOLDOWN_DURATION = 5.0  # secondes avant de retenter une recherche

# === Throttle navigation block lookups ===
var _nav_check_timer: float = 0.0
const NAV_CHECK_INTERVAL = 0.15  # vérif obstacles toutes les 0.15s au lieu de chaque frame
var _cached_block_ahead: int = 0  # BlockType en cache
var _cached_block_below: int = 0
var _cached_block_above: int = 0
var _wall_impassable: bool = false  # mur 2+ blocs détecté devant

# === Retour surface mineur ===
var _mine_entry_pos: Vector3 = Vector3.ZERO
var _mine_resume_pos: Vector3 = Vector3.ZERO  # position sauvegardée pour reprendre le minage
var _returning_to_surface: bool = false
var _return_stuck_timer: float = 0.0

func setup(idx: int, pos: Vector3, chunk_pos: Vector3i, prof: int = 0):
	villager_index = idx
	_spawn_pos = pos
	chunk_position = chunk_pos
	profession = prof
	home_position = pos

func _ready():
	position = _spawn_pos
	_preload_steve()
	_create_model()
	_create_collision()
	_create_head_label()
	_pick_new_wander()
	rotation.y = randf() * TAU
	world_manager = get_tree().get_first_node_in_group("world_manager")
	_day_night = get_tree().get_first_node_in_group("day_night_cycle")
	village_manager = get_node_or_null("/root/VillageManager")

func _create_model():
	if not _steve_scene:
		return
	_model_instance = _steve_scene.instantiate()
	# Steve GLB = 2 unités de haut (32px / 16 scale), 0.85 → ~1.7 unités = collision box
	_model_instance.scale = Vector3(0.85, 0.85, 0.85)
	# Pas de rotation sur model_instance (casse les animations bone)
	# Le facing est corrigé via +PI dans _face_target / _apply_movement
	add_child(_model_instance)
	# Appliquer le skin de profession
	var skin_path = VProfession.get_skin_for_profession(profession)
	_apply_skin_texture(_model_instance, skin_path)
	_anim_player = _find_animation_player(_model_instance)
	if _anim_player:
		# deterministic=true force le reset des bones sans track à la rest pose
		# (par défaut AnimationPlayer est non-déterministe et garde la pose précédente)
		_anim_player.deterministic = true
		if villager_index == 0:
			var anims: PackedStringArray = _anim_player.get_animation_list()
			print("NpcVillager: AnimationPlayer trouvé, %d animations: %s" % [anims.size(), str(anims)])
		_play_anim("idle")
	else:
		if villager_index == 0:
			print("NpcVillager: AUCUN AnimationPlayer trouvé dans le modèle")
	# Outils tenus en main (BoneAttachment3D sur rightArm/leftArm)
	_skeleton = _find_skeleton(_model_instance)
	if _skeleton and villager_index == 0:
		var bone_count = _skeleton.get_bone_count()
		var bone_names = []
		for i in range(bone_count):
			bone_names.append(_skeleton.get_bone_name(i))
		print("NpcVillager: Skeleton trouvé, %d bones: %s" % [bone_count, str(bone_names)])
	elif villager_index == 0:
		print("NpcVillager: AUCUN Skeleton3D trouvé dans le modèle")
	_setup_held_tools()

static func _load_skin_texture(skin_path: String) -> Texture2D:
	# Essayer le cache d'abord
	if _skin_cache.has(skin_path):
		return _skin_cache[skin_path]
	# Essayer load() (fonctionne si Godot a importé le fichier)
	var tex = load(skin_path) as Texture2D
	if tex:
		_skin_cache[skin_path] = tex
		return tex
	# Fallback : charger le PNG en runtime via Image (pas besoin d'import)
	var img = Image.load_from_file(skin_path)
	if img:
		var itex = ImageTexture.create_from_image(img)
		_skin_cache[skin_path] = itex
		print("NpcVillager: skin chargé via Image: " + skin_path)
		return itex
	push_warning("NpcVillager: skin introuvable: " + skin_path)
	return null

func _apply_skin_texture(model: Node, skin_path: String):
	var tex = _load_skin_texture(skin_path)
	if not tex:
		return
	_apply_skin_recursive(model, tex)

func _apply_skin_recursive(node: Node, tex: Texture2D):
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		for i in range(mi.mesh.get_surface_count()):
			var base_mat = mi.mesh.surface_get_material(i)
			if base_mat is StandardMaterial3D:
				var mat = base_mat.duplicate() as StandardMaterial3D
				mat.albedo_texture = tex
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Fix faces inversées
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_skin_recursive(child, tex)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null

func _play_anim(anim_name: String):
	if not _anim_player or _current_anim == anim_name:
		return
	if _anim_player.has_animation(anim_name):
		var anim = _anim_player.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR
		# Reset les bones à la rest pose avant de switcher (évite les jambes écartées)
		if _skeleton:
			_skeleton.reset_bone_poses()
		_anim_player.play(anim_name, 0)  # blend=0 (instant switch)
		_anim_player.seek(0.0, true)  # force update au frame 0
		_current_anim = anim_name

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found:
			return found
	return null

func _setup_held_tools():
	var tools = VProfession.get_held_tools(profession)
	if tools.is_empty() or not _model_instance or not _skeleton:
		return
	print("NpcVillager[%d]: setup tools %s (prof=%d)" % [villager_index, str(tools), profession])
	# Main droite — BoneAttachment3D sur rightItem (bone enfant de rightArm, bout de la main)
	# Ry(-90°) vue de profil + Rz(180°) flip pour que la lame pointe vers le bas (-Y = loin de l'épaule)
	# Offset Y = -half pour que le grip (bas original de la texture) soit dans la main
	var tool_offset_y = -NPC_TOOL_SIZE * 0.5
	if tools.has("right"):
		var tex_path = GC.get_item_texture_path() + tools["right"] + ".png"
		var mesh = _build_npc_tool_mesh(tex_path, Vector3(180, 90, 0))
		if mesh:
			_right_tool = _attach_tool_to_bone(mesh, "rightItem",
				Vector3(0.0, tool_offset_y - 0.1, 0.0), Vector3(-45, 0, 0))
	# Main gauche — BoneAttachment3D sur leftItem (miroir)
	if tools.has("left"):
		var left_name = tools["left"]
		var tex_path: String
		if left_name == "shield":
			tex_path = GC.get_entity_texture_path() + "shield_base_nopattern.png"
		else:
			tex_path = GC.get_item_texture_path() + left_name + ".png"
		var mesh = _build_npc_tool_mesh(tex_path, Vector3(180, -90, 0))
		if mesh:
			_left_tool = _attach_tool_to_bone(mesh, "leftItem",
				Vector3(0.0, tool_offset_y - 0.1, 0.0), Vector3(45, 0, 0))

func _attach_tool_to_bone(mesh: ArrayMesh, bone_name: String, offset: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var bone_idx = _skeleton.find_bone(bone_name)
	if bone_idx < 0:
		push_warning("NpcVillager: bone '%s' introuvable dans le skeleton" % bone_name)
		return null
	var attachment = BoneAttachment3D.new()
	attachment.bone_name = bone_name
	attachment.bone_idx = bone_idx
	_skeleton.add_child(attachment)
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.position = offset
	mesh_inst.rotation_degrees = rot_deg
	mesh_inst.extra_cull_margin = 100.0
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	attachment.add_child(mesh_inst)
	print("NpcVillager: tool attaché au bone '%s' (idx=%d), offset=%s, rot=%s" % [bone_name, bone_idx, str(offset), str(rot_deg)])
	return mesh_inst

static func _build_npc_tool_mesh(tex_path: String, rot_deg: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var cache_key = tex_path + str(rot_deg)
	if _tool_mesh_cache.has(cache_key):
		return _tool_mesh_cache[cache_key]
	# Charger l'image
	var img = Image.load_from_file(tex_path)
	if not img:
		var abs_path = ProjectSettings.globalize_path(tex_path)
		img = Image.load_from_file(abs_path)
	if not img:
		push_warning("NpcVillager: Tool texture introuvable: " + tex_path)
		return null
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != NPC_TOOL_GRID or img.get_height() != NPC_TOOL_GRID:
		img.resize(NPC_TOOL_GRID, NPC_TOOL_GRID, Image.INTERPOLATE_NEAREST)
	# Rotation bakée dans les vertices
	var rot_basis = Basis.from_euler(Vector3(
		deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	var mesh = ArrayMesh.new()
	var pixel_size = NPC_TOOL_SIZE / float(NPC_TOOL_GRID)
	var half = NPC_TOOL_SIZE * 0.5
	var half_d = NPC_TOOL_DEPTH * 0.5
	var color_quads: Dictionary = {}
	for py in range(NPC_TOOL_GRID):
		for px in range(NPC_TOOL_GRID):
			var c = img.get_pixel(px, py)
			if c.a < 0.5:
				continue
			var x0 = -half + px * pixel_size
			var x1 = x0 + pixel_size
			var y1 = half - py * pixel_size
			var y0 = y1 - pixel_size
			_npc_quad(color_quads, c, 1.0, rot_basis,
				Vector3(x0, y0, half_d), Vector3(x1, y0, half_d),
				Vector3(x1, y1, half_d), Vector3(x0, y1, half_d))
			_npc_quad(color_quads, c, 1.0, rot_basis,
				Vector3(x1, y0, -half_d), Vector3(x0, y0, -half_d),
				Vector3(x0, y1, -half_d), Vector3(x1, y1, -half_d))
			if px == 0 or img.get_pixel(px - 1, py).a < 0.5:
				_npc_quad(color_quads, c, 0.7, rot_basis,
					Vector3(x0, y0, -half_d), Vector3(x0, y0, half_d),
					Vector3(x0, y1, half_d), Vector3(x0, y1, -half_d))
			if px == NPC_TOOL_GRID - 1 or img.get_pixel(px + 1, py).a < 0.5:
				_npc_quad(color_quads, c, 0.7, rot_basis,
					Vector3(x1, y0, half_d), Vector3(x1, y0, -half_d),
					Vector3(x1, y1, -half_d), Vector3(x1, y1, half_d))
			if py == NPC_TOOL_GRID - 1 or img.get_pixel(px, py + 1).a < 0.5:
				_npc_quad(color_quads, c, 0.85, rot_basis,
					Vector3(x0, y0, half_d), Vector3(x0, y0, -half_d),
					Vector3(x1, y0, -half_d), Vector3(x1, y0, half_d))
			if py == 0 or img.get_pixel(px, py - 1).a < 0.5:
				_npc_quad(color_quads, c, 0.85, rot_basis,
					Vector3(x0, y1, -half_d), Vector3(x0, y1, half_d),
					Vector3(x1, y1, half_d), Vector3(x1, y1, -half_d))
	for key in color_quads:
		var quads = color_quads[key]
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = key
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		st.set_material(mat)
		for q in quads:
			var n = Vector3(0, 0, 1)
			st.set_normal(n); st.add_vertex(q[0])
			st.set_normal(n); st.add_vertex(q[1])
			st.set_normal(n); st.add_vertex(q[2])
			st.set_normal(n); st.add_vertex(q[0])
			st.set_normal(n); st.add_vertex(q[2])
			st.set_normal(n); st.add_vertex(q[3])
		st.commit(mesh)
	_tool_mesh_cache[cache_key] = mesh
	return mesh

static func _npc_quad(dict: Dictionary, base_color: Color, shade: float, rot: Basis, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3):
	var c = Color(base_color.r * shade, base_color.g * shade, base_color.b * shade, 1.0)
	if not dict.has(c):
		dict[c] = []
	dict[c].append([rot * v0, rot * v1, rot * v2, rot * v3])

func _set_tools_visible(vis: bool):
	if _right_tool:
		_right_tool.visible = vis
	if _left_tool:
		_left_tool.visible = vis

func _create_collision():
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.6, 1.7, 0.6)
	col.shape = shape
	col.position.y = 0.85
	add_child(col)

func _create_head_label():
	_head_label = Label3D.new()
	_head_label.font_size = 20
	_head_label.outline_size = 5
	_head_label.modulate = Color(1.0, 1.0, 1.0, 0.9)
	_head_label.outline_modulate = Color(0, 0, 0, 0.8)
	_head_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_head_label.no_depth_test = true
	_head_label.position = Vector3(0, 2.3, 0)
	_head_label.text = ""
	add_child(_head_label)

func _update_head_label():
	if not _head_label:
		return
	var prof_name = VProfession.get_profession_name(profession)
	var text = ""
	match current_activity:
		VProfession.Activity.WORK:
			if _task_status != "":
				text = prof_name + " - " + _task_status
			else:
				text = prof_name + " - Au travail"
		VProfession.Activity.SLEEP:
			text = prof_name + " - Zzz..."
		VProfession.Activity.GO_HOME:
			text = prof_name + " - Rentre"
		VProfession.Activity.GATHER:
			text = prof_name + " - Balade"
		VProfession.Activity.WANDER:
			text = prof_name + " - Explore"

	# Afficher la faim si critique
	if _is_starving:
		text = prof_name + " - Faim!"
	elif hunger < HUNGER_THRESHOLD_EAT:
		text += " (faim)"

	_head_label.text = text

	# Couleur selon l'activité + faim
	if _is_starving:
		_head_label.modulate = Color(1.0, 0.2, 0.2, 0.9)  # rouge
	elif hunger < HUNGER_THRESHOLD_EAT:
		_head_label.modulate = Color(1.0, 0.6, 0.2, 0.9)  # orange
	else:
		match current_activity:
			VProfession.Activity.WORK:
				_head_label.modulate = Color(1.0, 0.9, 0.3, 0.9)  # jaune
			VProfession.Activity.SLEEP:
				_head_label.modulate = Color(0.5, 0.5, 1.0, 0.7)  # bleu
			_:
				_head_label.modulate = Color(1.0, 1.0, 1.0, 0.8)  # blanc

# ============================================================
# PHYSICS PROCESS — dispatch par activité
# ============================================================

func _get_game_speed() -> float:
	if _day_night and _day_night.has_method("get_speed_multiplier"):
		return _day_night.get_speed_multiplier()
	return 1.0

func _physics_process(delta):
	# Gravité (toujours en temps réel)
	if not is_on_floor():
		velocity.y -= gravity_val * delta

	# Vitesse de déplacement adaptée au multiplicateur (cap à ×3 pour éviter la physique cassée)
	var game_speed = _get_game_speed()
	move_speed = _base_move_speed * minf(game_speed, 3.0)

	# Vérifier le schedule — accéléré par la vitesse du jeu
	_schedule_timer += delta * game_speed
	if _schedule_timer >= 2.0:
		_schedule_timer = 0.0
		_update_schedule()

	# Mettre à jour le label au-dessus de la tête (toujours en temps réel)
	_label_update_timer += delta
	if _label_update_timer >= 0.5:
		_label_update_timer = 0.0
		_update_head_label()

	# === Retour surface mineur ===
	if _returning_to_surface:
		_behavior_return_to_surface(delta)
		move_and_slide()
		return

	# === Faim ===
	_update_hunger(delta)

	# Dispatcher selon l'activité courante — delta normal pour le mouvement,
	# le game_speed est utilisé DANS les behaviors pour les timers de travail uniquement
	match current_activity:
		VProfession.Activity.WANDER:
			_behavior_wander(delta)
		VProfession.Activity.WORK:
			_behavior_work(delta)
		VProfession.Activity.GATHER:
			_behavior_gather(delta)
		VProfession.Activity.GO_HOME:
			_behavior_go_home(delta)
		VProfession.Activity.SLEEP:
			_behavior_sleep(delta)
		_:
			_behavior_wander(delta)

	move_and_slide()

# ============================================================
# FAIM
# ============================================================

func _update_hunger(delta):
	# Drain de faim
	var drain = HUNGER_DRAIN_REST
	if current_activity == VProfession.Activity.WORK:
		drain = HUNGER_DRAIN_WORK
	hunger = maxf(0.0, hunger - drain * delta * _get_game_speed())

	# Ralentissement si très affamé (appliqué sur _base_move_speed, le game_speed s'applique en amont)
	if hunger < HUNGER_THRESHOLD_SLOW:
		_base_move_speed = 1.0  # moitié de la vitesse de base (2.0 * 0.5)
	else:
		_base_move_speed = 2.0

	# Famine totale
	_is_starving = hunger <= 0.0

	# Tentative de manger pendant GATHER (12h-13h) ou quand la faim est basse
	if hunger < HUNGER_THRESHOLD_EAT and village_manager:
		_try_eat()

func _try_eat():
	if not village_manager:
		return
	# Essayer de manger du pain d'abord
	if village_manager.has_resources(BlockRegistry.BlockType.BREAD, 1):
		village_manager.consume_resources(BlockRegistry.BlockType.BREAD, 1)
		hunger = minf(HUNGER_MAX, hunger + HUNGER_BREAD_RESTORE)
		_show_harvest_label("Miam! +Pain", Vector3i(int(global_position.x), int(global_position.y) + 1, int(global_position.z)))
		return
	# Sinon manger du blé brut
	if village_manager.has_resources(BlockRegistry.BlockType.WHEAT_ITEM, 1):
		village_manager.consume_resources(BlockRegistry.BlockType.WHEAT_ITEM, 1)
		hunger = minf(HUNGER_MAX, hunger + HUNGER_WHEAT_RESTORE)
		_show_harvest_label("Miam! +Blé", Vector3i(int(global_position.x), int(global_position.y) + 1, int(global_position.z)))

# ============================================================
# SCHEDULE
# ============================================================

func _update_schedule():
	if not _day_night:
		return
	var hour = _day_night.get_hour()
	var new_activity = VProfession.get_activity_for_hour(hour, profession)
	if new_activity != current_activity:
		_on_activity_changed(current_activity, new_activity)
		current_activity = new_activity

func _on_activity_changed(old_activity: int, new_activity: int):
	# Libérer le POI si on quitte le travail
	if old_activity == VProfession.Activity.WORK:
		if poi_manager and claimed_poi != INVALID_POI:
			poi_manager.release_poi(claimed_poi)
			claimed_poi = INVALID_POI
		# Mineur souterrain : remonter à la surface au lieu de téléporter
		if village_manager and not current_task.is_empty():
			var task_type = current_task.get("type", "")
			if task_type == "mine_gallery" and _mine_entry_pos != Vector3.ZERO:
				# Sauvegarder la position pour y revenir après la balade
				_mine_resume_pos = global_position
				# Rendre la tâche et les positions
				if _mine_target != INVALID_POS:
					village_manager.release_position(_mine_target)
					_mine_target = INVALID_POS
				village_manager.return_task(current_task)
				current_task = {}
				_returning_to_surface = true
				_return_stuck_timer = 0.0
				_task_status = "Remonte..."
				# Ne pas reset la navigation — on va marcher vers _mine_entry_pos
				return
			# Retourner la tâche village non terminée (cas normal)
			# SAUF les tâches build — on les garde pour reprendre après
			if _mine_target != INVALID_POS:
				village_manager.release_position(_mine_target)
				_mine_target = INVALID_POS
			if current_task.get("type", "") not in ["build", "flatten"]:
				village_manager.return_task(current_task)
				current_task = {}
			# Les tâches build/flatten restent dans current_task pour reprendre demain
		_task_status = ""

	# Reset navigation
	has_target = false
	_arrived_at_target = false
	_target_stuck_timer = 0.0
	_total_stuck_time = 0.0
	_detour_timer = 0.0
	_detour_count = 0
	_wall_impassable = false
	_mine_timer = 0.0
	_build_timer = 0.0
	_build_walk_timer = 0.0
	_at_mine_entrance = false

	# Reprendre le wander timer
	if new_activity == VProfession.Activity.WANDER or new_activity == VProfession.Activity.GATHER:
		_pick_new_wander()

	# Show/hide outils tenus selon l'activité
	_set_tools_visible(new_activity == VProfession.Activity.WORK)

# ============================================================
# COMPORTEMENTS
# ============================================================

func _behavior_wander(delta):
	wander_timer -= delta
	if wander_timer <= 0:
		_pick_new_wander()

	if is_moving:
		_apply_movement(delta)
		_play_anim("walk")
	else:
		_decelerate()
		_play_anim("idle")

func _behavior_sleep(_delta):
	# Rester immobile
	is_moving = false
	_decelerate()
	_play_anim("idle")

func _behavior_gather(delta):
	# Pause déjeuner (12h-13h) — essayer de manger
	if hunger < HUNGER_MAX and village_manager:
		_try_eat()

	# Se diriger vers la place du village si elle existe, sinon errer autour de home
	var gather_center = home_position
	var gather_radius = 15.0
	if village_manager and village_manager.plaza_center != Vector3.ZERO:
		gather_center = village_manager.plaza_center
		gather_radius = float(village_manager.PLAZA_RADIUS) + 3.0

	var dist_to_center = Vector3(global_position.x, 0, global_position.z).distance_to(
		Vector3(gather_center.x, 0, gather_center.z))

	if dist_to_center > gather_radius:
		# Trop loin, aller vers la place
		if _walk_toward(gather_center, delta):
			_pick_new_wander()
			has_target = false
	else:
		# Errer sur la place
		wander_timer -= delta
		if wander_timer <= 0:
			_pick_new_wander()
		if is_moving:
			_apply_movement(delta)
			_play_anim("walk")
		else:
			_decelerate()
			_play_anim("idle")

func _behavior_go_home(delta):
	if _walk_toward(home_position, delta):
		# Arrivé à la maison
		is_moving = false
		_decelerate()
		_play_anim("idle")

func _behavior_work(delta):
	# Si le VillageManager existe, utiliser le système de tâches village
	if village_manager:
		_behavior_village_work(delta)
		return

	# Fallback: ancien système POI
	if claimed_poi == INVALID_POI:
		if poi_manager:
			var nearest = poi_manager.find_nearest_unclaimed(profession, global_position)
			if nearest != INVALID_POI:
				if poi_manager.claim_poi(nearest, self):
					claimed_poi = nearest
					has_target = false
					_arrived_at_target = false
		if claimed_poi == INVALID_POI:
			_behavior_wander(delta)
			return

	var poi_world = Vector3(claimed_poi.x + 0.5, claimed_poi.y, claimed_poi.z + 0.5)

	if not _arrived_at_target:
		if _walk_toward(poi_world, delta):
			_arrived_at_target = true
		return

	var dir_to_poi = poi_world - global_position
	if dir_to_poi.length_squared() > 0.01:
		rotation.y = atan2(dir_to_poi.x, dir_to_poi.z) + PI

	is_moving = false
	_decelerate()
	var work_anim = VProfession.get_work_anim(profession)
	_play_anim(work_anim)

# ============================================================
# VILLAGE WORK — exécution des tâches du VillageManager
# ============================================================

func _behavior_village_work(delta):
	# Si famine totale → arrêter de travailler
	if _is_starving:
		_task_status = "Faim!"
		is_moving = false
		_decelerate()
		_play_anim("idle")
		return

	# Cooldown après un scan qui n'a rien trouvé (évite les scans coûteux en boucle)
	if _search_cooldown > 0.0:
		_search_cooldown -= delta
		_behavior_wander(delta)
		return

	# Pas de tâche -> en demander une correspondant à notre profession
	if current_task.is_empty():
		current_task = village_manager.get_next_task_for(profession)
		if current_task.is_empty():
			_task_status = "Attend"
			_search_cooldown = 3.0  # attendre 3s avant de redemander
			_behavior_wander(delta)
			return
		# Log la prise de tâche
		var task_type = current_task.get("type", "?")
		var prof_name = VProfession.get_profession_name(profession)
		# Log uniquement les tâches notables (pas harvest/mine_gallery qui spamment)
		if task_type not in ["harvest", "mine_gallery", "mine", "farm_harvest"]:
			print("%s: prend tâche '%s'" % [prof_name, task_type])
		# Reset navigation
		has_target = false
		_arrived_at_target = false
		_mine_timer = 0.0
		_mine_target = INVALID_POS
		_mine_entry_pos = Vector3.ZERO
		_at_mine_entrance = false

	# Dispatcher par type de tâche
	match current_task.get("type", ""):
		"harvest":
			_execute_harvest(delta)
		"mine":
			_execute_mine(delta)
		"mine_gallery":
			_execute_mine_gallery(delta)
		"craft":
			_execute_craft(delta)
		"place_workstation":
			_execute_place_workstation(delta)
		"build":
			_execute_build(delta)
		"build_path":
			_execute_build_path(delta)
		"farm_create":
			_execute_farm_create(delta)
		"farm_harvest":
			_execute_farm_harvest(delta)
		"flatten":
			_execute_flatten(delta)
		_:
			current_task = {}

func _execute_harvest(delta):
	# Trouver un tronc d'arbre à couper
	if _mine_target == INVALID_POS:
		# Cooldown pour éviter les scans coûteux chaque frame
		if _search_cooldown > 0.0:
			_search_cooldown -= delta
			_task_status = "Cherche du bois..."
			_behavior_wander(delta)
			return
		# D'abord chercher un tronc PROCHE (rayon 4 blocs, sans exclusion)
		var nearby = _find_nearest_trunk_around(global_position, 4.0)
		if nearby != INVALID_POS:
			_mine_target = nearby
		else:
			# Rien de proche — chercher plus loin avec le scan village
			_mine_target = village_manager.find_nearest_block(5, global_position, 40.0, 0.0)
		if _mine_target == INVALID_POS:
			_task_status = "Cherche du bois..."
			village_manager.return_task(current_task)
			current_task = {}
			_search_cooldown = SEARCH_COOLDOWN_DURATION
			return
		village_manager.claim_position(_mine_target)
		has_target = true
		_arrived_at_target = false
		_mine_timer = 0.0

	# Marcher vers l'arbre
	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)
	_task_status = "[%s] Bois" % village_manager.get_tool_tier_label("Hache")

	if not _arrived_at_target:
		var xz_dist = Vector2(global_position.x - target_world.x, global_position.z - target_world.z).length()
		if xz_dist < 2.5:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	# Arrivé -> miner le bloc
	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	var block_type = world_manager.get_block_at_position(Vector3(_mine_target.x, _mine_target.y, _mine_target.z))
	if block_type == BlockRegistry.BlockType.AIR:
		# Bloc déjà cassé — chercher un autre tronc à proximité immédiate
		village_manager.release_position(_mine_target)
		var next_trunk = _find_nearest_trunk_around(Vector3(_mine_target.x, _mine_target.y, _mine_target.z), 3.0)
		if next_trunk != INVALID_POS:
			_mine_target = next_trunk
			village_manager.claim_position(_mine_target)
			_mine_timer = 0.0
		else:
			_mine_target = INVALID_POS
			_arrived_at_target = false
			_mine_timer = 0.0
		return

	_mine_timer += delta * _get_game_speed()
	var mine_time = village_manager.get_mine_time(block_type)

	if _mine_timer >= mine_time:
		# Casser le bloc
		var last_pos = _mine_target
		village_manager.break_block(_mine_target)
		village_manager.add_resource(_mined_drop(block_type))
		village_manager.release_position(_mine_target)
		_show_harvest_label("+1", _mine_target)

		# Chercher le prochain tronc à proximité (même arbre ou arbre voisin)
		var next_trunk = _find_nearest_trunk_around(Vector3(last_pos.x, last_pos.y, last_pos.z), 3.0)
		if next_trunk != INVALID_POS:
			# Si le prochain tronc est sur une colonne XZ différente, c'est un autre arbre
			# → nettoyer les feuilles de l'arbre qu'on vient de finir
			if next_trunk.x != last_pos.x or next_trunk.z != last_pos.z:
				_harvest_leaves_around(last_pos)
			_mine_target = next_trunk
			village_manager.claim_position(_mine_target)
			_arrived_at_target = false  # remarcher vers le nouveau tronc
			_mine_timer = 0.0
		else:
			# Plus aucun tronc autour — casser les feuilles et chercher plus loin
			_harvest_leaves_around(last_pos)
			_mine_target = INVALID_POS
			_arrived_at_target = false
			_mine_timer = 0.0

func _harvest_leaves_around(center_pos: Vector3i):
	# Leaf decay style Minecraft : détruit toutes les feuilles orphelines autour du tronc abattu.
	# Une feuille est orpheline si aucun tronc n'existe dans un rayon de 4 blocs (Manhattan).
	# BATCHED : modifie directement chunk.blocks, rebuild 1 seule fois par chunk.
	var leaf_set = { 6: true, 44: true, 45: true, 46: true, 47: true, 48: true, 49: true }
	var wood_set = { 5: true, 32: true, 33: true, 34: true, 35: true, 36: true, 42: true }

	# Scan élargi : rayon 8, grande portée verticale (feuilles souvent sous le sommet)
	var scan_r = 8
	var scan_h_min = -12
	var scan_h_max = 8

	# Phase 1 : scanner la zone, collecter feuilles ET troncs
	var leaf_positions: Array = []
	var trunk_positions: Array = []
	for dy in range(scan_h_min, scan_h_max):
		for dx in range(-scan_r, scan_r + 1):
			for dz in range(-scan_r, scan_r + 1):
				var pos = Vector3i(center_pos.x + dx, center_pos.y + dy, center_pos.z + dz)
				var bt = world_manager.get_block_at_position(Vector3(pos.x, pos.y, pos.z))
				if leaf_set.has(bt):
					leaf_positions.append(pos)
				elif wood_set.has(bt):
					trunk_positions.append(pos)

	if leaf_positions.is_empty():
		return

	# Phase 2 : identifier les feuilles orphelines (aucun tronc à distance Manhattan ≤ 4)
	var orphan_leaves: Array = []
	for leaf_pos in leaf_positions:
		var has_trunk = false
		for trunk_pos in trunk_positions:
			var dist = abs(leaf_pos.x - trunk_pos.x) + abs(leaf_pos.y - trunk_pos.y) + abs(leaf_pos.z - trunk_pos.z)
			if dist <= 4:
				has_trunk = true
				break
		if not has_trunk:
			orphan_leaves.append(leaf_pos)

	if orphan_leaves.is_empty():
		return

	# Phase 3 : détruire les feuilles orphelines en batch (1 rebuild par chunk)
	var affected_chunks: Dictionary = {}
	for leaf_pos in orphan_leaves:
		var cx = floori(float(leaf_pos.x) / 16.0)
		var cz = floori(float(leaf_pos.z) / 16.0)
		var chunk_key = Vector3i(cx, 0, cz)
		if world_manager.chunks.has(chunk_key):
			var chunk = world_manager.chunks[chunk_key]
			var lx = leaf_pos.x - cx * 16
			var lz = leaf_pos.z - cz * 16
			if lx < 0:
				lx += 16
			if lz < 0:
				lz += 16
			chunk.blocks[lx * 4096 + lz * 256 + leaf_pos.y] = 0  # AIR
			chunk.is_modified = true
			affected_chunks[chunk_key] = chunk

	# Rebuild mesh UNE SEULE FOIS par chunk affecté
	for chunk in affected_chunks.values():
		chunk._rebuild_mesh()

	# Feuilles détruites — pas d'ajout à l'inventaire (inutile, pollue le stock)

func _find_nearest_trunk_around(from: Vector3, radius: float) -> Vector3i:
	# Cherche le tronc d'arbre le plus proche dans un rayon 3D
	# Optimisé : Dict lookup pour les types, early exit si trouvé à dist <= 1
	if not world_manager:
		return INVALID_POS
	var wood_set = { 5: true, 32: true, 33: true, 34: true, 35: true, 36: true, 42: true }
	var r = int(ceil(radius))
	var center = Vector3i(int(round(from.x)), int(from.y), int(round(from.z)))
	var best = INVALID_POS
	var best_dist = INF

	# Scan en spirale : d'abord les blocs proches (dy=0 d'abord, puis vers le haut)
	for dy in range(-1, 10):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var pos = Vector3i(center.x + dx, center.y + dy, center.z + dz)
				var bt = world_manager.get_block_at_position(Vector3(pos.x, pos.y, pos.z))
				if wood_set.has(bt):
					if village_manager and village_manager.claimed_positions.has(pos):
						continue
					var d = from.distance_to(Vector3(pos.x, pos.y, pos.z))
					if d < best_dist:
						best_dist = d
						best = pos
						if d <= 1.5:
							return best  # early exit — tronc juste à côté

	return best

const MIN_MINE_DISTANCE_FROM_VILLAGE = 30.0  # ne pas miner à moins de 30 blocs du village

func _execute_mine(delta):
	# Miner un type de bloc spécifique (sable, pierre en surface, etc.)
	if _mine_target == INVALID_POS:
		var block_type = current_task.get("target_block", 3)
		var is_sand = (block_type == 4)  # SAND — pas de restriction distance village
		# Chercher à partir d'un point éloigné du village center (sauf sable)
		var search_from = global_position
		if village_manager and not is_sand:
			var to_center = Vector3(global_position.x - village_manager.village_center.x, 0,
				global_position.z - village_manager.village_center.z)
			var dist_to_center = to_center.length()
			if dist_to_center < MIN_MINE_DISTANCE_FROM_VILLAGE:
				var dir_away = to_center.normalized() if to_center.length() > 0.1 else Vector3(1, 0, 0)
				search_from = village_manager.village_center + dir_away * MIN_MINE_DISTANCE_FROM_VILLAGE
				search_from.y = global_position.y
		var search_radius = 72.0 if is_sand else 20.0  # rayon élargi pour le sable (~5 chunks)
		_mine_target = village_manager.find_nearest_surface_block(block_type, search_from, search_radius, is_sand)
		if _mine_target == INVALID_POS:
			_task_status = "Cherche sable..." if is_sand else "Cherche..."
			village_manager.return_task(current_task)
			current_task = {}
			_search_cooldown = SEARCH_COOLDOWN_DURATION
			return
		village_manager.claim_position(_mine_target)
		has_target = true
		_arrived_at_target = false
		_mine_timer = 0.0

	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)
	var mine_block_type = current_task.get("target_block", 3)
	if mine_block_type == 4:
		_task_status = "[Pelle] Sable"
	else:
		_task_status = "[%s] Mine" % village_manager.get_tool_tier_label("Pioche")

	if not _arrived_at_target:
		var dist = global_position.distance_to(target_world)
		if dist < 3.0:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	var block_type = world_manager.get_block_at_position(Vector3(_mine_target.x, _mine_target.y, _mine_target.z))
	if block_type == BlockRegistry.BlockType.AIR:
		village_manager.release_position(_mine_target)
		_mine_target = INVALID_POS
		current_task = {}
		return

	_mine_timer += delta * _get_game_speed()
	var mine_time = village_manager.get_mine_time(block_type)

	if _mine_timer >= mine_time:
		village_manager.break_block(_mine_target)
		if not _is_junk_block(block_type):
			village_manager.add_resource(_mined_drop(block_type))
		village_manager.release_position(_mine_target)
		_show_harvest_label("+1", _mine_target)
		pass  # Supprimé : trop fréquent pour le log
		_mine_target = INVALID_POS
		_mine_timer = 0.0
		current_task = {}

var _at_mine_entrance: bool = false  # le mineur est arrivé à l'entrée de mine

func _execute_mine_gallery(delta):
	# MINAGE SÉQUENTIEL — suit le mine_plan pré-calculé par VillageManager.
	#
	# Le mine_plan est un Array de Vector3i ordonné de haut en bas.
	# Chaque marche = 4 blocs (2 colonnes × 2 hauteurs), puis descente de 1.
	# Les blocs sont toujours adjacents au PNJ car il les mine dans l'ordre.
	#
	# Flow simple :
	#   1. Marcher vers l'entrée de mine (30 blocs du village)
	#   2. Demander le prochain bloc au plan séquentiel
	#   3. Si le bloc est à portée (< 6 blocs) → miner
	#      Si le bloc est trop loin → marcher vers lui (horizontalement)
	#   4. Boucler

	# Mémoriser l'entrée de mine pour le retour surface le soir
	if _mine_entry_pos == Vector3.ZERO:
		if village_manager.mine_entrance != INVALID_POS:
			_mine_entry_pos = Vector3(village_manager.mine_entrance.x + 0.5, village_manager.mine_entrance.y + 1, village_manager.mine_entrance.z + 0.5)
		else:
			_mine_entry_pos = global_position

	_task_status = "[%s] Mine" % village_manager.get_tool_tier_label("Pioche")

	# Phase 1: Se rendre à la mine (resume_pos si dispo, sinon entrée)
	if not _at_mine_entrance:
		var walk_target = _mine_entry_pos
		if _mine_resume_pos != Vector3.ZERO:
			walk_target = _mine_resume_pos
		var p_dx = global_position.x - walk_target.x
		var p_dz = global_position.z - walk_target.z
		var dist_h = sqrt(p_dx * p_dx + p_dz * p_dz)
		if dist_h < 3.0:
			_at_mine_entrance = true
			_mine_resume_pos = Vector3.ZERO  # consommé
		else:
			# Téléportation en mode rapide (×2+)
			if _get_game_speed() >= 2.0:
				global_position = Vector3(walk_target.x, walk_target.y, walk_target.z)
				_at_mine_entrance = true
				_mine_resume_pos = Vector3.ZERO
			else:
				_task_status = "[%s] Vers mine..." % village_manager.get_tool_tier_label("Pioche")
				# Mode berserker : casser TOUT sur le chemin (0 détour)
				_berserker_walk_toward(walk_target, delta)
				return

	# Phase 2: Vérifier que le stockpile n'est pas saturé, puis obtenir le prochain bloc
	if _mine_target == INVALID_POS:
		if village_manager.is_mine_stock_full():
			_task_status = "Stock plein — pause mine"
			current_task = {}
			_at_mine_entrance = false
			return
		_mine_target = village_manager.get_next_mine_block()
		if _mine_target == INVALID_POS:
			# Pas de bloc dispo — attendre au lieu d'abandonner
			_mine_timer += delta * _get_game_speed()
			_task_status = "[%s] Mine: attente..." % village_manager.get_tool_tier_label("Pioche")
			if _mine_timer > 10.0:
				# Après 10s d'attente, rendre la tâche
				_task_status = "Mine OK"
				current_task = {}
				_mine_timer = 0.0
			return
		village_manager.claim_position(_mine_target)
		_mine_timer = 0.0

	# Phase 3: Se rapprocher du bloc si nécessaire
	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)
	var dx = global_position.x - target_world.x
	var dz = global_position.z - target_world.z
	var dist_h = sqrt(dx * dx + dz * dz)
	var dy = global_position.y - target_world.y  # positif = mineur AU-DESSUS du bloc

	# En mode rapide (×2+), téléporter le mineur directement au bloc cible
	var game_speed = _get_game_speed()
	if game_speed >= 2.0 and (dy > 6.0 or dist_h > 5.0):
		global_position = Vector3(target_world.x, target_world.y + 1, target_world.z)
		# Pas de return — on enchaîne directement avec le minage ci-dessous

	elif dy > 6.0 and dist_h > 3.0:
		# Mineur très au-dessus du bloc cible — il est en surface ou en haut de l'escalier.
		# D'abord aller à l'entrée de mine, puis descendre l'escalier naturellement.
		var entry_dx = global_position.x - _mine_entry_pos.x
		var entry_dz = global_position.z - _mine_entry_pos.z
		var entry_dist = sqrt(entry_dx * entry_dx + entry_dz * entry_dz)
		if entry_dist > 3.0:
			# Pas encore à l'entrée — y aller d'abord
			_task_status = "[%s] Vers mine..." % village_manager.get_tool_tier_label("Pioche")
			_berserker_walk_toward(_mine_entry_pos, delta)
		else:
			# À l'entrée — descendre vers le bloc cible via l'escalier
			_task_status = "[%s] Descend..." % village_manager.get_tool_tier_label("Pioche")
			_berserker_walk_toward(target_world, delta)
		_mine_timer += delta  # timeout en temps RÉEL (pas accéléré)
		if _mine_timer > 45.0:
			print("Mineur: skip bloc trop profond à %s (dy=%.1f)" % [str(_mine_target), dy])
			village_manager.release_position(_mine_target)
			_mine_target = INVALID_POS
			_mine_timer = 0.0
		return

	elif dist_h > 5.0:
		# Bloc trop loin horizontalement — berserker pour y aller
		_berserker_walk_toward(target_world, delta)
		_mine_timer += delta  # timeout en temps RÉEL (pas accéléré)
		if _mine_timer > 30.0:
			print("Mineur: skip bloc inaccessible à %s (dist_h=%.1f)" % [str(_mine_target), dist_h])
			village_manager.release_position(_mine_target)
			_mine_target = INVALID_POS
			_mine_timer = 0.0
		return

	# Phase 4: Miner le bloc
	# Le bloc est à portée — on peut le miner même s'il est sous nos pieds ou devant
	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	var block_type = world_manager.get_block_at_position(Vector3(_mine_target.x, _mine_target.y, _mine_target.z))
	if block_type == BlockRegistry.BlockType.AIR or block_type == BlockRegistry.BlockType.WATER:
		# Bloc déjà vide — passer au suivant
		village_manager.release_position(_mine_target)
		_mine_target = INVALID_POS
		_mine_timer = 0.0
		return

	_mine_timer += delta * _get_game_speed()
	var mine_time = village_manager.get_mine_time(block_type)

	if _mine_timer >= mine_time:
		village_manager.break_block(_mine_target)
		if not _is_junk_block(block_type):
			village_manager.add_resource(_mined_drop(block_type))
		village_manager.release_position(_mine_target)
		_show_harvest_label("+1", _mine_target)
		var prof_name = VProfession.get_profession_name(profession)
		pass  # Supprimé : trop fréquent pour le log
		_mine_target = INVALID_POS
		_mine_timer = 0.0


func _execute_craft(delta):
	var recipe_name = current_task.get("recipe_name", "")
	if recipe_name == "":
		current_task = {}
		return
	_task_status = "[Craft] %s" % recipe_name

	# Si un workstation est placé (furnace ou crafting_table), marcher vers lui d'abord
	if not _arrived_at_target:
		var ws_pos = Vector3.ZERO
		var found_ws = false
		# Chercher la workstation du forgeron
		for ws_type in [21, 12, 22, 23, 24]:  # FURNACE, CRAFTING_TABLE, STONE/IRON/GOLD
			if village_manager.placed_workstations.has(ws_type):
				var pos = village_manager.placed_workstations[ws_type]
				ws_pos = Vector3(pos.x + 0.5, pos.y, pos.z + 0.5)
				found_ws = true
				break

		if found_ws:
			var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
				Vector3(ws_pos.x, 0, ws_pos.z))
			if dist > 2.5:
				# Si trop loin verticalement (coincé dans la mine), téléport direct
				var vertical_diff = absf(global_position.y - ws_pos.y)
				if vertical_diff > 6.0 or (_total_stuck_time > 10.0 and dist > 8.0):
					global_position = ws_pos + Vector3(0, 1, 0)
					_total_stuck_time = 0.0
					_arrived_at_target = true
				else:
					_walk_toward(ws_pos, delta)
					return
			else:
				# Aussi téléporter si coincé dans la mine mais proche en XZ
				var vertical_diff = absf(global_position.y - ws_pos.y)
				if vertical_diff > 6.0:
					global_position = ws_pos + Vector3(0, 1, 0)
					_total_stuck_time = 0.0
		_arrived_at_target = true

	# Arrivé au workstation → animation + craft
	is_moving = false
	_decelerate()
	_play_anim("attack")

	# Petit délai de craft (0.8s)
	_mine_timer += delta * _get_game_speed()
	if _mine_timer < 0.8:
		return
	_mine_timer = 0.0

	var success = village_manager.try_craft(recipe_name)
	if success:
		_show_harvest_label("[Craft] " + recipe_name, Vector3i(int(global_position.x), int(global_position.y) + 1, int(global_position.z)))
		# Répéter le craft pour les recettes batch (Planches, Pain) — max 8 fois
		var repeatable = recipe_name == "Planches" or recipe_name == "Pain" or recipe_name == "Verre" or recipe_name == "Lingot de fer" or recipe_name == "Sable"
		if repeatable:
			var repeats = current_task.get("_repeats", 0) + 1
			current_task["_repeats"] = repeats
			_task_status = "[Craft] %s (x%d)" % [recipe_name, repeats]
			if repeats < 8:
				return  # Reste sur la tâche, re-boucle avec nouveau timer
	else:
		# Craft échoué — ne PAS remettre en queue, l'évaluation re-créera la tâche
		# quand les ressources seront disponibles. Évite le spam "prend tâche 'craft'"
		_search_cooldown = SEARCH_COOLDOWN_DURATION
	current_task = {}
	_arrived_at_target = false

func _execute_place_workstation(delta):
	var block_type = current_task.get("target_block", -1)
	if block_type < 0 or not village_manager.has_resources(block_type, 1):
		current_task = {}
		return

	_task_status = "[Place] Atelier"

	# Trouver un emplacement
	if not current_task.has("place_pos"):
		var spot = village_manager.find_flat_spot_near_center()
		if spot == INVALID_POS:
			village_manager.return_task(current_task)
			current_task = {}
			return
		current_task["place_pos"] = spot

	var place_pos = current_task["place_pos"]
	var target_world = Vector3(place_pos.x + 0.5, place_pos.y, place_pos.z + 0.5)

	# Marcher vers l'emplacement
	if not _arrived_at_target:
		var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
			Vector3(target_world.x, 0, target_world.z))
		if dist < 2.5:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	# Placer le bloc
	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	village_manager.consume_resources(block_type, 1)
	village_manager.place_workstation_at(block_type, place_pos)
	_show_harvest_label("Workstation!", place_pos)
	current_task = {}

func _execute_build(delta):
	_task_status = "[%s] Construction" % village_manager.get_tool_tier_label("Marteau")
	var block_list = current_task.get("block_list", [])
	var block_index = current_task.get("block_index", 0)
	var origin = current_task.get("origin", Vector3i.ZERO)

	if block_index >= block_list.size():
		# Construction terminée
		var bp_index = current_task.get("blueprint_index", 0)
		if bp_index < village_manager.BLUEPRINTS.size():
			var bp = village_manager.BLUEPRINTS[bp_index]
			village_manager.register_built_structure(bp["name"], origin, bp["size"])
		current_task = {}
		return

	# Bloc courant à placer
	var block_data = block_list[block_index]
	var world_pos = Vector3i(
		origin.x + block_data[0],
		origin.y + block_data[1],
		origin.z + block_data[2]
	)
	var target_world = Vector3(world_pos.x + 0.5, world_pos.y, world_pos.z + 0.5)

	# Marcher vers la position de construction
	if not _arrived_at_target:
		var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
			Vector3(target_world.x, 0, target_world.z))
		if dist < 3.0:
			_arrived_at_target = true
			_build_walk_timer = 0.0
		else:
			# Téléport de construction : après 8s de marche, téléporter directement
			# (le _walk_toward générique ne fonctionne pas bien dans les structures
			# partiellement construites car les détours empêchent le stuck_time de monter)
			_build_walk_timer += delta
			if _build_walk_timer > 8.0:
				global_position = Vector3(target_world.x, target_world.y + 1, target_world.z)
				_arrived_at_target = true
				_build_walk_timer = 0.0
				_total_stuck_time = 0.0
				_detour_count = 0
				_wall_impassable = false
			else:
				_walk_toward(target_world, delta)
			return

	# Placer le bloc
	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	_build_timer += delta * _get_game_speed()
	if _build_timer >= 0.15:
		_build_timer = 0.0
		# Batch : placer jusqu'à 4 blocs d'un coup (blocs proches)
		var placed = 0
		while placed < 4 and block_index + placed < block_list.size():
			var bd = block_list[block_index + placed]
			var wp = Vector3i(origin.x + bd[0], origin.y + bd[1], origin.z + bd[2])
			village_manager.place_block(wp, bd[3])
			placed += 1
		current_task["block_index"] = block_index + placed
		_arrived_at_target = false  # Bouger vers le prochain bloc
		_build_walk_timer = 0.0

func _execute_build_path(delta):
	_task_status = "[%s] Place" % village_manager.get_tool_tier_label("Marteau")

	# Récupérer le prochain bloc de la place/chemin à poser
	if _mine_target == INVALID_POS:
		var entry = village_manager.get_next_path_block()
		if entry.is_empty():
			# Place terminée
			village_manager.mark_path_complete()
			current_task = {}
			return
		_mine_target = entry[0] as Vector3i
		_path_block_type = entry[1] as int
		has_target = true
		_arrived_at_target = false
		_build_timer = 0.0

	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)

	# Marcher vers la position
	if not _arrived_at_target:
		var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
			Vector3(target_world.x, 0, target_world.z))
		if dist < 2.5:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	_build_timer += delta * _get_game_speed()
	if _build_timer >= 0.1:
		_build_timer = 0.0
		# Batch : poser jusqu'à 6 blocs par tick
		var placed = 0
		while placed < 6:
			# Torches = consomment du stock de torches, autres = consomment de la pierre
			var is_torch = _path_block_type == BlockRegistry.BlockType.TORCH
			if is_torch:
				if village_manager.has_resources(BlockRegistry.BlockType.TORCH, 1):
					village_manager.consume_resources(BlockRegistry.BlockType.TORCH, 1)
					village_manager.place_block(_mine_target, _path_block_type)
					placed += 1
				else:
					break  # Pas de torches en stock, on attend
			elif village_manager.get_total_stone() >= 1:
				village_manager.consume_any_stone(1)
				village_manager.place_block(_mine_target, _path_block_type)
				placed += 1
			else:
				break
			# Bloc suivant
			var entry = village_manager.get_next_path_block()
			if entry.is_empty():
				village_manager.mark_path_complete()
				current_task = {}
				return
			_mine_target = entry[0] as Vector3i
			_path_block_type = entry[1] as int
		if placed > 0:
			_show_harvest_label("Place x%d" % placed, _mine_target)
		_mine_target = INVALID_POS
		_arrived_at_target = false
		if village_manager._path_index >= village_manager._path_blocks.size():
			village_manager.mark_path_complete()
			current_task = {}

func _execute_farm_create(delta):
	_task_status = "[%s] Laboure" % village_manager.get_tool_tier_label("Houe")

	# Trouver la prochaine parcelle à créer
	if _mine_target == INVALID_POS:
		_mine_target = village_manager.get_next_farm_plot_to_create()
		if _mine_target == INVALID_POS:
			# Ferme complète
			current_task = {}
			return
		village_manager.claim_position(_mine_target)
		has_target = true
		_arrived_at_target = false
		_build_timer = 0.0

	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)

	if not _arrived_at_target:
		var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
			Vector3(target_world.x, 0, target_world.z))
		if dist < 2.5:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	_build_timer += delta * _get_game_speed()
	if _build_timer >= 1.0:
		_build_timer = 0.0
		village_manager.create_farm_plot(_mine_target)
		village_manager.release_position(_mine_target)
		_show_harvest_label("Labouré", _mine_target)
		_mine_target = INVALID_POS
		_arrived_at_target = false
		# Enchaîner avec la parcelle suivante
		var next = village_manager.get_next_farm_plot_to_create()
		if next == INVALID_POS:
			current_task = {}

func _execute_farm_harvest(delta):
	_task_status = "[Faucille] Récolte"

	if _mine_target == INVALID_POS:
		var plot = village_manager.get_mature_wheat_plot()
		if plot.is_empty():
			current_task = {}
			return
		_mine_target = plot["pos"]
		village_manager.claim_position(_mine_target)
		has_target = true
		_arrived_at_target = false
		_build_timer = 0.0

	var target_world = Vector3(_mine_target.x + 0.5, _mine_target.y, _mine_target.z + 0.5)

	if not _arrived_at_target:
		var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
			Vector3(target_world.x, 0, target_world.z))
		if dist < 2.5:
			_arrived_at_target = true
		else:
			_walk_toward(target_world, delta)
			return

	_face_target(target_world)
	is_moving = false
	_decelerate()
	_play_anim("attack")

	_build_timer += delta * _get_game_speed()
	if _build_timer >= 0.8:
		_build_timer = 0.0
		# Trouver le plot correspondant et le récolter
		for plot in village_manager.farm_plots:
			if plot["pos"] == _mine_target and plot["stage"] >= village_manager.WHEAT_MAX_STAGE:
				village_manager.harvest_wheat(plot)
				_show_harvest_label("+1 Blé", _mine_target)
				break
		village_manager.release_position(_mine_target)
		_mine_target = INVALID_POS
		_arrived_at_target = false
		# Chercher un autre blé mature
		var next_plot = village_manager.get_mature_wheat_plot()
		if next_plot.is_empty():
			current_task = {}

func _execute_flatten(delta):
	_task_status = "Aplanissement terrain"

	# Obtenir la prochaine colonne à nettoyer
	if _mine_target == INVALID_POS:
		var next = village_manager.get_next_flatten_column()
		if next.is_empty():
			current_task = {}  # flatten terminé
			return
		_mine_target = next["pos"]
		_arrived_at_target = false

	# Marcher en BERSERKER vers la colonne (détruit tout sur le passage)
	var walk_target = Vector3(_mine_target.x + 0.5, global_position.y, _mine_target.z + 0.5)

	if not _arrived_at_target:
		var dist = Vector3(global_position.x, 0, global_position.z).distance_to(
			Vector3(walk_target.x, 0, walk_target.z))
		if dist < 2.0:
			_arrived_at_target = true
		else:
			_berserker_walk_toward(walk_target, delta)
			return

	# Arrivé : nettoyer la colonne entière au-dessus de ref_y (BATCHED)
	var affected_chunks: Dictionary = {}
	village_manager.clear_column_above_ref_batched(_mine_target.x, _mine_target.z, affected_chunks)

	# Nettoyer aussi les 4 voisins (évite les blocs flottants sur les bords)
	for neighbor in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var nx = _mine_target.x + neighbor.x
		var nz = _mine_target.z + neighbor.y
		village_manager.clear_column_above_ref_batched(nx, nz, affected_chunks)
	# Rebuild mesh UNE SEULE FOIS par chunk affecté
	village_manager.flush_affected_chunks(affected_chunks)

	_show_harvest_label("Terrain!", _mine_target)
	_mine_target = INVALID_POS

func _behavior_return_to_surface(delta):
	_task_status = "Remonte..."
	_label_update_timer += delta
	if _label_update_timer >= 0.5:
		_label_update_timer = 0.0
		_update_head_label()

	# En mode rapide, téléport direct à l'entrée de la mine
	var arrived = false
	if _get_game_speed() >= 2.0:
		global_position = Vector3(_mine_entry_pos.x, _mine_entry_pos.y, _mine_entry_pos.z)
		arrived = true
	else:
		arrived = _berserker_walk_toward(_mine_entry_pos, delta)
	if arrived:
		# Arrivé en surface
		_returning_to_surface = false
		_mine_entry_pos = Vector3.ZERO
		_return_stuck_timer = 0.0
		_task_status = ""
		has_target = false
		_arrived_at_target = false
		_target_stuck_timer = 0.0
		_total_stuck_time = 0.0
		_detour_count = 0
		_set_tools_visible(false)
		_pick_new_wander()
		return

	# Safety timeout : si bloqué > 8s → téléporter en surface
	_return_stuck_timer += delta
	if _return_stuck_timer > 8.0:
		global_position = _mine_entry_pos + Vector3(0, 1, 0)
		_returning_to_surface = false
		_mine_entry_pos = Vector3.ZERO
		_return_stuck_timer = 0.0
		_task_status = ""
		has_target = false
		_total_stuck_time = 0.0
		_detour_count = 0
		_set_tools_visible(false)
		_pick_new_wander()

func _face_target(target: Vector3):
	var dir = target - global_position
	if dir.length_squared() > 0.01:
		rotation.y = atan2(dir.x, dir.z) + PI

func _show_harvest_label(text: String, pos: Vector3i):
	var label = Label3D.new()
	label.text = text
	label.font_size = 32
	label.modulate = Color(0.2, 1.0, 0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(pos.x + 0.5, pos.y + 1.5, pos.z + 0.5)
	get_tree().current_scene.add_child(label)

	# Tween: monte et disparaît
	var tween = get_tree().create_tween()
	tween.tween_property(label, "position:y", label.position.y + 1.5, 1.0)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

# ============================================================
# NAVIGATION VERS UNE CIBLE
# ============================================================

func _walk_toward(target: Vector3, delta: float) -> bool:
	var diff = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var dist = diff.length()

	# Arrivé
	if dist < 1.5:
		is_moving = false
		_total_stuck_time = 0.0
		_detour_count = 0
		_wall_impassable = false
		return true

	# Téléportation accélérée en mode rapide (×2+) quand la cible est loin
	var game_speed = _get_game_speed()
	if game_speed >= 2.0 and dist > 8.0:
		global_position = Vector3(target.x, target.y + 1, target.z)
		_total_stuck_time = 0.0
		_detour_count = 0
		_wall_impassable = false
		is_moving = false
		return true

	# Téléportation de secours : seuil relevé à 25s (dernier recours)
	if _total_stuck_time > 25.0:
		var tp_pos = Vector3(target.x, target.y + 1, target.z)
		global_position = tp_pos
		_total_stuck_time = 0.0
		_detour_count = 0
		_detour_timer = 0.0
		_wall_impassable = false
		is_moving = false
		return true

	# Après 7 détours sur harvest/mine : abandonner la cible
	if _detour_count >= 7 and not current_task.is_empty():
		var task_type = current_task.get("type", "")
		if task_type in ["harvest", "mine"]:
			_abandon_current_target()
			return false

	# Après 2 détours : casser le bloc devant pour passer (mode berserker)
	if _detour_count >= 2 and _detour_timer <= 0.0:
		if _try_break_path_block(diff.normalized()):
			_detour_count = 0
			_wall_impassable = false
			_detour_timer = 0.0

	# En détour (contournement d'obstacle)
	if _detour_timer > 0.0:
		_detour_timer -= delta
		wander_direction = _detour_direction
		is_moving = true
		_apply_movement(delta)
		_play_anim("walk")
		return false

	# Marcher vers la cible
	wander_direction = diff.normalized()
	is_moving = true
	_apply_movement(delta)
	_play_anim("walk")

	# Détection immédiate de mur infranchissable → détour sans attendre
	if _wall_impassable:
		_total_stuck_time += delta * 3.0  # compte plus vite quand bloqué par un mur
		_start_smart_detour(diff.normalized())
		return false

	# Détection de blocage en mode cible
	_target_stuck_timer += delta
	if _target_stuck_timer >= 2.0:
		var moved_dist = global_position.distance_to(_last_pos)
		if moved_dist < 0.5:
			_total_stuck_time += 2.0
			_start_smart_detour(diff.normalized())
		else:
			# On bouge — réduire le stuck time et redonner du crédit
			_total_stuck_time = maxf(0.0, _total_stuck_time - 1.0)
			if moved_dist >= 0.5:
				_detour_count = maxi(0, _detour_count - 1)
		_last_pos = global_position
		_target_stuck_timer = 0.0

	return false

func _berserker_walk_toward(target: Vector3, delta: float) -> bool:
	# Walk vers la cible en mode berserker : casse IMMÉDIATEMENT tout bloc sur le chemin
	# Pas de détour, pas de patience — on fonce et on casse.
	var diff = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var dist = diff.length()

	if dist < 1.5:
		is_moving = false
		_total_stuck_time = 0.0
		_detour_count = 0
		_wall_impassable = false
		return true

	# Téléportation accélérée en mode rapide (×2+) quand la cible est loin
	var game_speed = _get_game_speed()
	if game_speed >= 2.0 and dist > 8.0:
		global_position = Vector3(target.x, target.y + 1, target.z)
		_total_stuck_time = 0.0
		_detour_count = 0
		_wall_impassable = false
		is_moving = false
		return true

	# Téléportation de secours après 20s
	if _total_stuck_time > 20.0:
		global_position = Vector3(target.x, target.y + 1, target.z)
		_total_stuck_time = 0.0
		_detour_count = 0
		_wall_impassable = false
		is_moving = false
		return true

	# Forcer le passage : casser les blocs devant immédiatement
	var toward = diff.normalized()
	_try_break_path_block(toward)

	# Marcher
	wander_direction = toward
	is_moving = true
	has_target = true
	_apply_movement(delta)
	_play_anim("walk")

	# Détection de blocage
	_target_stuck_timer += delta
	if _target_stuck_timer >= 1.5:
		var moved_dist = global_position.distance_to(_last_pos)
		if moved_dist < 0.3:
			_total_stuck_time += 1.5
			# Casser dans toutes les directions proches
			_try_break_path_block(toward)
			_try_break_path_block(Vector3(toward.z, 0, -toward.x))  # perpendiculaire
			_try_break_path_block(Vector3(-toward.z, 0, toward.x))
		else:
			_total_stuck_time = maxf(0.0, _total_stuck_time - 1.0)
		_last_pos = global_position
		_target_stuck_timer = 0.0

	return false

# ============================================================
# SMART DETOUR — contournement intelligent d'obstacles
# ============================================================

func _start_smart_detour(toward_target: Vector3):
	_wall_impassable = false
	_detour_count += 1
	var forward = toward_target.normalized()
	var perp_left = Vector3(-forward.z, 0, forward.x)
	var perp_right = Vector3(forward.z, 0, -forward.x)
	var back = -forward

	match _detour_count:
		1:
			_detour_direction = perp_left
			_detour_timer = 2.0
		2:
			_detour_direction = perp_right
			_detour_timer = 2.5
		3:
			_detour_direction = (perp_left + back).normalized()
			_detour_timer = 3.0
		4:
			_detour_direction = (perp_right + back).normalized()
			_detour_timer = 3.0
		5:
			_detour_direction = back
			_detour_timer = 3.5
		_:
			# Détour 6+ : direction aléatoire
			var angle = randf() * TAU
			_detour_direction = Vector3(cos(angle), 0, sin(angle))
			_detour_timer = 3.0

func _abandon_current_target():
	# Libérer la cible claimée
	if _mine_target != INVALID_POS and village_manager:
		village_manager.release_position(_mine_target)
		_mine_target = INVALID_POS

	# Retourner la tâche dans la queue
	if not current_task.is_empty() and village_manager:
		village_manager.return_task(current_task)
		current_task = {}

	# Reset navigation
	has_target = false
	_arrived_at_target = false
	_target_stuck_timer = 0.0
	_total_stuck_time = 0.0
	_detour_timer = 0.0
	_detour_count = 0
	_wall_impassable = false
	_mine_timer = 0.0

	# Cooldown pour éviter de reprendre la même cible
	_search_cooldown = SEARCH_COOLDOWN_DURATION

	var prof_name = VProfession.get_profession_name(profession)
	pass  # Supprimé : trop fréquent pour le log

func _try_break_path_block(toward: Vector3) -> bool:
	# Casse les blocs devant le PNJ pour se frayer un passage
	# Ne casse PAS les blocs dans le périmètre des structures du village
	if not world_manager or not village_manager:
		return false

	var feet_y = int(global_position.y)
	var ahead_pos = global_position + toward * 1.0
	var block_pos_feet = Vector3i(int(round(ahead_pos.x)), feet_y, int(round(ahead_pos.z)))
	var block_pos_head = Vector3i(block_pos_feet.x, feet_y + 1, block_pos_feet.z)

	var broke_any = false

	# Casser le bloc aux pieds (si pas protégé)
	var bt_feet = world_manager.get_block_at_position(Vector3(block_pos_feet.x, block_pos_feet.y, block_pos_feet.z))
	if bt_feet != BlockRegistry.BlockType.AIR and bt_feet != BlockRegistry.BlockType.WATER:
		if not _is_in_village_structure(block_pos_feet):
			village_manager.break_block(block_pos_feet)
			if not _is_junk_block(bt_feet):
				village_manager.add_resource(_mined_drop(bt_feet))
			broke_any = true

	# Casser le bloc à la tête (si pas protégé)
	var bt_head = world_manager.get_block_at_position(Vector3(block_pos_head.x, block_pos_head.y, block_pos_head.z))
	if bt_head != BlockRegistry.BlockType.AIR and bt_head != BlockRegistry.BlockType.WATER:
		if not _is_in_village_structure(block_pos_head):
			village_manager.break_block(block_pos_head)
			if not _is_junk_block(bt_head):
				village_manager.add_resource(_mined_drop(bt_head))
			broke_any = true

	if broke_any:
		_show_harvest_label("+Passage!", block_pos_feet)
		var prof_name = VProfession.get_profession_name(profession)
		pass  # Supprimé : trop fréquent pour le log

	return broke_any

const SOFT_BLOCK_HARDNESS = 0.5  # seuil : casser immédiatement les blocs <= cette dureté

func _try_break_soft_blocks_ahead() -> bool:
	# Casse les blocs mous (feuilles, herbe, neige...) directement devant le PNJ
	# pour éviter des détours inutiles. Ne casse PAS les structures du village.
	if not world_manager or not village_manager:
		return false

	var feet_y = int(global_position.y)
	var ahead_pos = global_position + wander_direction * 0.8
	var block_pos_feet = Vector3i(int(round(ahead_pos.x)), feet_y, int(round(ahead_pos.z)))
	var block_pos_head = Vector3i(block_pos_feet.x, feet_y + 1, block_pos_feet.z)

	var broke_any = false

	# Bloc aux pieds
	var bt_feet = world_manager.get_block_at_position(Vector3(block_pos_feet.x, block_pos_feet.y, block_pos_feet.z))
	if bt_feet != BlockRegistry.BlockType.AIR and bt_feet != BlockRegistry.BlockType.WATER:
		var hardness = BlockRegistry.get_block_hardness(bt_feet as BlockRegistry.BlockType)
		if hardness <= SOFT_BLOCK_HARDNESS and not _is_in_village_structure(block_pos_feet):
			village_manager.break_block(block_pos_feet)
			if not _is_junk_block(bt_feet):
				village_manager.add_resource(_mined_drop(bt_feet))
			broke_any = true

	# Bloc à la tête
	var bt_head = world_manager.get_block_at_position(Vector3(block_pos_head.x, block_pos_head.y, block_pos_head.z))
	if bt_head != BlockRegistry.BlockType.AIR and bt_head != BlockRegistry.BlockType.WATER:
		var hardness = BlockRegistry.get_block_hardness(bt_head as BlockRegistry.BlockType)
		if hardness <= SOFT_BLOCK_HARDNESS and not _is_in_village_structure(block_pos_head):
			village_manager.break_block(block_pos_head)
			if not _is_junk_block(bt_head):
				village_manager.add_resource(_mined_drop(bt_head))
			broke_any = true

	return broke_any

func _is_in_village_structure(pos: Vector3i) -> bool:
	# Vérifie si une position est dans le périmètre d'une structure construite
	if not village_manager:
		return false
	for built in village_manager.built_structures:
		var bo = built["origin"]
		var bs = built["size"]
		# Marge de 1 bloc autour des structures
		if pos.x >= bo.x - 1 and pos.x < bo.x + bs.x + 1 \
			and pos.y >= bo.y - 1 and pos.y < bo.y + bs.y + 1 \
			and pos.z >= bo.z - 1 and pos.z < bo.z + bs.z + 1:
			return true
	# Aussi protéger les workstations placées
	for ws_type in village_manager.placed_workstations:
		var ws_pos = village_manager.placed_workstations[ws_type]
		if pos == ws_pos or pos == Vector3i(ws_pos.x, ws_pos.y + 1, ws_pos.z):
			return true
	return false

# ============================================================
# MOUVEMENT COMMUN (auto-jump, évitement eau/falaises, stuck)
# ============================================================

func _apply_movement(delta):
	if is_on_floor() and world_manager:
		# Throttle block lookups : toutes les 0.15s au lieu de chaque frame
		_nav_check_timer += delta
		if _nav_check_timer >= NAV_CHECK_INTERVAL:
			_nav_check_timer = 0.0
			_wall_impassable = false  # reset avant re-check
			var feet_y = int(global_position.y)
			var ahead_pos = global_position + wander_direction * 0.8
			var ahead_feet = Vector3(ahead_pos.x, feet_y, ahead_pos.z)
			_cached_block_ahead = world_manager.get_block_at_position(ahead_feet.floor())
			_cached_block_above = world_manager.get_block_at_position(Vector3(ahead_feet.x, feet_y + 1, ahead_feet.z).floor())
			_cached_block_below = world_manager.get_block_at_position(Vector3(ahead_feet.x, feet_y - 1, ahead_feet.z).floor())

		# Utiliser les valeurs en cache
		if _cached_block_ahead == BlockRegistry.BlockType.WATER:
			_pick_new_wander()
			is_moving = false
			return
		elif not has_target and _cached_block_ahead == BlockRegistry.BlockType.AIR and _cached_block_below == BlockRegistry.BlockType.AIR:
			_pick_new_wander()
			is_moving = false
			return
		elif _cached_block_ahead != BlockRegistry.BlockType.AIR:
			if _cached_block_above == BlockRegistry.BlockType.AIR:
				# Bloc simple devant — sauter par-dessus
				velocity.y = _jump_velocity
				_wall_impassable = false
			else:
				# Mur de 2+ blocs — casser pour passer (tout bloc, pas juste mous)
				if has_target and _try_break_path_block(wander_direction):
					_wall_impassable = false  # passage dégagé
				elif has_target and _try_break_soft_blocks_ahead():
					_wall_impassable = false
				else:
					_wall_impassable = true

	# Mouvement horizontal — arrêter si mur infranchissable
	if _wall_impassable:
		velocity.x = 0
		velocity.z = 0
	else:
		velocity.x = wander_direction.x * move_speed
		velocity.z = wander_direction.z * move_speed

	# Rotation vers la direction de déplacement
	if wander_direction.length_squared() > 0.01:
		rotation.y = atan2(wander_direction.x, wander_direction.z) + PI

	# Détection de blocage (wander classique, pas en mode cible)
	if not has_target:
		_stuck_timer += delta
		if _stuck_timer >= 1.0:
			var moved_dist = global_position.distance_to(_last_pos)
			if moved_dist < 0.3:
				_pick_new_wander()
			_last_pos = global_position
			_stuck_timer = 0.0

func _decelerate():
	velocity.x = move_toward(velocity.x, 0, move_speed * 2.0)
	velocity.z = move_toward(velocity.z, 0, move_speed * 2.0)
	_stuck_timer = 0.0

func _pick_new_wander():
	wander_timer = randf_range(3.0, 8.0)
	is_moving = randf() > 0.5
	if is_moving:
		var angle = randf() * TAU
		wander_direction = Vector3(cos(angle), 0, sin(angle)).normalized()

# ============================================================
# INFO
# ============================================================

func take_hit(damage: int, knockback: Vector3 = Vector3.ZERO):
	health -= damage
	velocity += knockback
	if health <= 0:
		if claimed_poi != Vector3i(-9999, -9999, -9999) and poi_manager:
			poi_manager.release_poi(claimed_poi)
		if village_manager:
			if _mine_target != INVALID_POS:
				village_manager.release_position(_mine_target)
			if not current_task.is_empty():
				village_manager.return_task(current_task)
			village_manager.unregister_villager(self)
		queue_free()

func get_info_text() -> String:
	var prof_name = VProfession.get_profession_name(profession)
	# Si en mode village work, afficher la tâche en cours
	if village_manager and current_activity == VProfession.Activity.WORK and _task_status != "":
		return "%s - %s" % [prof_name, _task_status]
	var activity_names = {
		VProfession.Activity.WANDER: "Se promène",
		VProfession.Activity.WORK: "Au travail",
		VProfession.Activity.GATHER: "Socialise",
		VProfession.Activity.GO_HOME: "Rentre chez lui",
		VProfession.Activity.SLEEP: "Dort",
	}
	var activity_text = activity_names.get(current_activity, "")
	return "%s - %s" % [prof_name, activity_text]
