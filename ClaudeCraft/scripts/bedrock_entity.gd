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
static func build_model(geo_path: String, texture: Texture2D, geometry_id: String = "") -> Node3D:
	var geo = _load_geometry(geo_path, geometry_id)
	if geo.is_empty():
		push_warning("[BedrockEntity] No geometry in " + geo_path)
		return null

	var tex_w: float = geo["tex_w"]
	var tex_h: float = geo["tex_h"]
	var bones_data: Array = geo["bones"]

	# Material shared by all cubes
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Slightly lit so mobs have some depth — not fully unshaded
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX

	var root := Node3D.new()
	root.name = "BedrockModel"

	# First pass: create bone Node3Ds
	var bone_nodes: Dictionary = {}   # name → Node3D
	var bone_pivots: Dictionary = {}  # name → Array[3]
	for bd in bones_data:
		var bname: String = bd.get("name", "unnamed")
		var pivot: Array = bd.get("pivot", [0, 0, 0])
		var node := Node3D.new()
		node.name = bname
		bone_nodes[bname] = node
		bone_pivots[bname] = pivot

	# Second pass: parent, position, rotation, mesh
	for bd in bones_data:
		var bname: String = bd.get("name", "unnamed")
		var node: Node3D = bone_nodes[bname]
		var pivot: Array = bd.get("pivot", [0, 0, 0])
		var parent_name: String = bd.get("parent", "")

		# Set parent and compute relative position
		if parent_name != "" and bone_nodes.has(parent_name):
			bone_nodes[parent_name].add_child(node)
			var pp: Array = bone_pivots[parent_name]
			node.position = Vector3(pivot[0] - pp[0], pivot[1] - pp[1], pivot[2] - pp[2]) * SCALE
		else:
			root.add_child(node)
			node.position = Vector3(pivot[0], pivot[1], pivot[2]) * SCALE

		# Apply bind_pose_rotation or static rotation
		var bind_rot: Array = bd.get("bind_pose_rotation", bd.get("rotation", [0, 0, 0]))
		if bind_rot != [0, 0, 0] and bind_rot != [0.0, 0.0, 0.0]:
			node.rotation_degrees = Vector3(bind_rot[0], bind_rot[1], bind_rot[2])

		# Build cube meshes
		var mirror_bone: bool = bd.get("mirror", false)
		var cubes: Array = bd.get("cubes", [])
		if cubes.size() > 0:
			var mesh := _build_cubes_mesh(cubes, pivot, tex_w, tex_h, material, mirror_bone)
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
			# Handle inheritance: "geometry.sheep.v1.8:geometry.sheep.sheared.v1.8"
			var gid := key.split(":")[0]
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
		# Fallback: first geometry found
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
static func _build_cubes_mesh(cubes: Array, bone_pivot: Array, tex_w: float, tex_h: float, material: StandardMaterial3D, mirror_bone: bool) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var px: float = bone_pivot[0]
	var py: float = bone_pivot[1]
	var pz: float = bone_pivot[2]

	for cube in cubes:
		var origin: Array = cube.get("origin", [0, 0, 0])
		var sz: Array = cube.get("size", [1, 1, 1])
		var uv_origin: Array = cube.get("uv", [0, 0])
		var inflate: float = cube.get("inflate", 0.0)
		var cube_mirror: bool = cube.get("mirror", mirror_bone)
		var cube_rot: Array = cube.get("rotation", [0, 0, 0])

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
		#          d      w      d      w
		#   v  +------+------+------+------+
		#   d  |      | Top  |      |Bottom|
		#      +------+------+------+------+
		#   h  |Right | Front| Left | Back |
		#      +------+------+------+------+
		# "Right" = +X face, "Left" = -X face (from entity POV, but UV layout convention)
		# For our coordinate system:
		# Front  = North = -Z    Back  = South = +Z
		# Right  = West  = +X    Left  = East  = -X

		# UV rects: [u_start, v_start, u_end, v_end] in pixel space
		# East (-X):   u, v+d → u+d, v+d+h
		var uv_east := [u, v + d, u + d, v + d + h]
		# North (-Z / front): u+d, v+d → u+d+w, v+d+h
		var uv_north := [u + d, v + d, u + d + w, v + d + h]
		# West (+X):  u+d+w, v+d → u+d+w+d, v+d+h
		var uv_west := [u + d + w, v + d, u + d + w + d, v + d + h]
		# South (+Z / back): u+d+w+d, v+d → u+2d+2w, v+d+h
		var uv_south := [u + d + w + d, v + d, u + 2*d + 2*w, v + d + h]
		# Top (+Y):   u+d, v → u+d+w, v+d
		var uv_top := [u + d, v, u + d + w, v + d]
		# Bottom (-Y): u+d+w, v → u+2w+d, v+d
		var uv_bottom := [u + d + w, v, u + d + 2*w, v + d]

		if cube_mirror:
			# Mirror horizontally: swap east/west UVs and flip U within each face
			var tmp := uv_east
			uv_east = [uv_west[2], uv_west[1], uv_west[0], uv_west[3]]
			uv_west = [tmp[2], tmp[1], tmp[0], tmp[3]]
			uv_north = [uv_north[2], uv_north[1], uv_north[0], uv_north[3]]
			uv_south = [uv_south[2], uv_south[1], uv_south[0], uv_south[3]]
			uv_top = [uv_top[2], uv_top[1], uv_top[0], uv_top[3]]
			uv_bottom = [uv_bottom[2], uv_bottom[1], uv_bottom[0], uv_bottom[3]]

		# Emit 6 faces (each as 2 triangles)
		# North face (-Z) at z=z0
		_emit_face(st, tex_w, tex_h, uv_north,
			Vector3(x1, y0, z0), Vector3(x0, y0, z0),
			Vector3(x0, y1, z0), Vector3(x1, y1, z0),
			Vector3(0, 0, -1))
		# South face (+Z) at z=z1
		_emit_face(st, tex_w, tex_h, uv_south,
			Vector3(x0, y0, z1), Vector3(x1, y0, z1),
			Vector3(x1, y1, z1), Vector3(x0, y1, z1),
			Vector3(0, 0, 1))
		# West face (+X) at x=x1
		_emit_face(st, tex_w, tex_h, uv_west,
			Vector3(x1, y0, z1), Vector3(x1, y0, z0),
			Vector3(x1, y1, z0), Vector3(x1, y1, z1),
			Vector3(1, 0, 0))
		# East face (-X) at x=x0
		_emit_face(st, tex_w, tex_h, uv_east,
			Vector3(x0, y0, z0), Vector3(x0, y0, z1),
			Vector3(x0, y1, z1), Vector3(x0, y1, z0),
			Vector3(-1, 0, 0))
		# Top face (+Y) at y=y1
		_emit_face(st, tex_w, tex_h, uv_top,
			Vector3(x0, y1, z0), Vector3(x0, y1, z1),
			Vector3(x1, y1, z1), Vector3(x1, y1, z0),
			Vector3(0, 1, 0))
		# Bottom face (-Y) at y=y0
		_emit_face(st, tex_w, tex_h, uv_bottom,
			Vector3(x1, y0, z0), Vector3(x1, y0, z1),
			Vector3(x0, y0, z1), Vector3(x0, y0, z0),
			Vector3(0, -1, 0))

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
## Vertices v0-v3 in CCW order, uv_rect = [u0, v0, u1, v1] pixel coords.
static func _emit_face(st: SurfaceTool, tex_w: float, tex_h: float,
		uv_rect: Array, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3,
		normal: Vector3) -> void:
	# Normalize UV to 0-1
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
