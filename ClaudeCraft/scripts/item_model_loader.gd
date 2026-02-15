extends RefCounted
class_name ItemModelLoader

## Convertit un modèle Minecraft JSON (Blockbench) en ArrayMesh Godot
## Format : elements[].from/to (coords 0-16), faces UV, textures, rotations, display transforms

# Cache des modèles déjà parsés
static var _cache: Dictionary = {}

static func load_model(json_path: String, texture_base_path: String) -> ArrayMesh:
	if _cache.has(json_path):
		return _cache[json_path]

	var abs_path = ProjectSettings.globalize_path(json_path)
	var file = FileAccess.open(abs_path, FileAccess.READ)
	if not file:
		push_warning("[ItemModelLoader] Impossible d'ouvrir: " + json_path)
		return null

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) != OK:
		push_warning("[ItemModelLoader] JSON invalide: " + json_path)
		return null

	var data: Dictionary = json.data
	var mesh = _parse_model(data, texture_base_path)
	if mesh:
		_cache[json_path] = mesh
	return mesh

static func _parse_model(data: Dictionary, texture_base_path: String) -> ArrayMesh:
	var elements: Array = data.get("elements", [])
	if elements.is_empty():
		return null

	var texture_size: Array = data.get("texture_size", [16, 16])
	var tex_w: float = float(texture_size[0])
	var tex_h: float = float(texture_size[1])

	# Charger les textures référencées
	var textures_map: Dictionary = data.get("textures", {})
	var loaded_textures: Dictionary = {}
	for key in textures_map:
		var tex_name: String = textures_map[key]
		# Retirer le préfixe namespace si présent (ex: "MoreIronShortAxes:item/iron_axe/axeBlade1")
		if ":" in tex_name:
			tex_name = tex_name.split(":")[-1]
		var tex_path = texture_base_path.path_join(tex_name + ".png")
		var tex = _load_texture(tex_path)
		if tex:
			loaded_textures[key] = tex
			# Aussi mapper avec "#" prefix
			loaded_textures["#" + key] = tex

	if loaded_textures.is_empty():
		push_warning("[ItemModelLoader] Aucune texture trouvée dans: " + texture_base_path)

	# Obtenir les transforms d'affichage FPS
	var display = data.get("display", {})
	var fp_transform = display.get("firstperson_righthand", {})

	var mesh = ArrayMesh.new()

	# Grouper les éléments par texture pour minimiser les surfaces
	var elements_by_texture: Dictionary = {}

	for element in elements:
		var from: Array = element.get("from", [0, 0, 0])
		var to: Array = element.get("to", [16, 16, 16])
		var faces: Dictionary = element.get("faces", {})
		var rotation_data = element.get("rotation", null)

		for face_name in faces:
			var face: Dictionary = faces[face_name]
			var tex_ref: String = face.get("texture", "#0")
			if not elements_by_texture.has(tex_ref):
				elements_by_texture[tex_ref] = []
			elements_by_texture[tex_ref].append({
				"from": from,
				"to": to,
				"face_name": face_name,
				"face": face,
				"rotation": rotation_data
			})

	# Construire une surface par texture
	for tex_ref in elements_by_texture:
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.cull_mode = BaseMaterial3D.CULL_BACK

		if loaded_textures.has(tex_ref):
			mat.albedo_texture = loaded_textures[tex_ref]
		else:
			mat.albedo_color = Color(0.7, 0.7, 0.7)

		st.set_material(mat)

		for entry in elements_by_texture[tex_ref]:
			_add_face_to_surface(st, entry, tex_w, tex_h)

		st.generate_normals()
		st.commit(mesh)

	# Appliquer le transform firstperson_righthand
	if not fp_transform.is_empty():
		mesh = _apply_display_transform(mesh, fp_transform)

	return mesh

static func _add_face_to_surface(st: SurfaceTool, entry: Dictionary, tex_w: float, tex_h: float):
	var from_arr: Array = entry["from"]
	var to_arr: Array = entry["to"]
	var face_name: String = entry["face_name"]
	var face: Dictionary = entry["face"]
	var rotation_data = entry["rotation"]

	# Coordonnées en unités Minecraft (0-16) → centrer sur l'origine
	var from_v = Vector3(from_arr[0], from_arr[1], from_arr[2]) - Vector3(8, 8, 8)
	var to_v = Vector3(to_arr[0], to_arr[1], to_arr[2]) - Vector3(8, 8, 8)

	# UV du JSON (en pixels) → normaliser en 0-1
	var uv_data: Array = face.get("uv", [0, 0, tex_w, tex_h])
	var uv_min = Vector2(uv_data[0] / tex_w, uv_data[1] / tex_h)
	var uv_max = Vector2(uv_data[2] / tex_w, uv_data[3] / tex_h)

	# Rotation UV de la face
	var uv_rot: int = int(face.get("rotation", 0))

	# Générer les 4 vertices et 4 UV de la face quad
	var verts: Array = _get_face_vertices(face_name, from_v, to_v)
	var uvs: Array = _get_face_uvs(uv_min, uv_max, uv_rot)

	if verts.size() < 4:
		return

	# Appliquer la rotation de l'élément
	if rotation_data:
		var rot_angle = deg_to_rad(float(rotation_data.get("angle", 0)))
		if rot_angle != 0.0:
			var rot_axis_str: String = rotation_data.get("axis", "y")
			var rot_origin_arr: Array = rotation_data.get("origin", [8, 8, 8])
			var rot_origin = Vector3(rot_origin_arr[0], rot_origin_arr[1], rot_origin_arr[2]) - Vector3(8, 8, 8)

			var rot_axis: Vector3
			match rot_axis_str:
				"x": rot_axis = Vector3.RIGHT
				"y": rot_axis = Vector3.UP
				"z": rot_axis = Vector3.BACK
				_: rot_axis = Vector3.UP

			for i in range(verts.size()):
				var v: Vector3 = verts[i] - rot_origin
				v = v.rotated(rot_axis, rot_angle)
				verts[i] = v + rot_origin

	# Émettre 2 triangles (0-1-2, 0-2-3)
	for idx in [0, 1, 2]:
		st.set_uv(uvs[idx])
		st.add_vertex(verts[idx])
	for idx in [0, 2, 3]:
		st.set_uv(uvs[idx])
		st.add_vertex(verts[idx])

