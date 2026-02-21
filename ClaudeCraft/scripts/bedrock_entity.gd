# bedrock_entity.gd — Minecraft Bedrock .geo.json → Godot Node3D hierarchy
# Parses bone structure, builds UV-mapped cube meshes, returns animatable model

const SCALE := 1.0 / 16.0  # Bedrock pixels → Godot units (1 block)

# Cache: geo_path → { "bones_data": Array, "tex_w": float, "tex_h": float }
static var _geo_cache: Dictionary = {}

# ---------------------------------------------------------------------------
#  PUBLIC API
# ---------------------------------------------------------------------------

## Build a complete model from a Bedrock .geo.json + texture.
## Returns a Node3D root with named children for each bone.
## geometry_id: e.g. "geometry.sheep.sheared.v1.8" — empty = first found.
static func build_model(geo_path: String, texture: Texture2D, geometry_id: String = "", skip_bones: Array = []) -> Node3D:
	var geo = _load_geometry(geo_path, geometry_id)
	if geo.is_empty():
		push_warning("[BedrockEntity] No geometry in " + geo_path)
		return null

	# Use texture dimensions as fallback when geometry doesn't specify them
	var tex_w: float = geo["tex_w"]
	var tex_h: float = geo["tex_h"]
	if texture and (tex_w == 64.0 and tex_h == 32.0):
		var real_w := float(texture.get_width())
		var real_h := float(texture.get_height())
		if real_w != tex_w or real_h != tex_h:
			tex_w = real_w
			tex_h = real_h
	var bones_data: Array = geo["bones"]

	# Material shared by all cubes
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var root := Node3D.new()
	root.name = "BedrockModel"

	# Build skip set for fast lookup
	var skip_set: Dictionary = {}
	for sname in skip_bones:
		skip_set[sname] = true

	# First pass: create bone Node3Ds and collect data
	var bone_nodes: Dictionary = {}   # name → Node3D
	var bone_pivots: Dictionary = {}  # name → Array[3] (world-space)
	var bone_parent: Dictionary = {}  # name → parent name
	for bd in bones_data:
		var bname: String = bd.get("name", "unnamed")
		if skip_set.has(bname):
			continue
		var pivot: Array = bd.get("pivot", [0, 0, 0])
		var node := Node3D.new()
		node.name = bname
		bone_nodes[bname] = node
		bone_pivots[bname] = pivot
		bone_parent[bname] = bd.get("parent", "")

	# Accumulated node rotation basis (from "rotation" field only — NOT bind_pose)
	var bone_node_basis: Dictionary = {}  # name → Basis

	# Second pass: parent, position, rotation, mesh
	for bd in bones_data:
		var bname: String = bd.get("name", "unnamed")
		if skip_set.has(bname):
			continue
		var node: Node3D = bone_nodes[bname]
		var pivot: Array = bd.get("pivot", [0, 0, 0])
		var pname: String = bone_parent[bname]

		# KEY DISTINCTION:
		# bind_pose_rotation → mesh-only visual rotation (baked into vertices)
		# rotation → bone node rotation (DOES propagate to children)
		var bind_rot_arr: Array = bd.get("bind_pose_rotation", [0, 0, 0])
		var node_rot_arr: Array = bd.get("rotation", [0, 0, 0])
		var bind_rot_deg := Vector3(bind_rot_arr[0], bind_rot_arr[1], bind_rot_arr[2])
		var node_rot_deg := Vector3(node_rot_arr[0], node_rot_arr[1], node_rot_arr[2])

		# Node rotation basis (only from "rotation" field — affects children)
		var node_basis := Basis.IDENTITY
		if node_rot_deg != Vector3.ZERO:
			node_basis = Basis.from_euler(Vector3(
				deg_to_rad(node_rot_deg.x), deg_to_rad(node_rot_deg.y), deg_to_rad(node_rot_deg.z)))

		# Bind-pose basis (baked into mesh vertices, NOT set as node transform)
		var bind_basis := Basis.IDENTITY
		if bind_rot_deg != Vector3.ZERO:
			bind_basis = Basis.from_euler(Vector3(
				deg_to_rad(bind_rot_deg.x), deg_to_rad(bind_rot_deg.y), deg_to_rad(bind_rot_deg.z)))

		# Position: child offsets need inverse of parent's accumulated NODE rotation
		if pname != "" and bone_nodes.has(pname):
			bone_nodes[pname].add_child(node)
			var pp: Array = bone_pivots[pname]
			var world_offset := Vector3(pivot[0] - pp[0], pivot[1] - pp[1], pivot[2] - pp[2]) * SCALE
			var parent_accum: Basis = bone_node_basis.get(pname, Basis.IDENTITY)
			node.position = parent_accum.inverse() * world_offset
			bone_node_basis[bname] = parent_accum * node_basis
		else:
			root.add_child(node)
			node.position = Vector3(pivot[0], pivot[1], pivot[2]) * SCALE
			bone_node_basis[bname] = node_basis

		# Apply "rotation" to the bone node (propagates to children)
		if node_rot_deg != Vector3.ZERO:
			node.rotation_degrees = node_rot_deg

		# Build cube meshes — bake bind_pose_rotation into vertices
		var mirror_bone: bool = bd.get("mirror", false)
		var cubes: Array = bd.get("cubes", [])
		if cubes.size() > 0:
			var mesh := _build_cubes_mesh(cubes, pivot, tex_w, tex_h, material, mirror_bone, bind_basis)
			if mesh:
				node.add_child(mesh)

	return root


