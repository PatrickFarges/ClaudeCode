extends Node3D
class_name Chunk

const CHUNK_SIZE = 16
const CHUNK_HEIGHT = 256

# Shared material (un seul pour tous les chunks)
static var _shared_material: Material = null
static var _shared_water_material: StandardMaterial3D = null
static var _shared_cross_material: Material = null
const WATER_TYPE: int = 15  # BlockRegistry.BlockType.WATER

# Cross mesh block types (vegetation) — skipped by greedy mesher, rendered as X quads
const CROSS_TYPES: Dictionary = {
	77: true,  # SHORT_GRASS
	78: true,  # FERN
	79: true,  # DEAD_BUSH
	80: true,  # DANDELION
	81: true,  # POPPY
	82: true,  # CORNFLOWER
}

# Special shape blocks — excluded from greedy mesher, rendered with custom geometry
# STONE_BRICKS (83) = cube normal, pas besoin de l'exclure
const SLAB_TYPES: Dictionary = {
	87: true,  # OAK_SLAB
	88: true,  # COBBLESTONE_SLAB
	89: true,  # STONE_SLAB
}
const STAIR_TYPES: Dictionary = {
	84: true,  # OAK_STAIRS
	85: true,  # COBBLESTONE_STAIRS
	86: true,  # STONE_BRICK_STAIRS
}
const FENCE_TYPES: Dictionary = {
	91: true,  # OAK_FENCE
	97: true,  # IRON_BARS
}
const DOOR_TYPES: Dictionary = {
	90: true,  # OAK_DOOR
	95: true,  # IRON_DOOR
}
const THIN_TYPES: Dictionary = {
	92: true,  # GLASS_PANE
	93: true,  # LADDER
	94: true,  # OAK_TRAPDOOR
}
const LANTERN_TYPE: int = 96  # LANTERN

func _is_special_shape(bt: int) -> bool:
	return SLAB_TYPES.has(bt) or STAIR_TYPES.has(bt) or FENCE_TYPES.has(bt) or DOOR_TYPES.has(bt) or THIN_TYPES.has(bt) or bt == LANTERN_TYPE

# Bloc à exclure du greedy mesher (non-cube: flora, special shapes)
static func _skip_bt(bt: int) -> bool:
	return bt == 0 or bt == 15 or bt == 72 or bt >= 77  # AIR, WATER, TORCH, or any block >= SHORT_GRASS (cross + architectural)

# Bloc est un cube solide pour le greedy mesher
static func _is_greedy_solid(bt: int) -> bool:
	return bt != 0 and bt != 15 and bt != 72 and (bt < 77 or bt == 83)  # Exclude AIR, WATER, TORCH, cross types, special shapes (but STONE_BRICKS=83 is a cube)

var chunk_position: Vector3i
var blocks: PackedByteArray
var y_min: int = 0
var y_max: int = 0
var mesh_instance: MeshInstance3D
var water_mesh_instance: MeshInstance3D
var flora_mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D
var static_body: StaticBody3D
var is_mesh_built: bool = false
var is_modified: bool = false

# Torch lights
var _torch_lights: Array = []  # Array de Node3D (OmniLight3D + mesh)
const TORCH_TYPE: int = 72  # BlockRegistry.BlockType.TORCH
const MAX_TORCHES_PER_CHUNK: int = 16

# Thread mesh build
var _mesh_thread: Thread = null
var _rebuild_pending: bool = false  # Flag pour re-rebuild après thread en cours
var _vertices: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()
var _indices: PackedInt32Array = PackedInt32Array()
var _uvs: PackedVector2Array = PackedVector2Array()
var _custom0: PackedFloat32Array = PackedFloat32Array()
var _collision_faces: PackedVector3Array = PackedVector3Array()

# Water mesh arrays
var _water_vertices: PackedVector3Array = PackedVector3Array()
var _water_normals: PackedVector3Array = PackedVector3Array()
var _water_colors: PackedColorArray = PackedColorArray()
var _water_indices: PackedInt32Array = PackedInt32Array()

# Flora mesh arrays (cross billboards)
var _flora_vertices: PackedVector3Array = PackedVector3Array()
var _flora_normals: PackedVector3Array = PackedVector3Array()
var _flora_colors: PackedColorArray = PackedColorArray()
var _flora_indices: PackedInt32Array = PackedInt32Array()
var _flora_uvs: PackedVector2Array = PackedVector2Array()
var _flora_custom0: PackedFloat32Array = PackedFloat32Array()

func _init(pos: Vector3i, block_data: PackedByteArray, p_y_min: int = 0, p_y_max: int = CHUNK_HEIGHT - 1):
	chunk_position = pos
	blocks = block_data
	y_min = p_y_min
	y_max = p_y_max

static func _get_shared_material() -> Material:
	if not _shared_material:
		_shared_material = TextureManager.get_shared_material()
	return _shared_material

static func _get_cross_material() -> Material:
	if not _shared_cross_material:
		_shared_cross_material = TextureManager.get_cross_material()
	return _shared_cross_material

static func _get_water_material() -> StandardMaterial3D:
	if not _shared_water_material:
		_shared_water_material = StandardMaterial3D.new()
		_shared_water_material.vertex_color_use_as_albedo = true
		_shared_water_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_shared_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shared_water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shared_water_material.roughness = 0.2
	return _shared_water_material

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
	is_modified = true
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
	_uvs = PackedVector2Array()
	_custom0 = PackedFloat32Array()
	_collision_faces = PackedVector3Array()
	_water_vertices = PackedVector3Array()
	_water_normals = PackedVector3Array()
	_water_colors = PackedColorArray()
	_water_indices = PackedInt32Array()
	_flora_vertices = PackedVector3Array()
	_flora_normals = PackedVector3Array()
	_flora_colors = PackedColorArray()
	_flora_indices = PackedInt32Array()
	_flora_uvs = PackedVector2Array()
	_flora_custom0 = PackedFloat32Array()

	if y_min <= y_max:
		_greedy_mesh_y_faces()
		_greedy_mesh_z_faces()
		_greedy_mesh_x_faces()
		_build_special_mesh()
		_build_water_mesh()
		_build_flora_mesh()

