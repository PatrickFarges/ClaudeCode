# armor_manager.gd v1.0.0
# Systeme d'armures in-game — genere des mesh overlay skinnes au Skeleton3D Steve
# Supporte 5 materiaux (leather, chain, iron, gold, diamond) x 4 pieces (helmet, chestplate, leggings, boots)
#
# Usage:
#   ArmorManager.equip(skeleton, "helmet", "iron")
#   ArmorManager.equip_set(skeleton, "diamond")
#   ArmorManager.unequip(skeleton, "chestplate")
#   ArmorManager.unequip_all(skeleton)
#
# Changelog:
#   v1.0.0 — Creation initiale : mesh d'armure generes via ArrayMesh,
#            skinning GPU automatique via Skeleton3D, cache mesh/textures

class_name ArmorManager

const BEDROCK_SCALE: float = 1.0 / 16.0
const ARMOR_TEX_W: float = 64.0
const ARMOR_TEX_H: float = 32.0

const ARMOR_DIR = "res://assets/Armor/Bedrock/"
const ARMOR_MATERIAL_FILES = {
	"leather": ["cloth_1.png", "cloth_2.png"],
	"chain": ["chain_1.png", "chain_2.png"],
	"iron": ["iron_1.png", "iron_2.png"],
	"gold": ["gold_1.png", "gold_2.png"],
	"diamond": ["diamond_1.png", "diamond_2.png"],
}

# Definition des pieces d'armure (meme format que character_viewer.py)
# Chaque cube: [bone_name, origin, size, uv_offset, inflate, mirror]
# Coords en pixels Bedrock (1/16 de bloc)
const ARMOR_PIECES = {
	"helmet": {
		"layer": 1,
		"cubes": [
			["head", [-4, 24, -4], [8, 8, 8], [0, 0], 1.0, false],
			["hat", [-4, 24, -4], [8, 8, 8], [32, 0], 1.5, false],
		],
	},
	"chestplate": {
		"layer": 1,
		"cubes": [
			["body", [-4, 12, -2], [8, 12, 4], [16, 16], 1.01, false],
			["rightArm", [-8, 12, -2], [4, 12, 4], [40, 16], 1.0, false],
			["leftArm", [4, 12, -2], [4, 12, 4], [40, 16], 1.0, true],
		],
	},
	"leggings": {
		"layer": 2,
		"cubes": [
			["body", [-4, 12, -2], [8, 12, 4], [16, 16], 0.6, false],
			["rightLeg", [-3.9, 0, -2], [4, 12, 4], [0, 16], 1.2, false],
			["leftLeg", [-0.1, 0, -2], [4, 12, 4], [0, 16], 1.2, true],
		],
	},
	"boots": {
		"layer": 1,
		"cubes": [
			["rightLeg", [-3.9, 0, -2], [4, 12, 4], [0, 16], 1.5, false],
			["leftLeg", [-0.1, 0, -2], [4, 12, 4], [0, 16], 1.5, true],
		],
	},
}

# Node name prefix pour identifier les MeshInstance3D d'armure
const ARMOR_NODE_PREFIX = "armor_"

# Cache statique
static var _mesh_cache: Dictionary = {}      # piece_name -> ArrayMesh
static var _tex_cache: Dictionary = {}       # path -> ImageTexture
static var _mat_cache: Dictionary = {}       # "material_layer" -> StandardMaterial3D


# === API PUBLIQUE ===

static func equip(skeleton: Skeleton3D, piece_name: String, armor_material: String) -> void:
	if not ARMOR_PIECES.has(piece_name):
		push_warning("ArmorManager: piece inconnue '%s'" % piece_name)
		return
	if not ARMOR_MATERIAL_FILES.has(armor_material):
		push_warning("ArmorManager: materiau inconnu '%s'" % armor_material)
		return
	# Retirer l'ancienne piece si presente
	unequip(skeleton, piece_name)
	# Creer ou recuperer le mesh cache
	var mesh = _get_or_create_mesh(skeleton, piece_name)
	if not mesh:
		return
	# Creer le MeshInstance3D
	var mi = MeshInstance3D.new()
	mi.name = ARMOR_NODE_PREFIX + piece_name
	mi.mesh = mesh
	# Materiau avec la texture d'armure
	var layer = ARMOR_PIECES[piece_name]["layer"]
	var mat = _get_or_create_material(armor_material, layer)
	if mat:
		mi.set_surface_override_material(0, mat)
	# Ajouter comme enfant du Skeleton3D — le skinning GPU est automatique
	skeleton.add_child(mi)