# ---------------------------------------------------------------------------
#  GEOMETRY LOADING / CACHING
# ---------------------------------------------------------------------------

static func _load_geometry(geo_path: String, preferred_id: String) -> Dictionary:
	var cache_key := geo_path + "|" + preferred_id
	if _geo_cache.has(cache_key):
		return _geo_cache[cache_key]

	var file := FileAccess.open(geo_path, FileAccess.READ)
	if not file:
		push_warning("[BedrockEntity] Cannot open: " + geo_path)
		return {}

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("[BedrockEntity] JSON parse error: " + geo_path)
		return {}

	var data: Dictionary = json.data
	var result := {}

	# Format 1.12.0+ — "minecraft:geometry" array
	if data.has("minecraft:geometry"):
		for geo in data["minecraft:geometry"]:
			var desc: Dictionary = geo.get("description", {})
			var gid: String = desc.get("identifier", "")
			if preferred_id == "" or gid == preferred_id:
				result = {
					"tex_w": float(desc.get("texture_width", 64)),
					"tex_h": float(desc.get("texture_height", 32)),
					"bones": geo.get("bones", []),
				}
				break
		if result.is_empty() and data["minecraft:geometry"].size() > 0:
			var geo = data["minecraft:geometry"][0]
			var desc = geo.get("description", {})
			result = {
				"tex_w": float(desc.get("texture_width", 64)),
				"tex_h": float(desc.get("texture_height", 32)),
				"bones": geo.get("bones", []),
			}
	else:
		# Format 1.8.0 — top-level "geometry.xxx" keys
		var tex_w := 64.0
		var tex_h := 32.0
		for key in data.keys():
			if not key.begins_with("geometry."):
				continue
			var gid: String = key.split(":")[0]
			if preferred_id != "" and gid != preferred_id:
				continue
			var gdata: Dictionary = data[key]
			tex_w = float(gdata.get("texturewidth", 64))
			tex_h = float(gdata.get("textureheight", 32))
			result = {
				"tex_w": tex_w,
				"tex_h": tex_h,
				"bones": gdata.get("bones", []),
			}
			break
		if result.is_empty():
			for key in data.keys():
				if key.begins_with("geometry.") and key != "format_version":
					var gdata: Dictionary = data[key]
					result = {
						"tex_w": float(gdata.get("texturewidth", 64)),
						"tex_h": float(gdata.get("textureheight", 32)),
						"bones": gdata.get("bones", []),
					}
					break

	if not result.is_empty():
		_geo_cache[cache_key] = result
	return result


# ---------------------------------------------------------------------------
#  MESH BUILDING
# ---------------------------------------------------------------------------