func _apply_mesh_data():
	if _mesh_thread:
		_mesh_thread.wait_to_finish()
		_mesh_thread = null

	if not is_inside_tree():
		return

	if _vertices.size() == 0 and _water_vertices.size() == 0 and _flora_vertices.size() == 0:
		is_mesh_built = true
		return

	# ArrayMesh depuis les packed arrays (solid blocks)
	if _vertices.size() > 0:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_COLOR] = _colors
		arrays[Mesh.ARRAY_INDEX] = _indices
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
		arrays[Mesh.ARRAY_CUSTOM0] = _custom0

		var mesh: ArrayMesh = ArrayMesh.new()
		var flags = Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)

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

	# Water mesh (transparent, no collision)
	if _water_vertices.size() > 0:
		var water_arrays: Array = []
		water_arrays.resize(Mesh.ARRAY_MAX)
		water_arrays[Mesh.ARRAY_VERTEX] = _water_vertices
		water_arrays[Mesh.ARRAY_NORMAL] = _water_normals
		water_arrays[Mesh.ARRAY_COLOR] = _water_colors
		water_arrays[Mesh.ARRAY_INDEX] = _water_indices

		var water_mesh: ArrayMesh = ArrayMesh.new()
		water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water_arrays)

		water_mesh_instance = MeshInstance3D.new()
		water_mesh_instance.mesh = water_mesh
		water_mesh_instance.material_override = _get_water_material()
		water_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water_mesh_instance)

	# Flora mesh (cross billboards, no collision)
	if _flora_vertices.size() > 0:
		var flora_arrays: Array = []
		flora_arrays.resize(Mesh.ARRAY_MAX)
		flora_arrays[Mesh.ARRAY_VERTEX] = _flora_vertices
		flora_arrays[Mesh.ARRAY_NORMAL] = _flora_normals
		flora_arrays[Mesh.ARRAY_COLOR] = _flora_colors
		flora_arrays[Mesh.ARRAY_INDEX] = _flora_indices
		flora_arrays[Mesh.ARRAY_TEX_UV] = _flora_uvs
		flora_arrays[Mesh.ARRAY_CUSTOM0] = _flora_custom0

		var flora_mesh: ArrayMesh = ArrayMesh.new()
		var flags = Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		flora_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, flora_arrays, [], {}, flags)

		flora_mesh_instance = MeshInstance3D.new()
		flora_mesh_instance.mesh = flora_mesh
		flora_mesh_instance.material_override = _get_cross_material()
		flora_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flora_mesh_instance)

	# Torches : scanner et spawner les lumières
	_spawn_torch_lights()

	is_mesh_built = true

	# Libérer les tableaux temporaires
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()
	_uvs = PackedVector2Array()
	_custom0 = PackedFloat32Array()
	_collision_faces = PackedVector3Array()
	_water_vertices = PackedVector3Array()
	_water_normals = PackedVector3Array()
	_water_colors = PackedColorArray()
	_water_indices = PackedInt32Array()
	_flora_vertices = PackedVector3Array()
	_flora_normals = PackedVector3Array()
	_flora_colors = PackedColorArray()
	_flora_indices = PackedInt32Array()
	_flora_uvs = PackedVector2Array()
	_flora_custom0 = PackedFloat32Array()

# Rebuild async (pour casse/placement de blocs — threadé pour éviter le freeze)
func _rebuild_mesh():
	# Si un thread de rebuild est déjà en cours, juste marquer qu'on doit re-rebuild après
	if _mesh_thread:
		_rebuild_pending = true
		return
	_clear_torch_lights()
	is_mesh_built = false
	_mesh_thread = Thread.new()
	_mesh_thread.start(_thread_entry_rebuild)

func _thread_entry_rebuild():
	_compute_mesh_arrays()
	call_deferred("_apply_rebuild_data")

func _apply_rebuild_data():
	# Nettoyer les anciens mesh/collision avant d'appliquer les nouveaux
	if mesh_instance:
		mesh_instance.queue_free()
		mesh_instance = null
	if water_mesh_instance:
		water_mesh_instance.queue_free()
		water_mesh_instance = null
	if flora_mesh_instance:
		flora_mesh_instance.queue_free()
		flora_mesh_instance = null
	if static_body:
		static_body.queue_free()
		static_body = null
	_clear_torch_lights()
	# _apply_mesh_data fait le wait_to_finish du thread et crée les nouveaux mesh
	_apply_mesh_data()
	# Si un rebuild était en attente pendant le thread, le relancer
	if _rebuild_pending:
		_rebuild_pending = false
		_rebuild_mesh()

