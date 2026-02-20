extends Node3D

## Rendu du bras et de l'item en main du joueur (vue FPS)
## Blocs : cube texture par face depuis le pack actif
## Outils : flat sprite Minecraft-style depuis les textures d'items du pack

const GC = preload("res://scripts/game_config.gd")
const ARM_COLOR = Color(0.9, 0.75, 0.65)
const BLOCK_SIZE = 0.28
const ARM_SIZE = Vector3(0.15, 0.55, 0.15)
const BASE_POSITION = Vector3(0.62, -0.42, -0.68)
const SPRINT_OFFSET = Vector3(-0.1, 0.0, -0.05)
const SPRITE_SIZE = 0.38

# Noeuds
var hand_pivot: Node3D
var arm_mesh: MeshInstance3D
var item_holder: Node3D
var current_item_node: Node3D = null

# Animations
var bob_time: float = 0.0
var is_swinging: bool = false
var swing_tween: Tween = null
var swing_progress: float = 0.0
var _smooth_pos := Vector3(0.62, -0.42, -0.68)
var _smooth_rot_x: float = 0.0

# Reference
var player: CharacterBody3D = null

# Cache textures chargees
var _texture_cache: Dictionary = {}
var _sprite_cache: Dictionary = {}

# État arc (bow pulling)
var _holding_bow: bool = false
var _bow_pull: float = 0.0  # 0.0 à 1.0

func _ready():
	player = get_tree().get_first_node_in_group("player")
	_build_hierarchy()

func _build_hierarchy():
	hand_pivot = Node3D.new()
	hand_pivot.name = "HandPivot"
	hand_pivot.position = BASE_POSITION
	add_child(hand_pivot)

	arm_mesh = MeshInstance3D.new()
	arm_mesh.name = "Arm"
	var arm_box = BoxMesh.new()
	arm_box.size = ARM_SIZE
	arm_mesh.mesh = arm_box
	var arm_mat = StandardMaterial3D.new()
	arm_mat.albedo_color = ARM_COLOR
	arm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arm_mesh.material_override = arm_mat
	arm_mesh.layers = 2
	arm_mesh.position = Vector3(0, -0.08, 0)
	hand_pivot.add_child(arm_mesh)

	item_holder = Node3D.new()
	item_holder.name = "ItemHolder"
	item_holder.position = Vector3(0.0, 0.05, 0.0)
	hand_pivot.add_child(item_holder)

func _process(delta: float):
	if not player:
		player = get_tree().get_first_node_in_group("player")
		if not player:
			return
	_update_bobbing(delta)

var _sprint_blend: float = 0.0

func _update_bobbing(delta: float):
	if not player or not hand_pivot:
		return

	var on_floor = player.is_on_floor()
	var moving = player.velocity.length() > 0.5 and on_floor

	var sprint_target = 1.0 if player.is_sprinting else 0.0
	_sprint_blend = lerpf(_sprint_blend, sprint_target, delta * 6.0)

	var target_pos = BASE_POSITION + SPRINT_OFFSET * _sprint_blend

	if moving:
		var speed_mult = 1.3 if player.is_sprinting else 1.0
		var swing_amp = 20.0 if player.is_sprinting else 12.0
		bob_time += delta * speed_mult
		var bob_y = abs(sin(bob_time * 14.0)) * 0.015
		_smooth_pos = target_pos + Vector3(0, bob_y, 0)
		_smooth_rot_x = sin(bob_time * 7.0) * swing_amp
	else:
		bob_time = 0.0
		_smooth_pos = _smooth_pos.lerp(target_pos, delta * 10.0)
		_smooth_rot_x = lerpf(_smooth_rot_x, 0.0, delta * 10.0)

	# MC-style swing overlay (sinusoidal multi-axis arc)
	var swing_rot = _compute_swing_rotation()
	var swing_pos = _compute_swing_position()

	hand_pivot.position = _smooth_pos + swing_pos
	hand_pivot.rotation_degrees = Vector3(_smooth_rot_x + swing_rot.x, swing_rot.y, swing_rot.z)

var _holding_tool: bool = false

func play_swing():
	if is_swinging:
		return
	is_swinging = true
	swing_progress = 0.0

	if swing_tween and swing_tween.is_valid():
		swing_tween.kill()

	swing_tween = create_tween()
	swing_tween.tween_property(self, "swing_progress", 1.0, 0.28)
	swing_tween.tween_callback(func():
		is_swinging = false
		swing_progress = 0.0
	)

