extends Node3D
class_name Chunk

const CHUNK_SIZE = 16
const CHUNK_HEIGHT = 256

# Shared material (un seul pour tous les chunks)
static var _shared_material: StandardMaterial3D = null

var chunk_position: Vector3i
var blocks: PackedByteArray
var y_min: int = 0
var y_max: int = 0
var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D
var static_body: StaticBody3D
var is_mesh_built: bool = false

# Thread mesh build
var _mesh_thread: Thread = null
var _vertices: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()
var _indices: PackedInt32Array = PackedInt32Array()
var _collision_faces: PackedVector3Array = PackedVector3Array()

func _init(pos: Vector3i, block_data: PackedByteArray, p_y_min: int = 0, p_y_max: int = CHUNK_HEIGHT - 1):
	chunk_position = pos
	blocks = block_data
	y_min = p_y_min
	y_max = p_y_max

static func _get_shared_material() -> StandardMaterial3D:
	if not _shared_material:
		_shared_material = StandardMaterial3D.new()
		_shared_material.vertex_color_use_as_albedo = true
		_shared_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_shared_material.albedo_color = Color(1, 1, 1, 1)
		_shared_material.roughness = 0.8
		_shared_material.metallic = 0.0
	return _shared_material

# ============================================================
# ACCES AUX BLOCS
# ============================================================

func get_block(x: int, y: int, z: int) -> BlockRegistry.BlockType:
	if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_HEIGHT or z < 0 or z >= CHUNK_SIZE:
		return BlockRegistry.BlockType.AIR
	return blocks[x * 4096 + z * 256 + y] as BlockRegistry.BlockType

func set_block(x: int, y: int, z: int, block_type: BlockRegistry.BlockType):
	if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_HEIGHT or z < 0 or z >= CHUNK_SIZE:
		return
	blocks[x * 4096 + z * 256 + y] = block_type
	if block_type != BlockRegistry.BlockType.AIR:
		if y < y_min:
			y_min = y
		if y > y_max:
			y_max = y
	_rebuild_mesh()

# ============================================================
# MESH BUILDING — Async (thread) + Sync (rebuild bloc)
# ============================================================

func build_mesh_async():
	if _mesh_thread != null or is_mesh_built:
		return
	_mesh_thread = Thread.new()
	_mesh_thread.start(_thread_entry)

func _thread_entry():
	_compute_mesh_arrays()
	call_deferred("_apply_mesh_data")

func _compute_mesh_arrays():
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()
	_collision_faces = PackedVector3Array()

	if y_min <= y_max:
		_greedy_mesh_y_faces()
		_greedy_mesh_z_faces()
		_greedy_mesh_x_faces()

func _apply_mesh_data():
	if _mesh_thread:
		_mesh_thread.wait_to_finish()
		_mesh_thread = null

	if not is_inside_tree():
		return

	if _vertices.size() == 0:
		is_mesh_built = true
		return

	# ArrayMesh depuis les packed arrays
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _get_shared_material()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)

	# Collision
	if _collision_faces.size() > 0:
		static_body = StaticBody3D.new()
		collision_shape = CollisionShape3D.new()
		var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
		shape.set_faces(_collision_faces)
		collision_shape.shape = shape
		static_body.add_child(collision_shape)
		add_child(static_body)

	is_mesh_built = true

	# Libérer les tableaux temporaires
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()
	_collision_faces = PackedVector3Array()

# Rebuild synchrone (pour casse/placement de blocs)
func _rebuild_mesh():
	if _mesh_thread:
		_mesh_thread.wait_to_finish()
		_mesh_thread = null
	if mesh_instance:
		mesh_instance.queue_free()
		mesh_instance = null
	if static_body:
		static_body.queue_free()
		static_body = null
	is_mesh_built = false
	call_deferred("_deferred_rebuild")

func _deferred_rebuild():
	_compute_mesh_arrays()
	_apply_mesh_data()