func _exit_tree():
	_rebuild_pending = false
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
				if _is_greedy_solid(bt):
					var nb: int = blocks[idx + 1] if y + 1 < CHUNK_HEIGHT else 0
					if not _is_greedy_solid(nb):
						mask[x][z] = bt
						has_faces = true
					else:
						mask[x][z] = -1
				else:
					mask[x][z] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, CHUNK_SIZE)
			for q in quads:
				var u: int = q[0]; var v: int = q[1]; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var tint: Color = BlockRegistry.get_block_tint(bt, "top")
				var tex_name: String = BlockRegistry.get_face_texture(bt, "top")
				var layer: float = float(TextureManager.get_layer_index(tex_name))
				var ao0 = _calculate_ao_for_face(Vector3.UP, u, y, v)
				var ao1 = _calculate_ao_for_face(Vector3.UP, u + w - 1, y, v)
				var ao2 = _calculate_ao_for_face(Vector3.UP, u + w - 1, y, v + h - 1)
				var ao3 = _calculate_ao_for_face(Vector3.UP, u, y, v + h - 1)
				_emit_quad(
					Vector3(u, y + 1, v), Vector3(u + w, y + 1, v),
					Vector3(u + w, y + 1, v + h), Vector3(u, y + 1, v + h),
					Vector3.UP, tint, [ao0[0], ao1[1], ao2[2], ao3[3]], float(w), float(h), layer)

		# --- DOWN (-Y) ---
		has_faces = false
		for x in range(CHUNK_SIZE):
			var x_off: int = x * 4096
			for z in range(CHUNK_SIZE):
				var idx: int = x_off + z * 256 + y
				var bt: int = blocks[idx]
				if _is_greedy_solid(bt):
					var nb: int = blocks[idx - 1] if y - 1 >= 0 else 0
					if not _is_greedy_solid(nb):
						mask[x][z] = bt
						has_faces = true
					else:
						mask[x][z] = -1
				else:
					mask[x][z] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, CHUNK_SIZE)
			for q in quads:
				var u: int = q[0]; var v: int = q[1]; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var tint: Color = BlockRegistry.get_block_tint(bt, "bottom") * 0.6
				var tex_name: String = BlockRegistry.get_face_texture(bt, "bottom")
				var layer: float = float(TextureManager.get_layer_index(tex_name))
				var ao0 = _calculate_ao_for_face(Vector3.DOWN, u, y, v + h - 1)
				var ao1 = _calculate_ao_for_face(Vector3.DOWN, u + w - 1, y, v + h - 1)
				var ao2 = _calculate_ao_for_face(Vector3.DOWN, u + w - 1, y, v)
				var ao3 = _calculate_ao_for_face(Vector3.DOWN, u, y, v)
				_emit_quad(
					Vector3(u, y, v + h), Vector3(u + w, y, v + h),
					Vector3(u + w, y, v), Vector3(u, y, v),
					Vector3.DOWN, tint, [ao0[0], ao1[1], ao2[2], ao3[3]], float(w), float(h), layer)

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
				if _is_greedy_solid(bt):
					var nb: int = blocks[xzp_off + y] if z + 1 < CHUNK_SIZE else 0
					if not _is_greedy_solid(nb):
						mask[x][iy] = bt
						has_faces = true
					else:
						mask[x][iy] = -1
				else:
					mask[x][iy] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, y_range)
			for q in quads:
				var u: int = q[0]; var v: int = q[1] + y_min; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var tint: Color = BlockRegistry.get_block_tint(bt, "back") * 0.8
				var tex_name: String = BlockRegistry.get_face_texture(bt, "back")
				var layer: float = float(TextureManager.get_layer_index(tex_name))
				var ao0 = _calculate_ao_for_face(Vector3.BACK, u + w - 1, v, z)
				var ao1 = _calculate_ao_for_face(Vector3.BACK, u, v, z)
				var ao2 = _calculate_ao_for_face(Vector3.BACK, u, v + h - 1, z)
				var ao3 = _calculate_ao_for_face(Vector3.BACK, u + w - 1, v + h - 1, z)
				_emit_quad(
					Vector3(u + w, v, z + 1), Vector3(u, v, z + 1),
					Vector3(u, v + h, z + 1), Vector3(u + w, v + h, z + 1),
					Vector3.BACK, tint, [ao0[0], ao1[1], ao2[2], ao3[3]], float(w), float(h), layer)

		# --- FORWARD (-Z) ---
		has_faces = false
		for x in range(CHUNK_SIZE):
			var x_off: int = x * 4096
			var xz_off: int = x_off + z * 256
			var xzm_off: int = x_off + (z - 1) * 256
			for iy in range(y_range):
				var y: int = y_min + iy
				var bt: int = blocks[xz_off + y]
				if _is_greedy_solid(bt):
					var nb: int = blocks[xzm_off + y] if z - 1 >= 0 else 0
					if not _is_greedy_solid(nb):
						mask[x][iy] = bt
						has_faces = true
					else:
						mask[x][iy] = -1
				else:
					mask[x][iy] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, y_range)
			for q in quads:
				var u: int = q[0]; var v: int = q[1] + y_min; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var tint: Color = BlockRegistry.get_block_tint(bt, "front") * 0.8
				var tex_name: String = BlockRegistry.get_face_texture(bt, "front")
				var layer: float = float(TextureManager.get_layer_index(tex_name))
				var ao0 = _calculate_ao_for_face(Vector3.FORWARD, u, v, z)
				var ao1 = _calculate_ao_for_face(Vector3.FORWARD, u + w - 1, v, z)
				var ao2 = _calculate_ao_for_face(Vector3.FORWARD, u + w - 1, v + h - 1, z)
				var ao3 = _calculate_ao_for_face(Vector3.FORWARD, u, v + h - 1, z)
				_emit_quad(
					Vector3(u, v, z), Vector3(u + w, v, z),
					Vector3(u + w, v + h, z), Vector3(u, v + h, z),
					Vector3.FORWARD, tint, [ao0[0], ao1[1], ao2[2], ao3[3]], float(w), float(h), layer)

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
				if _is_greedy_solid(bt):
					var nb: int = blocks[xp_off + z_off + y] if x + 1 < CHUNK_SIZE else 0
					if not _is_greedy_solid(nb):
						mask[z][iy] = bt
						has_faces = true
					else:
						mask[z][iy] = -1
				else:
					mask[z][iy] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, y_range)
			for q in quads:
				var u: int = q[0]; var v: int = q[1] + y_min; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var tint: Color = BlockRegistry.get_block_tint(bt, "right") * 0.9
				var tex_name: String = BlockRegistry.get_face_texture(bt, "right")
				var layer: float = float(TextureManager.get_layer_index(tex_name))
				var ao0 = _calculate_ao_for_face(Vector3.RIGHT, x, v, u)
				var ao1 = _calculate_ao_for_face(Vector3.RIGHT, x, v, u + w - 1)
				var ao2 = _calculate_ao_for_face(Vector3.RIGHT, x, v + h - 1, u + w - 1)
				var ao3 = _calculate_ao_for_face(Vector3.RIGHT, x, v + h - 1, u)
				_emit_quad(
					Vector3(x + 1, v, u), Vector3(x + 1, v, u + w),
					Vector3(x + 1, v + h, u + w), Vector3(x + 1, v + h, u),
					Vector3.RIGHT, tint, [ao0[0], ao1[1], ao2[2], ao3[3]], float(w), float(h), layer)

		# --- LEFT (-X) ---
		has_faces = false
		for z in range(CHUNK_SIZE):
			var z_off: int = z * 256
			for iy in range(y_range):
				var y: int = y_min + iy
				var bt: int = blocks[x_off + z_off + y]
				if _is_greedy_solid(bt):
					var nb: int = blocks[xm_off + z_off + y] if x - 1 >= 0 else 0
					if not _is_greedy_solid(nb):
						mask[z][iy] = bt
						has_faces = true
					else:
						mask[z][iy] = -1
				else:
					mask[z][iy] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, y_range)
			for q in quads:
				var u: int = q[0]; var v: int = q[1] + y_min; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var tint: Color = BlockRegistry.get_block_tint(bt, "left") * 0.9
				var tex_name: String = BlockRegistry.get_face_texture(bt, "left")
				var layer: float = float(TextureManager.get_layer_index(tex_name))
				var ao0 = _calculate_ao_for_face(Vector3.LEFT, x, v, u + w - 1)
				var ao1 = _calculate_ao_for_face(Vector3.LEFT, x, v, u)
				var ao2 = _calculate_ao_for_face(Vector3.LEFT, x, v + h - 1, u)
				var ao3 = _calculate_ao_for_face(Vector3.LEFT, x, v + h - 1, u + w - 1)
				_emit_quad(
					Vector3(x, v, u + w), Vector3(x, v, u),
					Vector3(x, v + h, u), Vector3(x, v + h, u + w),
					Vector3.LEFT, tint, [ao0[0], ao1[1], ao2[2], ao3[3]], float(w), float(h), layer)