func _compute_swing_rotation() -> Vector3:
	if swing_progress <= 0.0:
		return Vector3.ZERO
	var t = swing_progress
	var f = sin(t * t * PI)
	var f1 = sin(sqrt(t) * PI)
	if _holding_tool:
		# MC-style : arc descendant dominant (X) + oscillation Y + twist Z
		return Vector3(f1 * -60.0, f * -15.0, f1 * -15.0)
	else:
		# Blocs / mains vides : coup frontal
		return Vector3(f1 * -40.0, 0.0, 0.0)

func _compute_swing_position() -> Vector3:
	if swing_progress <= 0.0:
		return Vector3.ZERO
	var t = swing_progress
	return Vector3(
		-0.2 * sin(sqrt(t) * PI),
		0.1 * sin(sqrt(t) * TAU),
		-0.1 * sin(t * PI)
	)

# ============================================================
# AFFICHAGE BLOC EN MAIN
# ============================================================

func update_held_item(block_type: BlockRegistry.BlockType):
	_clear_held_item()
	_holding_tool = false

	if block_type == BlockRegistry.BlockType.AIR:
		arm_mesh.visible = true
		return

	arm_mesh.visible = false
	current_item_node = _create_block_cube(block_type)
	if current_item_node:
		item_holder.add_child(current_item_node)

# ============================================================
# AFFICHAGE OUTIL EN MAIN — FLAT SPRITE MINECRAFT-STYLE
# ============================================================

func update_held_item_sprite(tool_type: ToolRegistry.ToolType):
	_clear_held_item()
	_holding_tool = true
	arm_mesh.visible = false

	var tex_path = ToolRegistry.get_item_texture_path(tool_type)
	print("[HandItemRenderer] tool_type=%s tex_path=%s" % [str(tool_type), tex_path])
	if tex_path.is_empty():
		arm_mesh.visible = true
		return

	var sprite_node = _create_item_sprite(tex_path)
	print("[HandItemRenderer] sprite_node=%s" % str(sprite_node))
	if sprite_node:
		current_item_node = sprite_node
		item_holder.add_child(current_item_node)
	else:
		arm_mesh.visible = true

# ============================================================
# AFFICHAGE ARC — Change la texture selon le pull (charge)
# ============================================================

func update_bow_pull(pull: float):
	"""Met à jour la texture de l'arc selon le niveau de charge (0.0 à 1.0)"""
	_bow_pull = pull
	if not _holding_bow:
		return
	# Sélectionner la texture selon les seuils MC
	var tex_name: String
	if pull <= 0.0:
		tex_name = "bow"
	elif pull < 0.65:
		tex_name = "bow_pulling_0"
	elif pull < 0.9:
		tex_name = "bow_pulling_1"
	else:
		tex_name = "bow_pulling_2"

	var tex_path = GC.get_item_texture_path() + tex_name + ".png"
	_rebuild_bow_sprite(tex_path)

func _rebuild_bow_sprite(tex_path: String):
	"""Reconstruit le mesh extrudé de l'arc avec une nouvelle texture"""
	if not current_item_node:
		return
	var abs_path = ProjectSettings.globalize_path(tex_path)
	if not FileAccess.file_exists(abs_path):
		return
	var img = Image.new()
	if img.load(abs_path) != OK:
		return
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != MODEL_GRID or img.get_height() != MODEL_GRID:
		img.resize(MODEL_GRID, MODEL_GRID, Image.INTERPOLATE_NEAREST)
	var mesh = _build_extruded_mesh(img)
	current_item_node.mesh = mesh

func start_bow_pull():
	_holding_bow = true
	_bow_pull = 0.0

func stop_bow_pull():
	_holding_bow = false
	_bow_pull = 0.0
	# Remettre la texture par défaut
	if current_item_node:
		var tex_path = GC.get_item_texture_path() + "bow.png"
		_rebuild_bow_sprite(tex_path)

# ============================================================
# AFFICHAGE NODE 3D ARBITRAIRE (pour food GLB etc.)
# ============================================================

func update_held_tool_node(node: Node3D, hand_rotation := Vector3(-25, -135, 45), hand_scale := 0.35):
	_clear_held_item()
	_holding_tool = false
	arm_mesh.visible = false

	if node == null:
		arm_mesh.visible = true
		return

	_apply_glb_render_settings(node)

	var aabb = _compute_model_aabb(node)
	var max_dim = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if max_dim > 0.001:
		var s = hand_scale / max_dim
		node.scale = Vector3(s, s, s)
		var center = aabb.get_center() * s
		node.position = Vector3(-center.x, -center.y, -center.z)
	else:
		node.scale = Vector3(0.03, 0.03, 0.03)
		node.position = Vector3.ZERO

	node.rotation_degrees = hand_rotation
	current_item_node = node
	item_holder.add_child(current_item_node)

func _clear_held_item():
	if current_item_node:
		current_item_node.queue_free()
		current_item_node = null