static func unequip(skeleton: Skeleton3D, piece_name: String) -> void:
	var node_name = ARMOR_NODE_PREFIX + piece_name
	var existing = skeleton.get_node_or_null(node_name)
	if existing:
		existing.queue_free()


static func equip_set(skeleton: Skeleton3D, armor_material: String) -> void:
	for piece_name in ARMOR_PIECES:
		equip(skeleton, piece_name, armor_material)


static func unequip_all(skeleton: Skeleton3D) -> void:
	for piece_name in ARMOR_PIECES:
		unequip(skeleton, piece_name)


static func has_piece(skeleton: Skeleton3D, piece_name: String) -> bool:
	return skeleton.get_node_or_null(ARMOR_NODE_PREFIX + piece_name) != null


static func get_equipped_pieces(skeleton: Skeleton3D) -> Array:
	var result = []
	for piece_name in ARMOR_PIECES:
		if has_piece(skeleton, piece_name):
			result.append(piece_name)
	return result


# === GENERATION MESH ===

static func _get_or_create_mesh(skeleton: Skeleton3D, piece_name: String) -> ArrayMesh:
	if _mesh_cache.has(piece_name):
		return _mesh_cache[piece_name]
	var mesh = _build_armor_mesh(skeleton, piece_name)
	if mesh:
		_mesh_cache[piece_name] = mesh
	return mesh


static func _build_armor_mesh(skeleton: Skeleton3D, piece_name: String) -> ArrayMesh:
	var piece = ARMOR_PIECES[piece_name]
	var cubes: Array = piece["cubes"]

	var verts = PackedVector3Array()
	var norms = PackedVector3Array()
	var uvs = PackedVector2Array()
	var bones_arr = PackedInt32Array()
	var weights_arr = PackedFloat32Array()

	for cube in cubes:
		var bone_name: String = cube[0]
		var origin: Array = cube[1]
		var size: Array = cube[2]
		var uv_offset: Array = cube[3]
		var inflate: float = cube[4]
		var mirror: bool = cube[5]

		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx < 0:
			push_warning("ArmorManager: bone '%s' introuvable dans le skeleton" % bone_name)
			continue

		var faces = _generate_box_faces(origin, size, uv_offset, inflate, mirror)
		for f in faces:
			verts.append(f[0])
			norms.append(f[1])
			uvs.append(f[2])
			bones_arr.append_array(PackedInt32Array([bone_idx, 0, 0, 0]))
			weights_arr.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))

	if verts.is_empty():
		return null

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones_arr
	arrays[Mesh.ARRAY_WEIGHTS] = weights_arr

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# === GENERATION BOX FACES (meme algorithme que character_viewer.py) ===