# ============================================================
# EMISSION D'UN QUAD FUSIONNE
# ============================================================

func _emit_quad(v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3, color: Color, ao: Array, uv_w: float = 1.0, uv_h: float = 1.0, layer: float = 0.0, skip_collision: bool = false):
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

	# UV: V inversé pour que le haut de la texture soit en haut du quad
	_uvs.append(Vector2(0, uv_h))
	_uvs.append(Vector2(uv_w, uv_h))
	_uvs.append(Vector2(uv_w, 0))
	_uvs.append(Vector2(0, 0))

	# CUSTOM0: layer index dans le Texture2DArray
	_custom0.append(layer)
	_custom0.append(layer)
	_custom0.append(layer)
	_custom0.append(layer)

	_indices.append(base)
	_indices.append(base + 1)
	_indices.append(base + 2)
	_indices.append(base + 2)
	_indices.append(base + 3)
	_indices.append(base)

	# Faces de collision (2 triangles)
	if not skip_collision:
		_collision_faces.append(v0)
		_collision_faces.append(v1)
		_collision_faces.append(v2)
		_collision_faces.append(v2)
		_collision_faces.append(v3)
		_collision_faces.append(v0)

# ============================================================
# FLORA MESH — cross billboards (2 quads en X par bloc)
# ============================================================

func _build_flora_mesh():
	if y_min > y_max:
		return
	for x in range(CHUNK_SIZE):
		var x_off: int = x * 4096
		for z in range(CHUNK_SIZE):
			var xz_off: int = x_off + z * 256
			for y in range(y_min, y_max + 1):
				var bt: int = blocks[xz_off + y]
				if CROSS_TYPES.has(bt):
					_emit_cross_quad(x, y, z, bt)

func _emit_cross_quad(x: int, y: int, z: int, bt: int):
	var tex_name: String = BlockRegistry.get_face_texture(bt, "all")
	var layer: float = float(TextureManager.get_layer_index(tex_name))
	var tint: Color = BlockRegistry.get_block_tint(bt, "all")
	var base: int = _flora_vertices.size()

	# Quad 1 : diagonale (0,0) -> (1,1) dans le plan XZ
	var fx: float = float(x)
	var fy: float = float(y)
	var fz: float = float(z)

	_flora_vertices.append(Vector3(fx, fy, fz))
	_flora_vertices.append(Vector3(fx + 1.0, fy, fz + 1.0))
	_flora_vertices.append(Vector3(fx + 1.0, fy + 1.0, fz + 1.0))
	_flora_vertices.append(Vector3(fx, fy + 1.0, fz))

	# Quad 2 : diagonale (1,0) -> (0,1) dans le plan XZ
	_flora_vertices.append(Vector3(fx + 1.0, fy, fz))
	_flora_vertices.append(Vector3(fx, fy, fz + 1.0))
	_flora_vertices.append(Vector3(fx, fy + 1.0, fz + 1.0))
	_flora_vertices.append(Vector3(fx + 1.0, fy + 1.0, fz))

	# Normales vers le haut pour un eclairage uniforme (style MC)
	for i in range(8):
		_flora_normals.append(Vector3.UP)

	# Couleur / tint — layer index encode dans l'alpha du vertex color
	# (contourne un probleme de CUSTOM0 non transmis au shader flora)
	var tint_with_layer := Color(tint.r, tint.g, tint.b, layer / 255.0)
	for i in range(8):
		_flora_colors.append(tint_with_layer)

	# UVs (V inverse) — 2 quads identiques
	for i in range(2):
		_flora_uvs.append(Vector2(0, 1))
		_flora_uvs.append(Vector2(1, 1))
		_flora_uvs.append(Vector2(1, 0))
		_flora_uvs.append(Vector2(0, 0))

	# Layer index (CUSTOM0 — conserve pour compatibilite)
	for i in range(8):
		_flora_custom0.append(layer)

	# Indices — 2 quads = 4 triangles
	_flora_indices.append(base)
	_flora_indices.append(base + 1)
	_flora_indices.append(base + 2)
	_flora_indices.append(base + 2)
	_flora_indices.append(base + 3)
	_flora_indices.append(base)

	_flora_indices.append(base + 4)
	_flora_indices.append(base + 5)
	_flora_indices.append(base + 6)
	_flora_indices.append(base + 6)
	_flora_indices.append(base + 7)
	_flora_indices.append(base + 4)

# ============================================================
# WATER MESH — top faces only (greedy)
# ============================================================

func _build_water_mesh():
	var mask: Array = []
	mask.resize(CHUNK_SIZE)
	for i in range(CHUNK_SIZE):
		mask[i] = []
		mask[i].resize(CHUNK_SIZE)

	for y in range(y_min, y_max + 1):
		var has_faces: bool = false
		for x in range(CHUNK_SIZE):
			var x_off: int = x * 4096
			for z in range(CHUNK_SIZE):
				var idx: int = x_off + z * 256 + y
				var bt: int = blocks[idx]
				if bt == WATER_TYPE and (y + 1 >= CHUNK_HEIGHT or blocks[idx + 1] == 0):
					# Anti-damier : ne pas rendre l'eau en surface si un voisin
					# au meme niveau est un bloc solide (= rive)
					var at_shore: bool = false
					if x > 0:
						var nb: int = blocks[(x - 1) * 4096 + z * 256 + y]
						if nb != 0 and nb != WATER_TYPE:
							at_shore = true
					if not at_shore and x < CHUNK_SIZE - 1:
						var nb: int = blocks[(x + 1) * 4096 + z * 256 + y]
						if nb != 0 and nb != WATER_TYPE:
							at_shore = true
					if not at_shore and z > 0:
						var nb: int = blocks[x_off + (z - 1) * 256 + y]
						if nb != 0 and nb != WATER_TYPE:
							at_shore = true
					if not at_shore and z < CHUNK_SIZE - 1:
						var nb: int = blocks[x_off + (z + 1) * 256 + y]
						if nb != 0 and nb != WATER_TYPE:
							at_shore = true
					if not at_shore:
						mask[x][z] = bt
						has_faces = true
					else:
						mask[x][z] = -1
				else:
					mask[x][z] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, CHUNK_SIZE)
			for q in quads:
				var u: int = q[0]; var v: int = q[1]; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var color: Color = BlockRegistry.get_block_color(bt)
				_emit_water_quad(
					Vector3(u, y + 0.85, v), Vector3(u + w, y + 0.85, v),
					Vector3(u + w, y + 0.85, v + h), Vector3(u, y + 0.85, v + h),
					Vector3.UP, color)