# ============================================================
# CREATION DU MODELE 3D EXTRUDE (pixel-extruded Minecraft-style)
# Chaque pixel opaque de la texture est extrude en petit cube 3D
# ============================================================

const EXTRUDE_DEPTH = 0.04  # epaisseur de l'item en unites 3D
const MODEL_GRID = 16  # resolution de la grille d'extrusion (toujours 16x16 comme MC)

func _create_item_sprite(tex_path: String) -> MeshInstance3D:
	var abs_path = ProjectSettings.globalize_path(tex_path)

	if not FileAccess.file_exists(abs_path):
		push_warning("[HandItemRenderer] Texture introuvable: " + tex_path)
		return null

	var img = Image.new()
	if img.load(abs_path) != OK:
		return null

	img.convert(Image.FORMAT_RGBA8)

	# Redimensionner en 16x16 pour la grille d'extrusion (comme MC)
	if img.get_width() != MODEL_GRID or img.get_height() != MODEL_GRID:
		img.resize(MODEL_GRID, MODEL_GRID, Image.INTERPOLATE_NEAREST)

	var mesh = _build_extruded_mesh(img)
	print("[HandItemRenderer] Extruded mesh: %d surfaces" % mesh.get_surface_count())

	var inst = MeshInstance3D.new()
	inst.mesh = mesh
	inst.layers = 2

	# Rotation MC first-person : outil en diagonale, manche bas-droite
	inst.rotation_degrees = Vector3(0, -10, 40)
	inst.position = Vector3(0.03, 0.0, 0.0)

	return inst

func _build_extruded_mesh(img: Image) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var grid = MODEL_GRID
	var pixel_size = SPRITE_SIZE / float(grid)
	var half = SPRITE_SIZE * 0.5
	var half_d = EXTRUDE_DEPTH * 0.5

	# Grouper les pixels par couleur pour minimiser les surfaces/materiaux
	var color_quads: Dictionary = {}  # Color -> Array of [v0,v1,v2,v3,normal]

	for py in range(grid):
		for px in range(grid):
			var c = img.get_pixel(px, py)
			if c.a < 0.5:
				continue

			var x0 = -half + px * pixel_size
			var x1 = x0 + pixel_size
			var y1 = half - py * pixel_size
			var y0 = y1 - pixel_size

			# Face avant (Z+)
			_collect_quad(color_quads, c, 1.0,
				Vector3(x0, y0, half_d), Vector3(x1, y0, half_d),
				Vector3(x1, y1, half_d), Vector3(x0, y1, half_d))
			# Face arriere (Z-)
			_collect_quad(color_quads, c, 1.0,
				Vector3(x1, y0, -half_d), Vector3(x0, y0, -half_d),
				Vector3(x0, y1, -half_d), Vector3(x1, y1, -half_d))
			# Gauche
			if px == 0 or img.get_pixel(px - 1, py).a < 0.5:
				_collect_quad(color_quads, c, 0.7,
					Vector3(x0, y0, -half_d), Vector3(x0, y0, half_d),
					Vector3(x0, y1, half_d), Vector3(x0, y1, -half_d))
			# Droite
			if px == grid - 1 or img.get_pixel(px + 1, py).a < 0.5:
				_collect_quad(color_quads, c, 0.7,
					Vector3(x1, y0, half_d), Vector3(x1, y0, -half_d),
					Vector3(x1, y1, -half_d), Vector3(x1, y1, half_d))
			# Bas
			if py == grid - 1 or img.get_pixel(px, py + 1).a < 0.5:
				_collect_quad(color_quads, c, 0.85,
					Vector3(x0, y0, half_d), Vector3(x0, y0, -half_d),
					Vector3(x1, y0, -half_d), Vector3(x1, y0, half_d))
			# Haut
			if py == 0 or img.get_pixel(px, py - 1).a < 0.5:
				_collect_quad(color_quads, c, 0.85,
					Vector3(x0, y1, -half_d), Vector3(x0, y1, half_d),
					Vector3(x1, y1, half_d), Vector3(x1, y1, -half_d))

	# Construire une surface par couleur unique
	for key in color_quads:
		var quads = color_quads[key]
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = key
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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

	return mesh

func _collect_quad(dict: Dictionary, base_color: Color, shade: float, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3):
	var c = Color(base_color.r * shade, base_color.g * shade, base_color.b * shade, 1.0)
	if not dict.has(c):
		dict[c] = []
	dict[c].append([v0, v1, v2, v3])

# ============================================================
# CREATION DU CUBE BLOC TEXTURE
# ============================================================