static func _get_face_vertices(face_name: String, from_v: Vector3, to_v: Vector3) -> Array:
	# Retourne 4 vertices dans l'ordre pour un quad orienté vers l'extérieur
	match face_name:
		"up":
			return [
				Vector3(from_v.x, to_v.y, from_v.z),
				Vector3(to_v.x, to_v.y, from_v.z),
				Vector3(to_v.x, to_v.y, to_v.z),
				Vector3(from_v.x, to_v.y, to_v.z)
			]
		"down":
			return [
				Vector3(from_v.x, from_v.y, to_v.z),
				Vector3(to_v.x, from_v.y, to_v.z),
				Vector3(to_v.x, from_v.y, from_v.z),
				Vector3(from_v.x, from_v.y, from_v.z)
			]
		"north":
			return [
				Vector3(to_v.x, from_v.y, from_v.z),
				Vector3(from_v.x, from_v.y, from_v.z),
				Vector3(from_v.x, to_v.y, from_v.z),
				Vector3(to_v.x, to_v.y, from_v.z)
			]
		"south":
			return [
				Vector3(from_v.x, from_v.y, to_v.z),
				Vector3(to_v.x, from_v.y, to_v.z),
				Vector3(to_v.x, to_v.y, to_v.z),
				Vector3(from_v.x, to_v.y, to_v.z)
			]
		"east":
			return [
				Vector3(to_v.x, from_v.y, to_v.z),
				Vector3(to_v.x, from_v.y, from_v.z),
				Vector3(to_v.x, to_v.y, from_v.z),
				Vector3(to_v.x, to_v.y, to_v.z)
			]
		"west":
			return [
				Vector3(from_v.x, from_v.y, from_v.z),
				Vector3(from_v.x, from_v.y, to_v.z),
				Vector3(from_v.x, to_v.y, to_v.z),
				Vector3(from_v.x, to_v.y, from_v.z)
			]
	return []

static func _get_face_uvs(uv_min: Vector2, uv_max: Vector2, rotation_deg: int) -> Array:
	# 4 UV de base
	var uvs = [
		Vector2(uv_min.x, uv_max.y),  # bas-gauche
		Vector2(uv_max.x, uv_max.y),  # bas-droite
		Vector2(uv_max.x, uv_min.y),  # haut-droite
		Vector2(uv_min.x, uv_min.y),  # haut-gauche
	]

	# Rotation UV (90, 180, 270)
	var steps = (rotation_deg / 90) % 4
	for _i in range(steps):
		var last = uvs.pop_back()
		uvs.push_front(last)

	return uvs

static func _load_texture(path: String) -> ImageTexture:
	var abs_path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		# Essayer sans le sous-chemin (juste le nom de fichier)
		return null

	var img = Image.new()
	if img.load(abs_path) != OK:
		return null

	img.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)

static func _apply_display_transform(source_mesh: ArrayMesh, display: Dictionary) -> ArrayMesh:
	var rot_arr: Array = display.get("rotation", [0, 0, 0])
	var trans_arr: Array = display.get("translation", [0, 0, 0])
	var scale_arr: Array = display.get("scale", [1, 1, 1])

	var transform = Transform3D()

	# Appliquer l'échelle
	transform = transform.scaled(Vector3(scale_arr[0], scale_arr[1], scale_arr[2]))

	# Appliquer les rotations (euler XYZ en degrés)
	var basis = Basis()
	basis = basis.rotated(Vector3.RIGHT, deg_to_rad(rot_arr[0]))
	basis = basis.rotated(Vector3.UP, deg_to_rad(rot_arr[1]))
	basis = basis.rotated(Vector3.BACK, deg_to_rad(rot_arr[2]))
	transform.basis = basis * transform.basis

	# Appliquer la translation
	transform.origin = Vector3(trans_arr[0], trans_arr[1], trans_arr[2])

	# Transformer tous les vertices du mesh
	var new_mesh = ArrayMesh.new()
	for surface_idx in range(source_mesh.get_surface_count()):
		var arrays = source_mesh.surface_get_arrays(surface_idx)
		var mat = source_mesh.surface_get_material(surface_idx)

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]

		for i in range(vertices.size()):
			vertices[i] = transform * vertices[i]
		if normals:
			for i in range(normals.size()):
				normals[i] = (transform.basis * normals[i]).normalized()

		arrays[Mesh.ARRAY_VERTEX] = vertices
		if normals:
			arrays[Mesh.ARRAY_NORMAL] = normals

		new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		new_mesh.surface_set_material(surface_idx, mat)

	return new_mesh