func _emit_water_quad(v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3, color: Color):
	var base: int = _water_vertices.size()
	_water_vertices.append(v0)
	_water_vertices.append(v1)
	_water_vertices.append(v2)
	_water_vertices.append(v3)
	_water_normals.append(normal)
	_water_normals.append(normal)
	_water_normals.append(normal)
	_water_normals.append(normal)
	_water_colors.append(color)
	_water_colors.append(color)
	_water_colors.append(color)
	_water_colors.append(color)
	_water_indices.append(base)
	_water_indices.append(base + 1)
	_water_indices.append(base + 2)
	_water_indices.append(base + 2)
	_water_indices.append(base + 3)
	_water_indices.append(base)

# ============================================================
# TORCHES — rendu visuel + lumière
# ============================================================

func _clear_torch_lights():
	for node in _torch_lights:
		if is_instance_valid(node):
			node.queue_free()
	_torch_lights.clear()

func _spawn_torch_lights():
	_clear_torch_lights()
	if y_min > y_max:
		return

	var count = 0
	for x in range(CHUNK_SIZE):
		if count >= MAX_TORCHES_PER_CHUNK:
			break
		var x_off = x * 4096
		for z in range(CHUNK_SIZE):
			if count >= MAX_TORCHES_PER_CHUNK:
				break
			var xz_off = x_off + z * 256
			for y in range(y_min, y_max + 1):
				var bt_check = blocks[xz_off + y]
				if bt_check == TORCH_TYPE or bt_check == LANTERN_TYPE:
					if bt_check == LANTERN_TYPE:
						_create_lantern_at(x, y, z)
					else:
						_create_torch_at(x, y, z)
					count += 1
					if count >= MAX_TORCHES_PER_CHUNK:
						break

func _create_torch_at(lx: int, ly: int, lz: int):
	# Conteneur pour la torche
	var torch_node = Node3D.new()
	torch_node.position = Vector3(lx + 0.5, ly, lz + 0.5)

	# Pivot pour inclinaison murale (rotation autour de la base)
	var pivot = Node3D.new()
	pivot.name = "TorchPivot"
	torch_node.add_child(pivot)

	# Détecter si torche murale : bloc en dessous non-solide → chercher un mur adjacent
	var is_wall_torch = false
	var wall_angle = 0.0
	var below_bt = _get_local_block(lx, ly - 1, lz)
	if below_bt == 0 or below_bt == 15 or (below_bt >= 77 and below_bt != 83):
		# Pas de support en dessous → chercher un mur solide adjacent
		var checks = [
			[lx - 1, lz, 0.0],    # mur Ouest → pencher vers Est (+X) → rotation Z négative
			[lx + 1, lz, 180.0],  # mur Est → pencher vers Ouest (-X) → rotation Z positive
			[lx, lz - 1, 90.0],   # mur Nord → pencher vers Sud (+Z) → rotation X positive
			[lx, lz + 1, -90.0],  # mur Sud → pencher vers Nord (-Z) → rotation X négative
		]
		for check in checks:
			var cx = int(check[0])
			var cz = int(check[1])
			var adj_bt = _get_local_block(cx, ly, cz)
			if adj_bt != 0 and adj_bt != 15 and (adj_bt < 77 or adj_bt == 83):
				is_wall_torch = true
				wall_angle = check[2]
				break

	if is_wall_torch:
		# Décaler le pivot vers le mur pour que la torche penche depuis le mur
		match wall_angle:
			0.0:    # Mur Ouest → base contre le mur -X, flamme vers +X
				pivot.position = Vector3(-0.45, 0.3, 0)
				pivot.rotation_degrees = Vector3(0, 0, -45)
			180.0:  # Mur Est → base contre le mur +X, flamme vers -X
				pivot.position = Vector3(0.45, 0.3, 0)
				pivot.rotation_degrees = Vector3(0, 0, 45)
			90.0:   # Mur Nord → base contre le mur -Z, flamme vers +Z
				pivot.position = Vector3(0, 0.3, -0.45)
				pivot.rotation_degrees = Vector3(45, 0, 0)
			-90.0:  # Mur Sud → base contre le mur +Z, flamme vers -Z
				pivot.position = Vector3(0, 0.3, 0.45)
				pivot.rotation_degrees = Vector3(-45, 0, 0)

	# Visuel : petit cube doré (manche)
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.15, 0.5, 0.15)
	mesh_inst.mesh = box
	mesh_inst.position = Vector3(0, 0.25, 0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.4, 0.2, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.5, 1.0)
	mat.emission_energy_multiplier = 2.0
	mesh_inst.material_override = mat
	pivot.add_child(mesh_inst)

	# Flamme : petit cube émissif au sommet
	var flame_inst = MeshInstance3D.new()
	var flame_box = BoxMesh.new()
	flame_box.size = Vector3(0.1, 0.15, 0.1)
	flame_inst.mesh = flame_box
	flame_inst.position = Vector3(0, 0.55, 0)
	var flame_mat = StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.7, 0.1, 1.0)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.85, 0.4, 1.0)
	flame_mat.emission_energy_multiplier = 4.0
	flame_inst.material_override = flame_mat
	pivot.add_child(flame_inst)

	# Lumière omnidirectionnelle
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = 1.0
	light.omni_range = 8.0
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	light.position = Vector3(0, 0.6, 0)
	torch_node.add_child(light)

	add_child(torch_node)
	_torch_lights.append(torch_node)

func _get_local_block(lx: int, ly: int, lz: int) -> int:
	if lx < 0 or lx >= CHUNK_SIZE or lz < 0 or lz >= CHUNK_SIZE or ly < 0 or ly >= CHUNK_HEIGHT:
		return 0
	return blocks[lx * 4096 + lz * 256 + ly]

func _create_lantern_at(lx: int, ly: int, lz: int):
	var lantern_node = Node3D.new()
	lantern_node.position = Vector3(lx + 0.5, ly, lz + 0.5)

	# Corps de la lanterne (cube noir + partie dorée)
	var body = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.35, 0.45, 0.35)
	body.mesh = box
	body.position = Vector3(0, 0.225, 0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.35, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4, 1.0)
	mat.emission_energy_multiplier = 3.0
	body.material_override = mat
	lantern_node.add_child(body)

	# Lumière
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = 1.2
	light.omni_range = 10.0
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	light.position = Vector3(0, 0.3, 0)
	lantern_node.add_child(light)

	add_child(lantern_node)
	_torch_lights.append(lantern_node)