func _exit_tree():
	if _mesh_thread:
		_mesh_thread.wait_to_finish()
		_mesh_thread = null

# ============================================================
# GREEDY MESHING — Algorithme 2D
# ============================================================

func _run_greedy(mask: Array, u_size: int, v_size: int) -> Array:
	var quads: Array = []
	for v in range(v_size):
		var u: int = 0
		while u < u_size:
			var bt: int = mask[u][v]
			if bt == -1:
				u += 1
				continue

			var w: int = 1
			while u + w < u_size and mask[u + w][v] == bt:
				w += 1

			var h: int = 1
			var can_extend: bool = true
			while v + h < v_size and can_extend:
				for k in range(w):
					if mask[u + k][v + h] != bt:
						can_extend = false
						break
				if can_extend:
					h += 1

			quads.append([u, v, w, h, bt])

			for dv in range(h):
				for du in range(w):
					mask[u + du][v + dv] = -1

			u += w
	return quads

# ============================================================
# FACES Y (UP / DOWN) — masque u=x, v=z
# ============================================================

func _greedy_mesh_y_faces():
	var mask: Array = []
	mask.resize(CHUNK_SIZE)
	for i in range(CHUNK_SIZE):
		mask[i] = []
		mask[i].resize(CHUNK_SIZE)

	for y in range(y_min, y_max + 1):
		# --- UP (+Y) ---
		var has_faces: bool = false
		for x in range(CHUNK_SIZE):
			var x_off: int = x * 4096
			for z in range(CHUNK_SIZE):
				var idx: int = x_off + z * 256 + y
				var bt: int = blocks[idx]
				if bt != 0 and (y + 1 >= CHUNK_HEIGHT or blocks[idx + 1] == 0):
					mask[x][z] = bt
					has_faces = true
				else:
					mask[x][z] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, CHUNK_SIZE)
			for q in quads:
				var u: int = q[0]; var v: int = q[1]; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var color: Color = BlockRegistry.get_block_color(bt)
				var ao0 = _calculate_ao_for_face(Vector3.UP, u, y, v)
				var ao1 = _calculate_ao_for_face(Vector3.UP, u + w - 1, y, v)
				var ao2 = _calculate_ao_for_face(Vector3.UP, u + w - 1, y, v + h - 1)
				var ao3 = _calculate_ao_for_face(Vector3.UP, u, y, v + h - 1)
				_emit_quad(
					Vector3(u, y + 1, v), Vector3(u + w, y + 1, v),
					Vector3(u + w, y + 1, v + h), Vector3(u, y + 1, v + h),
					Vector3.UP, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

		# --- DOWN (-Y) ---
		has_faces = false
		for x in range(CHUNK_SIZE):
			var x_off: int = x * 4096
			for z in range(CHUNK_SIZE):
				var idx: int = x_off + z * 256 + y
				var bt: int = blocks[idx]
				if bt != 0 and (y - 1 < 0 or blocks[idx - 1] == 0):
					mask[x][z] = bt
					has_faces = true
				else:
					mask[x][z] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, CHUNK_SIZE)
			for q in quads:
				var u: int = q[0]; var v: int = q[1]; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var color: Color = BlockRegistry.get_block_color(bt) * 0.6
				var ao0 = _calculate_ao_for_face(Vector3.DOWN, u, y, v + h - 1)
				var ao1 = _calculate_ao_for_face(Vector3.DOWN, u + w - 1, y, v + h - 1)
				var ao2 = _calculate_ao_for_face(Vector3.DOWN, u + w - 1, y, v)
				var ao3 = _calculate_ao_for_face(Vector3.DOWN, u, y, v)
				_emit_quad(
					Vector3(u, y, v + h), Vector3(u + w, y, v + h),
					Vector3(u + w, y, v), Vector3(u, y, v),
					Vector3.DOWN, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

# ============================================================
# FACES Z (BACK / FORWARD) — masque u=x, v=y (réduit à y_range)
# ============================================================

func _greedy_mesh_z_faces():
	var y_range: int = y_max - y_min + 1
	if y_range <= 0:
		return
	var mask: Array = []
	mask.resize(CHUNK_SIZE)
	for i in range(CHUNK_SIZE):
		mask[i] = []
		mask[i].resize(y_range)

	for z in range(CHUNK_SIZE):
		# --- BACK (+Z) ---
		var has_faces: bool = false
		for x in range(CHUNK_SIZE):
			var x_off: int = x * 4096
			var xz_off: int = x_off + z * 256
			var xzp_off: int = x_off + (z + 1) * 256
			for iy in range(y_range):
				var y: int = y_min + iy
				var bt: int = blocks[xz_off + y]
				if bt != 0 and (z + 1 >= CHUNK_SIZE or blocks[xzp_off + y] == 0):
					mask[x][iy] = bt
					has_faces = true
				else:
					mask[x][iy] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, y_range)
			for q in quads:
				var u: int = q[0]; var v: int = q[1] + y_min; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var color: Color = BlockRegistry.get_block_color(bt) * 0.8
				var ao0 = _calculate_ao_for_face(Vector3.BACK, u + w - 1, v, z)
				var ao1 = _calculate_ao_for_face(Vector3.BACK, u, v, z)
				var ao2 = _calculate_ao_for_face(Vector3.BACK, u, v + h - 1, z)
				var ao3 = _calculate_ao_for_face(Vector3.BACK, u + w - 1, v + h - 1, z)
				_emit_quad(
					Vector3(u + w, v, z + 1), Vector3(u, v, z + 1),
					Vector3(u, v + h, z + 1), Vector3(u + w, v + h, z + 1),
					Vector3.BACK, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

		# --- FORWARD (-Z) ---
		has_faces = false
		for x in range(CHUNK_SIZE):
			var x_off: int = x * 4096
			var xz_off: int = x_off + z * 256
			var xzm_off: int = x_off + (z - 1) * 256
			for iy in range(y_range):
				var y: int = y_min + iy
				var bt: int = blocks[xz_off + y]
				if bt != 0 and (z - 1 < 0 or blocks[xzm_off + y] == 0):
					mask[x][iy] = bt
					has_faces = true
				else:
					mask[x][iy] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, y_range)
			for q in quads:
				var u: int = q[0]; var v: int = q[1] + y_min; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var color: Color = BlockRegistry.get_block_color(bt) * 0.8
				var ao0 = _calculate_ao_for_face(Vector3.FORWARD, u, v, z)
				var ao1 = _calculate_ao_for_face(Vector3.FORWARD, u + w - 1, v, z)
				var ao2 = _calculate_ao_for_face(Vector3.FORWARD, u + w - 1, v + h - 1, z)
				var ao3 = _calculate_ao_for_face(Vector3.FORWARD, u, v + h - 1, z)
				_emit_quad(
					Vector3(u, v, z), Vector3(u + w, v, z),
					Vector3(u + w, v + h, z), Vector3(u, v + h, z),
					Vector3.FORWARD, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

# ============================================================
# FACES X (RIGHT / LEFT) — masque u=z, v=y (réduit à y_range)
# ============================================================

func _greedy_mesh_x_faces():
	var y_range: int = y_max - y_min + 1
	if y_range <= 0:
		return
	var mask: Array = []
	mask.resize(CHUNK_SIZE)
	for i in range(CHUNK_SIZE):
		mask[i] = []
		mask[i].resize(y_range)

	for x in range(CHUNK_SIZE):
		var x_off: int = x * 4096
		var xp_off: int = (x + 1) * 4096
		var xm_off: int = (x - 1) * 4096

		# --- RIGHT (+X) ---
		var has_faces: bool = false
		for z in range(CHUNK_SIZE):
			var z_off: int = z * 256
			for iy in range(y_range):
				var y: int = y_min + iy
				var bt: int = blocks[x_off + z_off + y]
				if bt != 0 and (x + 1 >= CHUNK_SIZE or blocks[xp_off + z_off + y] == 0):
					mask[z][iy] = bt
					has_faces = true
				else:
					mask[z][iy] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, y_range)
			for q in quads:
				var u: int = q[0]; var v: int = q[1] + y_min; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var color: Color = BlockRegistry.get_block_color(bt) * 0.9
				var ao0 = _calculate_ao_for_face(Vector3.RIGHT, x, v, u)
				var ao1 = _calculate_ao_for_face(Vector3.RIGHT, x, v, u + w - 1)
				var ao2 = _calculate_ao_for_face(Vector3.RIGHT, x, v + h - 1, u + w - 1)
				var ao3 = _calculate_ao_for_face(Vector3.RIGHT, x, v + h - 1, u)
				_emit_quad(
					Vector3(x + 1, v, u), Vector3(x + 1, v, u + w),
					Vector3(x + 1, v + h, u + w), Vector3(x + 1, v + h, u),
					Vector3.RIGHT, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

		# --- LEFT (-X) ---
		has_faces = false
		for z in range(CHUNK_SIZE):
			var z_off: int = z * 256
			for iy in range(y_range):
				var y: int = y_min + iy
				var bt: int = blocks[x_off + z_off + y]
				if bt != 0 and (x - 1 < 0 or blocks[xm_off + z_off + y] == 0):
					mask[z][iy] = bt
					has_faces = true
				else:
					mask[z][iy] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, y_range)
			for q in quads:
				var u: int = q[0]; var v: int = q[1] + y_min; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var color: Color = BlockRegistry.get_block_color(bt) * 0.9
				var ao0 = _calculate_ao_for_face(Vector3.LEFT, x, v, u + w - 1)
				var ao1 = _calculate_ao_for_face(Vector3.LEFT, x, v, u)
				var ao2 = _calculate_ao_for_face(Vector3.LEFT, x, v + h - 1, u)
				var ao3 = _calculate_ao_for_face(Vector3.LEFT, x, v + h - 1, u + w - 1)
				_emit_quad(
					Vector3(x, v, u + w), Vector3(x, v, u),
					Vector3(x, v + h, u), Vector3(x, v + h, u + w),
					Vector3.LEFT, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

# ============================================================
# EMISSION D'UN QUAD FUSIONNE
# ============================================================

func _emit_quad(v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3, color: Color, ao: Array):
	var base: int = _vertices.size()

	_vertices.append(v0)
	_vertices.append(v1)
	_vertices.append(v2)
	_vertices.append(v3)

	_normals.append(normal)
	_normals.append(normal)
	_normals.append(normal)
	_normals.append(normal)

	_colors.append(color * ao[0])
	_colors.append(color * ao[1])
	_colors.append(color * ao[2])
	_colors.append(color * ao[3])

	_indices.append(base)
	_indices.append(base + 1)
	_indices.append(base + 2)
	_indices.append(base + 2)
	_indices.append(base + 3)
	_indices.append(base)

	# Faces de collision (2 triangles)
	_collision_faces.append(v0)
	_collision_faces.append(v1)
	_collision_faces.append(v2)
	_collision_faces.append(v2)
	_collision_faces.append(v3)
	_collision_faces.append(v0)

# ============================================================
# AMBIENT OCCLUSION
# ============================================================

func _is_block_solid(x: int, y: int, z: int) -> bool:
	if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_HEIGHT or z < 0 or z >= CHUNK_SIZE:
		return false
	return blocks[x * 4096 + z * 256 + y] != 0

func _calculate_ao_for_face(direction: Vector3, x: int, y: int, z: int) -> Array:
	var ao = [1.0, 1.0, 1.0, 1.0]

	if direction == Vector3.UP:
		ao[0] = _calculate_vertex_ao(x-1, y+1, z-1, x-1, y+1, z, x, y+1, z-1)
		ao[1] = _calculate_vertex_ao(x+1, y+1, z-1, x+1, y+1, z, x, y+1, z-1)
		ao[2] = _calculate_vertex_ao(x+1, y+1, z+1, x+1, y+1, z, x, y+1, z+1)
		ao[3] = _calculate_vertex_ao(x-1, y+1, z+1, x-1, y+1, z, x, y+1, z+1)
	elif direction == Vector3.DOWN:
		ao[0] = _calculate_vertex_ao(x-1, y-1, z+1, x-1, y-1, z, x, y-1, z+1)
		ao[1] = _calculate_vertex_ao(x+1, y-1, z+1, x+1, y-1, z, x, y-1, z+1)
		ao[2] = _calculate_vertex_ao(x+1, y-1, z-1, x+1, y-1, z, x, y-1, z-1)
		ao[3] = _calculate_vertex_ao(x-1, y-1, z-1, x-1, y-1, z, x, y-1, z-1)
	elif direction == Vector3.FORWARD:
		ao[0] = _calculate_vertex_ao(x-1, y-1, z-1, x-1, y, z-1, x, y-1, z-1)
		ao[1] = _calculate_vertex_ao(x+1, y-1, z-1, x+1, y, z-1, x, y-1, z-1)
		ao[2] = _calculate_vertex_ao(x+1, y+1, z-1, x+1, y, z-1, x, y+1, z-1)
		ao[3] = _calculate_vertex_ao(x-1, y+1, z-1, x-1, y, z-1, x, y+1, z-1)
	elif direction == Vector3.BACK:
		ao[0] = _calculate_vertex_ao(x+1, y-1, z+1, x+1, y, z+1, x, y-1, z+1)
		ao[1] = _calculate_vertex_ao(x-1, y-1, z+1, x-1, y, z+1, x, y-1, z+1)
		ao[2] = _calculate_vertex_ao(x-1, y+1, z+1, x-1, y, z+1, x, y+1, z+1)
		ao[3] = _calculate_vertex_ao(x+1, y+1, z+1, x+1, y, z+1, x, y+1, z+1)
	elif direction == Vector3.LEFT:
		ao[0] = _calculate_vertex_ao(x-1, y-1, z+1, x-1, y, z+1, x-1, y-1, z)
		ao[1] = _calculate_vertex_ao(x-1, y-1, z-1, x-1, y, z-1, x-1, y-1, z)
		ao[2] = _calculate_vertex_ao(x-1, y+1, z-1, x-1, y, z-1, x-1, y+1, z)
		ao[3] = _calculate_vertex_ao(x-1, y+1, z+1, x-1, y, z+1, x-1, y+1, z)
	elif direction == Vector3.RIGHT:
		ao[0] = _calculate_vertex_ao(x+1, y-1, z-1, x+1, y, z-1, x+1, y-1, z)
		ao[1] = _calculate_vertex_ao(x+1, y-1, z+1, x+1, y, z+1, x+1, y-1, z)
		ao[2] = _calculate_vertex_ao(x+1, y+1, z+1, x+1, y, z+1, x+1, y+1, z)
		ao[3] = _calculate_vertex_ao(x+1, y+1, z-1, x+1, y, z-1, x+1, y+1, z)

	return ao

func _calculate_vertex_ao(x1: int, y1: int, z1: int, x2: int, y2: int, z2: int, x3: int, y3: int, z3: int) -> float:
	var side1 = 1 if _is_block_solid(x1, y1, z1) else 0
	var side2 = 1 if _is_block_solid(x2, y2, z2) else 0
	var corner = 1 if _is_block_solid(x3, y3, z3) else 0

	if side1 == 1 and side2 == 1:
		return 0.4

	var total = side1 + side2 + corner
	if total == 0:
		return 1.0
	elif total == 1:
		return 0.85
	elif total == 2:
		return 0.65
	else:
		return 0.5