func _create_block_cube(block_type: BlockRegistry.BlockType) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.layers = 2

	var faces_data = BlockRegistry.BLOCK_DATA[block_type].get("faces", {})

	if faces_data.size() > 0 and _has_any_texture_file(faces_data):
		mesh_inst.mesh = _build_textured_cube(block_type, faces_data)
	else:
		var box = BoxMesh.new()
		box.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		mesh_inst.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = BlockRegistry.get_block_color(block_type)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_inst.material_override = mat

	mesh_inst.rotation_degrees = Vector3(0, 45, 0)
	return mesh_inst

func _has_any_texture_file(faces: Dictionary) -> bool:
	for key in faces:
		var tex_name = faces[key]
		if not GC.resolve_block_texture(tex_name).is_empty():
			return true
	return false

func _build_textured_cube(block_type: BlockRegistry.BlockType, faces: Dictionary) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var s = BLOCK_SIZE * 0.5

	var face_defs = [
		["top",    [Vector3(-s,s,-s), Vector3(s,s,-s), Vector3(s,s,s), Vector3(-s,s,s)],    Vector3(0,1,0)],
		["bottom", [Vector3(-s,-s,s), Vector3(s,-s,s), Vector3(s,-s,-s), Vector3(-s,-s,-s)], Vector3(0,-1,0)],
		["front",  [Vector3(-s,-s,-s), Vector3(s,-s,-s), Vector3(s,s,-s), Vector3(-s,s,-s)], Vector3(0,0,-1)],
		["back",   [Vector3(s,-s,s), Vector3(-s,-s,s), Vector3(-s,s,s), Vector3(s,s,s)],     Vector3(0,0,1)],
		["right",  [Vector3(s,-s,-s), Vector3(s,-s,s), Vector3(s,s,s), Vector3(s,s,-s)],     Vector3(1,0,0)],
		["left",   [Vector3(-s,-s,s), Vector3(-s,-s,-s), Vector3(-s,s,-s), Vector3(-s,s,s)], Vector3(-1,0,0)],
	]

	var uvs = [Vector2(0,1), Vector2(1,1), Vector2(1,0), Vector2(0,0)]

	for face_def in face_defs:
		var face_name: String = face_def[0]
		var verts: Array = face_def[1]
		var normal: Vector3 = face_def[2]

		var tex_name = BlockRegistry.get_face_texture(block_type, face_name)
		var tint = BlockRegistry.get_block_tint(block_type, face_name)
		var mat = _get_face_material(tex_name, tint)

		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(mat)

		for idx in [0, 1, 2]:
			st.set_normal(normal)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])
		for idx in [0, 2, 3]:
			st.set_normal(normal)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])

		st.commit(mesh)

	return mesh

func _get_face_material(tex_name: String, tint: Color) -> StandardMaterial3D:
	var cache_key = tex_name + str(tint)
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var abs_path = GC.resolve_block_texture(tex_name)

	if not abs_path.is_empty():
		var img = Image.new()
		if img.load(abs_path) == OK:
			img.convert(Image.FORMAT_RGBA8)
			if tint != Color(1,1,1,1):
				for y in range(img.get_height()):
					for x in range(img.get_width()):
						var c = img.get_pixel(x, y)
						img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
			var tex = ImageTexture.create_from_image(img)
			mat.albedo_texture = tex
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			_texture_cache[cache_key] = mat
			return mat

	mat.albedo_color = tint
	_texture_cache[cache_key] = mat
	return mat

# ============================================================
# HELPERS GLB (pour les rares modeles 3D restants — food etc.)
# ============================================================

func _compute_model_aabb(root: Node3D) -> AABB:
	var points: Array = []
	_collect_mesh_points(root, root, points)
	if points.is_empty():
		return AABB(Vector3.ZERO, Vector3(0.1, 0.1, 0.1))
	var aabb = AABB(points[0], Vector3.ZERO)
	for i in range(1, points.size()):
		aabb = aabb.expand(points[i])
	return aabb

func _collect_mesh_points(node: Node, root: Node3D, points: Array):
	if node is MeshInstance3D and node.mesh:
		var mesh_aabb = node.mesh.get_aabb()
		var xform = _get_relative_transform(node as Node3D, root)
		for i in range(8):
			points.append(xform * mesh_aabb.get_endpoint(i))
	for child in node.get_children():
		_collect_mesh_points(child, root, points)

func _get_relative_transform(from_node: Node3D, to_node: Node3D) -> Transform3D:
	if from_node == to_node:
		return Transform3D.IDENTITY
	var xform = from_node.transform
	var current = from_node.get_parent()
	while current != to_node and current != null:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform

func _apply_glb_render_settings(node: Node):
	if node is MeshInstance3D:
		node.layers = 3
	for child in node.get_children():
		_apply_glb_render_settings(child)