# ============================================================
# SPECIAL SHAPE MESH — slabs, stairs, fences, doors, glass panes, ladders, trapdoors
# ============================================================

func _build_special_mesh():
	if y_min > y_max:
		return
	for x in range(CHUNK_SIZE):
		var x_off: int = x * 4096
		for z in range(CHUNK_SIZE):
			var xz_off: int = x_off + z * 256
			for y in range(y_min, y_max + 1):
				var bt: int = blocks[xz_off + y]
				if SLAB_TYPES.has(bt):
					_emit_slab(x, y, z, bt)
				elif STAIR_TYPES.has(bt):
					_emit_stair(x, y, z, bt)
				elif FENCE_TYPES.has(bt):
					_emit_fence(x, y, z, bt)
				elif DOOR_TYPES.has(bt):
					_emit_door(x, y, z, bt)
				elif THIN_TYPES.has(bt):
					if bt == 93:  # LADDER
						_emit_ladder(x, y, z, bt)
					elif bt == 94:  # OAK_TRAPDOOR
						_emit_trapdoor(x, y, z, bt)
					else:  # GLASS_PANE
						_emit_glass_pane(x, y, z, bt)

func _emit_slab(x: int, y: int, z: int, bt: int):
	# Demi-bloc — 1×0.5×1, partie basse
	var fx: float = float(x)
	var fy: float = float(y)
	var fz: float = float(z)
	var tex_name: String = BlockRegistry.get_face_texture(bt, "all")
	var layer: float = float(TextureManager.get_layer_index(tex_name))
	var tint: Color = Color.WHITE
	var ao_full: Array = [1.0, 1.0, 1.0, 1.0]

	# Top face (y + 0.5)
	_emit_quad(
		Vector3(fx, fy + 0.5, fz), Vector3(fx + 1, fy + 0.5, fz),
		Vector3(fx + 1, fy + 0.5, fz + 1), Vector3(fx, fy + 0.5, fz + 1),
		Vector3.UP, tint, ao_full, 1.0, 1.0, layer)
	# Bottom face
	_emit_quad(
		Vector3(fx, fy, fz + 1), Vector3(fx + 1, fy, fz + 1),
		Vector3(fx + 1, fy, fz), Vector3(fx, fy, fz),
		Vector3.DOWN, tint * 0.6, ao_full, 1.0, 1.0, layer)
	# Front (+Z)
	_emit_quad(
		Vector3(fx + 1, fy, fz + 1), Vector3(fx, fy, fz + 1),
		Vector3(fx, fy + 0.5, fz + 1), Vector3(fx + 1, fy + 0.5, fz + 1),
		Vector3.BACK, tint * 0.8, ao_full, 1.0, 0.5, layer)
	# Back (-Z)
	_emit_quad(
		Vector3(fx, fy, fz), Vector3(fx + 1, fy, fz),
		Vector3(fx + 1, fy + 0.5, fz), Vector3(fx, fy + 0.5, fz),
		Vector3.FORWARD, tint * 0.8, ao_full, 1.0, 0.5, layer)
	# Right (+X)
	_emit_quad(
		Vector3(fx + 1, fy, fz), Vector3(fx + 1, fy, fz + 1),
		Vector3(fx + 1, fy + 0.5, fz + 1), Vector3(fx + 1, fy + 0.5, fz),
		Vector3.RIGHT, tint * 0.7, ao_full, 1.0, 0.5, layer)
	# Left (-X)
	_emit_quad(
		Vector3(fx, fy, fz + 1), Vector3(fx, fy, fz),
		Vector3(fx, fy + 0.5, fz), Vector3(fx, fy + 0.5, fz + 1),
		Vector3.LEFT, tint * 0.7, ao_full, 1.0, 0.5, layer)

func _emit_stair(x: int, y: int, z: int, bt: int):
	# Escalier — partie basse pleine (0-0.5) + partie haute arrière (0.5-1.0 sur z=0-0.5)
	var fx: float = float(x)
	var fy: float = float(y)
	var fz: float = float(z)
	var tex_name: String = BlockRegistry.get_face_texture(bt, "all")
	var layer: float = float(TextureManager.get_layer_index(tex_name))
	var tint: Color = Color.WHITE
	var ao: Array = [1.0, 1.0, 1.0, 1.0]

	# ---- Partie basse (dalle 0 à 0.5) ----
	# Bottom
	_emit_quad(
		Vector3(fx, fy, fz + 1), Vector3(fx + 1, fy, fz + 1),
		Vector3(fx + 1, fy, fz), Vector3(fx, fy, fz),
		Vector3.DOWN, tint * 0.6, ao, 1.0, 1.0, layer)
	# Top de la dalle (face visible devant la marche)
	_emit_quad(
		Vector3(fx, fy + 0.5, fz + 1), Vector3(fx + 1, fy + 0.5, fz + 1),
		Vector3(fx + 1, fy + 0.5, fz + 0.5), Vector3(fx, fy + 0.5, fz + 0.5),
		Vector3.UP, tint, ao, 1.0, 0.5, layer)
	# Front (+Z) basse
	_emit_quad(
		Vector3(fx + 1, fy, fz + 1), Vector3(fx, fy, fz + 1),
		Vector3(fx, fy + 0.5, fz + 1), Vector3(fx + 1, fy + 0.5, fz + 1),
		Vector3.BACK, tint * 0.8, ao, 1.0, 0.5, layer)
	# Sides basse
	_emit_quad(
		Vector3(fx + 1, fy, fz), Vector3(fx + 1, fy, fz + 1),
		Vector3(fx + 1, fy + 0.5, fz + 1), Vector3(fx + 1, fy + 0.5, fz),
		Vector3.RIGHT, tint * 0.7, ao, 1.0, 1.0, layer)
	_emit_quad(
		Vector3(fx, fy, fz + 1), Vector3(fx, fy, fz),
		Vector3(fx, fy + 0.5, fz), Vector3(fx, fy + 0.5, fz + 1),
		Vector3.LEFT, tint * 0.7, ao, 1.0, 1.0, layer)

	# ---- Partie haute (marche 0.5 à 1.0, moitié arrière z=0 à 0.5) ----
	# Top de la marche
	_emit_quad(
		Vector3(fx, fy + 1.0, fz), Vector3(fx + 1, fy + 1.0, fz),
		Vector3(fx + 1, fy + 1.0, fz + 0.5), Vector3(fx, fy + 1.0, fz + 0.5),
		Vector3.UP, tint, ao, 1.0, 0.5, layer)
	# Front de la marche (face z=0.5)
	_emit_quad(
		Vector3(fx + 1, fy + 0.5, fz + 0.5), Vector3(fx, fy + 0.5, fz + 0.5),
		Vector3(fx, fy + 1.0, fz + 0.5), Vector3(fx + 1, fy + 1.0, fz + 0.5),
		Vector3.BACK, tint * 0.8, ao, 1.0, 0.5, layer)
	# Back (-Z) pleine hauteur
	_emit_quad(
		Vector3(fx, fy, fz), Vector3(fx + 1, fy, fz),
		Vector3(fx + 1, fy + 1.0, fz), Vector3(fx, fy + 1.0, fz),
		Vector3.FORWARD, tint * 0.8, ao, 1.0, 1.0, layer)
	# Sides hautes (moitié sup des côtés)
	_emit_quad(
		Vector3(fx + 1, fy + 0.5, fz), Vector3(fx + 1, fy + 0.5, fz + 0.5),
		Vector3(fx + 1, fy + 1.0, fz + 0.5), Vector3(fx + 1, fy + 1.0, fz),
		Vector3.RIGHT, tint * 0.7, ao, 0.5, 0.5, layer)
	_emit_quad(
		Vector3(fx, fy + 0.5, fz + 0.5), Vector3(fx, fy + 0.5, fz),
		Vector3(fx, fy + 1.0, fz), Vector3(fx, fy + 1.0, fz + 0.5),
		Vector3.LEFT, tint * 0.7, ao, 0.5, 0.5, layer)