## Build a single MeshInstance3D containing all cubes for one bone.
## bind_basis: baked into vertex positions (bind_pose_rotation), NOT set as node transform.
static func _build_cubes_mesh(cubes: Array, bone_pivot: Array, tex_w: float, tex_h: float, material: StandardMaterial3D, mirror_bone: bool, bind_basis: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var px: float = bone_pivot[0]
	var py: float = bone_pivot[1]
	var pz: float = bone_pivot[2]
	var has_bind_rot := bind_basis != Basis.IDENTITY

	for cube in cubes:
		var origin: Array = cube.get("origin", [0, 0, 0])
		var sz: Array = cube.get("size", [1, 1, 1])
		var uv_origin: Array = cube.get("uv", [0, 0])
		var inflate: float = cube.get("inflate", 0.0)
		var cube_mirror: bool = cube.get("mirror", mirror_bone)
		var cube_rot: Array = cube.get("rotation", [0, 0, 0])
		var cube_pivot: Array = cube.get("pivot", bone_pivot)

		var w: float = sz[0]
		var h: float = sz[1]
		var d: float = sz[2]

		# Offset from bone pivot, with inflate
		var x0: float = (origin[0] - inflate - px) * SCALE
		var y0: float = (origin[1] - inflate - py) * SCALE
		var z0: float = (origin[2] - inflate - pz) * SCALE
		var x1: float = x0 + (w + inflate * 2.0) * SCALE
		var y1: float = y0 + (h + inflate * 2.0) * SCALE
		var z1: float = z0 + (d + inflate * 2.0) * SCALE

		var u: float = uv_origin[0]
		var v: float = uv_origin[1]

		# UV layout for Bedrock box [w, h, d]:
		var uv_east := [u, v + d, u + d, v + d + h]
		var uv_north := [u + d, v + d, u + d + w, v + d + h]
		var uv_west := [u + d + w, v + d, u + d + w + d, v + d + h]
		var uv_south := [u + d + w + d, v + d, u + 2*d + 2*w, v + d + h]
		var uv_top := [u + d, v, u + d + w, v + d]
		var uv_bottom := [u + d + w, v, u + d + 2*w, v + d]

		if cube_mirror:
			var tmp := uv_east
			uv_east = [uv_west[2], uv_west[1], uv_west[0], uv_west[3]]
			uv_west = [tmp[2], tmp[1], tmp[0], tmp[3]]
			uv_north = [uv_north[2], uv_north[1], uv_north[0], uv_north[3]]
			uv_south = [uv_south[2], uv_south[1], uv_south[0], uv_south[3]]
			uv_top = [uv_top[2], uv_top[1], uv_top[0], uv_top[3]]
			uv_bottom = [uv_bottom[2], uv_bottom[1], uv_bottom[0], uv_bottom[3]]

		# Build 8 corners
		var c := [
			Vector3(x0, y0, z0), Vector3(x1, y0, z0),
			Vector3(x1, y1, z0), Vector3(x0, y1, z0),
			Vector3(x0, y0, z1), Vector3(x1, y0, z1),
			Vector3(x1, y1, z1), Vector3(x0, y1, z1),
		]

		# Apply cube-level rotation (around cube's pivot)
		var cr := Vector3(cube_rot[0], cube_rot[1], cube_rot[2])
		if cr != Vector3.ZERO:
			var cube_basis := Basis.from_euler(Vector3(
				deg_to_rad(cr.x), deg_to_rad(cr.y), deg_to_rad(cr.z)))
			var cpivot := Vector3(
				(cube_pivot[0] - px) * SCALE,
				(cube_pivot[1] - py) * SCALE,
				(cube_pivot[2] - pz) * SCALE)
			for ci in range(8):
				c[ci] = cube_basis * (c[ci] - cpivot) + cpivot

		# Bake bind_pose_rotation into vertices (rotate around bone pivot = origin)
		if has_bind_rot:
			for ci in range(8):
				c[ci] = bind_basis * c[ci]

		# Face normals (also rotated by bind_pose if needed)
		var n_north := Vector3(0, 0, -1)
		var n_south := Vector3(0, 0, 1)
		var n_west := Vector3(1, 0, 0)
		var n_east := Vector3(-1, 0, 0)
		var n_top := Vector3(0, 1, 0)
		var n_bottom := Vector3(0, -1, 0)
		if has_bind_rot:
			n_north = bind_basis * n_north
			n_south = bind_basis * n_south
			n_west = bind_basis * n_west
			n_east = bind_basis * n_east
			n_top = bind_basis * n_top
			n_bottom = bind_basis * n_bottom

		# Emit 6 faces
		_emit_face(st, tex_w, tex_h, uv_north, c[1], c[0], c[3], c[2], n_north)
		_emit_face(st, tex_w, tex_h, uv_south, c[4], c[5], c[6], c[7], n_south)
		_emit_face(st, tex_w, tex_h, uv_west, c[5], c[1], c[2], c[6], n_west)
		_emit_face(st, tex_w, tex_h, uv_east, c[0], c[4], c[7], c[3], n_east)
		_emit_face(st, tex_w, tex_h, uv_top, c[3], c[7], c[6], c[2], n_top)
		_emit_face(st, tex_w, tex_h, uv_bottom, c[1], c[5], c[4], c[0], n_bottom)

	st.set_material(material)
	st.generate_tangents()
	var mesh := st.commit()
	if mesh == null:
		return null

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "CubeMesh"
	return mi


## Emit a quad (2 triangles) with UV from pixel rect.
static func _emit_face(st: SurfaceTool, tex_w: float, tex_h: float,
		uv_rect: Array, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3,
		normal: Vector3) -> void:
	var u0n: float = uv_rect[0] / tex_w
	var v0n: float = uv_rect[1] / tex_h
	var u1n: float = uv_rect[2] / tex_w
	var v1n: float = uv_rect[3] / tex_h

	var uvs := [
		Vector2(u0n, v1n),  # v0: bottom-left
		Vector2(u1n, v1n),  # v1: bottom-right
		Vector2(u1n, v0n),  # v2: top-right
		Vector2(u0n, v0n),  # v3: top-left
	]

	# Triangle 1: v0, v1, v2
	st.set_normal(normal)
	st.set_uv(uvs[0])
	st.add_vertex(v0)
	st.set_normal(normal)
	st.set_uv(uvs[1])
	st.add_vertex(v1)
	st.set_normal(normal)
	st.set_uv(uvs[2])
	st.add_vertex(v2)

	# Triangle 2: v0, v2, v3
	st.set_normal(normal)
	st.set_uv(uvs[0])
	st.add_vertex(v0)
	st.set_normal(normal)
	st.set_uv(uvs[2])
	st.add_vertex(v2)
	st.set_normal(normal)
	st.set_uv(uvs[3])
	st.add_vertex(v3)