static func _generate_box_faces(origin: Array, size: Array, uv_offset: Array, inflate: float, mirror: bool) -> Array:
	var ox: float = origin[0]
	var oy: float = origin[1]
	var oz: float = origin[2]
	var w: float = size[0]
	var h: float = size[1]
	var d: float = size[2]
	var u0: float = uv_offset[0]
	var v0: float = uv_offset[1]
	var S: float = BEDROCK_SCALE

	# Coins du box inflates en espace GLB
	var x0: float = (ox - inflate) * S
	var y0: float = (oy - inflate) * S
	var z0: float = (oz - inflate) * S
	var x1: float = (ox + w + inflate) * S
	var y1: float = (oy + h + inflate) * S
	var z1: float = (oz + d + inflate) * S

	var tw: float = ARMOR_TEX_W
	var th: float = ARMOR_TEX_H
	var result: Array = []

	# Bedrock box UV layout (depuis uv_offset [u0, v0], taille box [w, h, d]):
	# Top:    (u0+d, v0)          taille w x d
	# Bottom: (u0+d+w, v0)        taille w x d
	# Left:   (u0, v0+d)          taille d x h
	# Front:  (u0+d, v0+d)        taille w x h
	# Right:  (u0+d+w, v0+d)      taille d x h
	# Back:   (u0+d+w+d, v0+d)    taille w x h

	# [p0, p1, p2, p3, normal, face_u, face_v, face_w, face_h]
	var faces: Array = [
		# Front (-Z)
		[Vector3(x0,y0,z0), Vector3(x1,y0,z0), Vector3(x1,y1,z0), Vector3(x0,y1,z0),
		 Vector3(0,0,-1), u0+d, v0+d, w, h],
		# Back (+Z)
		[Vector3(x1,y0,z1), Vector3(x0,y0,z1), Vector3(x0,y1,z1), Vector3(x1,y1,z1),
		 Vector3(0,0,1), u0+d+w+d, v0+d, w, h],
		# Right (+X)
		[Vector3(x1,y0,z0), Vector3(x1,y0,z1), Vector3(x1,y1,z1), Vector3(x1,y1,z0),
		 Vector3(1,0,0), u0+d+w, v0+d, d, h],
		# Left (-X)
		[Vector3(x0,y0,z1), Vector3(x0,y0,z0), Vector3(x0,y1,z0), Vector3(x0,y1,z1),
		 Vector3(-1,0,0), u0, v0+d, d, h],
		# Top (+Y)
		[Vector3(x0,y1,z0), Vector3(x1,y1,z0), Vector3(x1,y1,z1), Vector3(x0,y1,z1),
		 Vector3(0,1,0), u0+d, v0, w, d],
		# Bottom (-Y)
		[Vector3(x0,y0,z1), Vector3(x1,y0,z1), Vector3(x1,y0,z0), Vector3(x0,y0,z0),
		 Vector3(0,-1,0), u0+d+w, v0, w, d],
	]

	for fd in faces:
		var p0: Vector3 = fd[0]
		var p1: Vector3 = fd[1]
		var p2: Vector3 = fd[2]
		var p3: Vector3 = fd[3]
		var normal: Vector3 = fd[4]
		var fu: float = fd[5]
		var fv: float = fd[6]
		var fw: float = fd[7]
		var fh: float = fd[8]

		var uv0 = Vector2(fu / tw, (fv + fh) / th)
		var uv1 = Vector2((fu + fw) / tw, (fv + fh) / th)
		var uv2 = Vector2((fu + fw) / tw, fv / th)
		var uv3 = Vector2(fu / tw, fv / th)

		if mirror:
			# Flip UVs horizontalement (swap 0<->1 et 2<->3)
			var tmp = uv0; uv0 = uv1; uv1 = tmp
			tmp = uv2; uv2 = uv3; uv3 = tmp

		# Deux triangles: 0-1-2 et 0-2-3
		var quad_verts = [p0, p1, p2, p3]
		var quad_uvs = [uv0, uv1, uv2, uv3]
		for idx in [0, 1, 2, 0, 2, 3]:
			result.append([quad_verts[idx], normal, quad_uvs[idx]])

	return result


# === MATERIAUX ===

static func _get_or_create_material(armor_material: String, layer: int) -> StandardMaterial3D:
	var key = "%s_%d" % [armor_material, layer]
	if _mat_cache.has(key):
		return _mat_cache[key].duplicate() as StandardMaterial3D
	# Charger la texture
	var files = ARMOR_MATERIAL_FILES[armor_material]
	var tex_file = files[layer - 1]  # layer 1 = index 0, layer 2 = index 1
	var tex_path = ARMOR_DIR + tex_file
	var tex = _load_texture(tex_path)
	if not tex:
		push_warning("ArmorManager: texture introuvable '%s'" % tex_path)
		return null
	# Creer le materiau
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.metallic = 0.0
	mat.roughness = 1.0
	# Cache le materiau de base
	_mat_cache[key] = mat
	return mat.duplicate() as StandardMaterial3D


static func _load_texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	# Essayer load() (Godot import)
	var tex = load(path) as Texture2D
	if tex:
		_tex_cache[path] = tex
		return tex
	# Fallback : charger le PNG via Image
	var img = Image.load_from_file(path)
	if img:
		var itex = ImageTexture.create_from_image(img)
		_tex_cache[path] = itex
		return itex
	return null