func _emit_fence(x: int, y: int, z: int, bt: int):
	# Poteau central 4/16 × 16/16 × 4/16
	var fx: float = float(x)
	var fy: float = float(y)
	var fz: float = float(z)
	var tex_name: String = BlockRegistry.get_face_texture(bt, "all")
	var layer: float = float(TextureManager.get_layer_index(tex_name))
	var tint: Color = Color.WHITE
	var ao: Array = [1.0, 1.0, 1.0, 1.0]

	var pw: float = 0.25  # post width
	var ph: float = pw / 2.0
	var cx: float = fx + 0.5
	var cz: float = fz + 0.5

	# Top
	_emit_quad(
		Vector3(cx - ph, fy + 1.0, cz - ph), Vector3(cx + ph, fy + 1.0, cz - ph),
		Vector3(cx + ph, fy + 1.0, cz + ph), Vector3(cx - ph, fy + 1.0, cz + ph),
		Vector3.UP, tint, ao, pw, pw, layer)
	# Bottom
	_emit_quad(
		Vector3(cx - ph, fy, cz + ph), Vector3(cx + ph, fy, cz + ph),
		Vector3(cx + ph, fy, cz - ph), Vector3(cx - ph, fy, cz - ph),
		Vector3.DOWN, tint * 0.6, ao, pw, pw, layer)
	# Front (+Z)
	_emit_quad(
		Vector3(cx + ph, fy, cz + ph), Vector3(cx - ph, fy, cz + ph),
		Vector3(cx - ph, fy + 1.0, cz + ph), Vector3(cx + ph, fy + 1.0, cz + ph),
		Vector3.BACK, tint * 0.8, ao, pw, 1.0, layer)
	# Back (-Z)
	_emit_quad(
		Vector3(cx - ph, fy, cz - ph), Vector3(cx + ph, fy, cz - ph),
		Vector3(cx + ph, fy + 1.0, cz - ph), Vector3(cx - ph, fy + 1.0, cz - ph),
		Vector3.FORWARD, tint * 0.8, ao, pw, 1.0, layer)
	# Right (+X)
	_emit_quad(
		Vector3(cx + ph, fy, cz - ph), Vector3(cx + ph, fy, cz + ph),
		Vector3(cx + ph, fy + 1.0, cz + ph), Vector3(cx + ph, fy + 1.0, cz - ph),
		Vector3.RIGHT, tint * 0.7, ao, pw, 1.0, layer)
	# Left (-X)
	_emit_quad(
		Vector3(cx - ph, fy, cz + ph), Vector3(cx - ph, fy, cz - ph),
		Vector3(cx - ph, fy + 1.0, cz - ph), Vector3(cx - ph, fy + 1.0, cz + ph),
		Vector3.LEFT, tint * 0.7, ao, pw, 1.0, layer)

func _emit_door(x: int, y: int, z: int, bt: int):
	# Porte — panneau plat 1×2×3/16, orienté face au +Z
	var fx: float = float(x)
	var fy: float = float(y)
	var fz: float = float(z)
	var tex_name: String = BlockRegistry.get_face_texture(bt, "all")
	var layer: float = float(TextureManager.get_layer_index(tex_name))
	var tint: Color = Color.WHITE
	var ao: Array = [1.0, 1.0, 1.0, 1.0]
	var depth: float = 3.0 / 16.0

	# Front face (+Z)
	_emit_quad(
		Vector3(fx + 1, fy, fz + depth), Vector3(fx, fy, fz + depth),
		Vector3(fx, fy + 1.0, fz + depth), Vector3(fx + 1, fy + 1.0, fz + depth),
		Vector3.BACK, tint, ao, 1.0, 1.0, layer)
	# Back face (-Z)
	_emit_quad(
		Vector3(fx, fy, fz), Vector3(fx + 1, fy, fz),
		Vector3(fx + 1, fy + 1.0, fz), Vector3(fx, fy + 1.0, fz),
		Vector3.FORWARD, tint, ao, 1.0, 1.0, layer)
	# Top
	_emit_quad(
		Vector3(fx, fy + 1.0, fz), Vector3(fx + 1, fy + 1.0, fz),
		Vector3(fx + 1, fy + 1.0, fz + depth), Vector3(fx, fy + 1.0, fz + depth),
		Vector3.UP, tint, ao, 1.0, depth, layer)
	# Bottom
	_emit_quad(
		Vector3(fx, fy, fz + depth), Vector3(fx + 1, fy, fz + depth),
		Vector3(fx + 1, fy, fz), Vector3(fx, fy, fz),
		Vector3.DOWN, tint * 0.6, ao, 1.0, depth, layer)
	# Right side
	_emit_quad(
		Vector3(fx + 1, fy, fz), Vector3(fx + 1, fy, fz + depth),
		Vector3(fx + 1, fy + 1.0, fz + depth), Vector3(fx + 1, fy + 1.0, fz),
		Vector3.RIGHT, tint * 0.7, ao, depth, 1.0, layer)
	# Left side
	_emit_quad(
		Vector3(fx, fy, fz + depth), Vector3(fx, fy, fz),
		Vector3(fx, fy + 1.0, fz), Vector3(fx, fy + 1.0, fz + depth),
		Vector3.LEFT, tint * 0.7, ao, depth, 1.0, layer)

func _emit_glass_pane(x: int, y: int, z: int, bt: int):
	# Vitre — panneau plat centré 1×1×2/16 orienté N-S
	var fx: float = float(x)
	var fy: float = float(y)
	var fz: float = float(z)
	var tex_name: String = BlockRegistry.get_face_texture(bt, "all")
	var layer: float = float(TextureManager.get_layer_index(tex_name))
	var tint: Color = Color.WHITE
	var ao: Array = [1.0, 1.0, 1.0, 1.0]
	var half: float = 1.0 / 16.0
	var cz: float = fz + 0.5

	# Front face
	_emit_quad(
		Vector3(fx + 1, fy, cz + half), Vector3(fx, fy, cz + half),
		Vector3(fx, fy + 1.0, cz + half), Vector3(fx + 1, fy + 1.0, cz + half),
		Vector3.BACK, tint, ao, 1.0, 1.0, layer)
	# Back face
	_emit_quad(
		Vector3(fx, fy, cz - half), Vector3(fx + 1, fy, cz - half),
		Vector3(fx + 1, fy + 1.0, cz - half), Vector3(fx, fy + 1.0, cz - half),
		Vector3.FORWARD, tint, ao, 1.0, 1.0, layer)
	# Top
	_emit_quad(
		Vector3(fx, fy + 1.0, cz - half), Vector3(fx + 1, fy + 1.0, cz - half),
		Vector3(fx + 1, fy + 1.0, cz + half), Vector3(fx, fy + 1.0, cz + half),
		Vector3.UP, tint, ao, 1.0, half * 2, layer)
	# Bottom
	_emit_quad(
		Vector3(fx, fy, cz + half), Vector3(fx + 1, fy, cz + half),
		Vector3(fx + 1, fy, cz - half), Vector3(fx, fy, cz - half),
		Vector3.DOWN, tint * 0.6, ao, 1.0, half * 2, layer)

func _emit_ladder(x: int, y: int, z: int, bt: int):
	# Échelle — panneau plat collé au mur -Z (face +Z)
	var fx: float = float(x)
	var fy: float = float(y)
	var fz: float = float(z)
	var tex_name: String = BlockRegistry.get_face_texture(bt, "all")
	var layer: float = float(TextureManager.get_layer_index(tex_name))
	var tint: Color = Color.WHITE
	var ao: Array = [1.0, 1.0, 1.0, 1.0]
	var offset: float = 1.0 / 16.0

	# Face visible (plaquée contre le mur -Z) — pas de collision pour permettre l'escalade
	_emit_quad(
		Vector3(fx + 1, fy, fz + offset), Vector3(fx, fy, fz + offset),
		Vector3(fx, fy + 1.0, fz + offset), Vector3(fx + 1, fy + 1.0, fz + offset),
		Vector3.BACK, tint, ao, 1.0, 1.0, layer, true)
	# Face arrière (contre le mur)
	_emit_quad(
		Vector3(fx, fy, fz), Vector3(fx + 1, fy, fz),
		Vector3(fx + 1, fy + 1.0, fz), Vector3(fx, fy + 1.0, fz),
		Vector3.FORWARD, tint, ao, 1.0, 1.0, layer, true)

func _emit_trapdoor(x: int, y: int, z: int, bt: int):
	# Trappe — panneau horizontal 1×3/16×1, au bas du bloc
	var fx: float = float(x)
	var fy: float = float(y)
	var fz: float = float(z)
	var tex_name: String = BlockRegistry.get_face_texture(bt, "all")
	var layer: float = float(TextureManager.get_layer_index(tex_name))
	var tint: Color = Color.WHITE
	var ao: Array = [1.0, 1.0, 1.0, 1.0]
	var height: float = 3.0 / 16.0

	# Top
	_emit_quad(
		Vector3(fx, fy + height, fz), Vector3(fx + 1, fy + height, fz),
		Vector3(fx + 1, fy + height, fz + 1), Vector3(fx, fy + height, fz + 1),
		Vector3.UP, tint, ao, 1.0, 1.0, layer)
	# Bottom
	_emit_quad(
		Vector3(fx, fy, fz + 1), Vector3(fx + 1, fy, fz + 1),
		Vector3(fx + 1, fy, fz), Vector3(fx, fy, fz),
		Vector3.DOWN, tint * 0.6, ao, 1.0, 1.0, layer)
	# Sides
	_emit_quad(
		Vector3(fx + 1, fy, fz + 1), Vector3(fx, fy, fz + 1),
		Vector3(fx, fy + height, fz + 1), Vector3(fx + 1, fy + height, fz + 1),
		Vector3.BACK, tint * 0.8, ao, 1.0, height, layer)
	_emit_quad(
		Vector3(fx, fy, fz), Vector3(fx + 1, fy, fz),
		Vector3(fx + 1, fy + height, fz), Vector3(fx, fy + height, fz),
		Vector3.FORWARD, tint * 0.8, ao, 1.0, height, layer)
	_emit_quad(
		Vector3(fx + 1, fy, fz), Vector3(fx + 1, fy, fz + 1),
		Vector3(fx + 1, fy + height, fz + 1), Vector3(fx + 1, fy + height, fz),
		Vector3.RIGHT, tint * 0.7, ao, 1.0, height, layer)
	_emit_quad(
		Vector3(fx, fy, fz + 1), Vector3(fx, fy, fz),
		Vector3(fx, fy + height, fz), Vector3(fx, fy + height, fz + 1),
		Vector3.LEFT, tint * 0.7, ao, 1.0, height, layer)

# ============================================================
# AMBIENT OCCLUSION
# ============================================================

func _is_block_solid(x: int, y: int, z: int) -> bool:
	if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_HEIGHT or z < 0 or z >= CHUNK_SIZE:
		return false
	var bt: int = blocks[x * 4096 + z * 256 + y]
	return bt != 0 and bt != WATER_TYPE and bt != TORCH_TYPE and not CROSS_TYPES.has(bt)

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

func _calculate_vertex_ao(_x1: int, _y1: int, _z1: int, _x2: int, _y2: int, _z2: int, _x3: int, _y3: int, _z3: int) -> float:
	return 1.0
