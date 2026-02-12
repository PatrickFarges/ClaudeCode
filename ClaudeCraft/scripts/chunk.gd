extends Node3D
class_name Chunk

const CHUNK_SIZE = 16
const CHUNK_HEIGHT = 256  # Hauteur du monde

var chunk_position: Vector3i
var blocks: Array = []
var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D
var static_body: StaticBody3D
var _vertex_count: int = 0  # Compteur de vertices pour le meshing
var is_mesh_built: bool = false

func _init(pos: Vector3i, block_data: Array = []):
	chunk_position = pos
	if block_data.size() > 0:
		blocks = block_data
	else:
		_initialize_blocks()

func _initialize_blocks():
	# Initialiser le tableau 3D de blocs (vide par défaut)
	blocks.resize(CHUNK_SIZE)
	for x in range(CHUNK_SIZE):
		blocks[x] = []
		blocks[x].resize(CHUNK_SIZE)
		for z in range(CHUNK_SIZE):
			blocks[x][z] = []
			blocks[x][z].resize(CHUNK_HEIGHT)
			for y in range(CHUNK_HEIGHT):
				blocks[x][z][y] = BlockRegistry.BlockType.AIR

func set_blocks(block_data: Array):
	"""Définir les blocs du chunk (appelé après génération threaded)"""
	blocks = block_data

func build_mesh():
	"""Construire le mesh du chunk (appelé dans le thread principal)"""
	if is_mesh_built:
		return

	_create_mesh()
	_create_collision()
	is_mesh_built = true

# ============================================================
# CREATION DU MESH — Greedy Meshing
# ============================================================
# Au lieu de générer 4 vertices par face visible (brute-force),
# on fusionne les faces adjacentes du même type en rectangles
# plus grands. Réduit le nombre de vertices de 10 à 100x.
# ============================================================

func _create_mesh():
	_vertex_count = 0

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.albedo_color = Color(1, 1, 1, 1)
	material.roughness = 0.8
	material.metallic = 0.0

	# Greedy meshing par direction de face
	_greedy_mesh_y_faces(st)  # UP + DOWN
	_greedy_mesh_z_faces(st)  # BACK + FORWARD
	_greedy_mesh_x_faces(st)  # RIGHT + LEFT

	var mesh = st.commit()

	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)

# ============================================================
# ALGORITHME GREEDY 2D
# ============================================================

func _run_greedy(mask: Array, u_size: int, v_size: int) -> Array:
	"""Balaye un masque 2D et fusionne les cellules adjacentes identiques.
	Retourne [[u, v, w, h, block_type], ...]"""
	var quads: Array = []
	for v in range(v_size):
		var u: int = 0
		while u < u_size:
			var bt: int = mask[u][v]
			if bt == -1:
				u += 1
				continue

			# Étendre en largeur (direction u)
			var w: int = 1
			while u + w < u_size and mask[u + w][v] == bt:
				w += 1

			# Étendre en hauteur (direction v)
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

			# Effacer le rectangle du masque
			for dv in range(h):
				for du in range(w):
					mask[u + du][v + dv] = -1

			u += w
	return quads

# ============================================================
# FACES Y (UP / DOWN) — masque u=x, v=z
# ============================================================

func _greedy_mesh_y_faces(st: SurfaceTool):
	var mask: Array = []
	mask.resize(CHUNK_SIZE)
	for i in range(CHUNK_SIZE):
		mask[i] = []
		mask[i].resize(CHUNK_SIZE)

	for y in range(CHUNK_HEIGHT):
		# --- UP (+Y) ---
		var has_faces: bool = false
		for x in range(CHUNK_SIZE):
			for z in range(CHUNK_SIZE):
				var bt: int = blocks[x][z][y]
				if bt != BlockRegistry.BlockType.AIR and (y + 1 >= CHUNK_HEIGHT or blocks[x][z][y + 1] == BlockRegistry.BlockType.AIR):
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
				_emit_quad(st,
					Vector3(u, y + 1, v), Vector3(u + w, y + 1, v),
					Vector3(u + w, y + 1, v + h), Vector3(u, y + 1, v + h),
					Vector3.UP, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

		# --- DOWN (-Y) ---
		has_faces = false
		for x in range(CHUNK_SIZE):
			for z in range(CHUNK_SIZE):
				var bt: int = blocks[x][z][y]
				if bt != BlockRegistry.BlockType.AIR and (y - 1 < 0 or blocks[x][z][y - 1] == BlockRegistry.BlockType.AIR):
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
				_emit_quad(st,
					Vector3(u, y, v + h), Vector3(u + w, y, v + h),
					Vector3(u + w, y, v), Vector3(u, y, v),
					Vector3.DOWN, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

# ============================================================
# FACES Z (BACK / FORWARD) — masque u=x, v=y
# ============================================================

func _greedy_mesh_z_faces(st: SurfaceTool):
	var mask: Array = []
	mask.resize(CHUNK_SIZE)
	for i in range(CHUNK_SIZE):
		mask[i] = []
		mask[i].resize(CHUNK_HEIGHT)

	for z in range(CHUNK_SIZE):
		# --- BACK (+Z) ---
		var has_faces: bool = false
		for x in range(CHUNK_SIZE):
			for y in range(CHUNK_HEIGHT):
				var bt: int = blocks[x][z][y]
				if bt != BlockRegistry.BlockType.AIR and (z + 1 >= CHUNK_SIZE or blocks[x][z + 1][y] == BlockRegistry.BlockType.AIR):
					mask[x][y] = bt
					has_faces = true
				else:
					mask[x][y] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, CHUNK_HEIGHT)
			for q in quads:
				var u: int = q[0]; var v: int = q[1]; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var color: Color = BlockRegistry.get_block_color(bt) * 0.8
				var ao0 = _calculate_ao_for_face(Vector3.BACK, u + w - 1, v, z)
				var ao1 = _calculate_ao_for_face(Vector3.BACK, u, v, z)
				var ao2 = _calculate_ao_for_face(Vector3.BACK, u, v + h - 1, z)
				var ao3 = _calculate_ao_for_face(Vector3.BACK, u + w - 1, v + h - 1, z)
				_emit_quad(st,
					Vector3(u + w, v, z + 1), Vector3(u, v, z + 1),
					Vector3(u, v + h, z + 1), Vector3(u + w, v + h, z + 1),
					Vector3.BACK, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

		# --- FORWARD (-Z) ---
		has_faces = false
		for x in range(CHUNK_SIZE):
			for y in range(CHUNK_HEIGHT):
				var bt: int = blocks[x][z][y]
				if bt != BlockRegistry.BlockType.AIR and (z - 1 < 0 or blocks[x][z - 1][y] == BlockRegistry.BlockType.AIR):
					mask[x][y] = bt
					has_faces = true
				else:
					mask[x][y] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, CHUNK_HEIGHT)
			for q in quads:
				var u: int = q[0]; var v: int = q[1]; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var color: Color = BlockRegistry.get_block_color(bt) * 0.8
				var ao0 = _calculate_ao_for_face(Vector3.FORWARD, u, v, z)
				var ao1 = _calculate_ao_for_face(Vector3.FORWARD, u + w - 1, v, z)
				var ao2 = _calculate_ao_for_face(Vector3.FORWARD, u + w - 1, v + h - 1, z)
				var ao3 = _calculate_ao_for_face(Vector3.FORWARD, u, v + h - 1, z)
				_emit_quad(st,
					Vector3(u, v, z), Vector3(u + w, v, z),
					Vector3(u + w, v + h, z), Vector3(u, v + h, z),
					Vector3.FORWARD, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

# ============================================================
# FACES X (RIGHT / LEFT) — masque u=z, v=y
# ============================================================

func _greedy_mesh_x_faces(st: SurfaceTool):
	var mask: Array = []
	mask.resize(CHUNK_SIZE)
	for i in range(CHUNK_SIZE):
		mask[i] = []
		mask[i].resize(CHUNK_HEIGHT)

	for x in range(CHUNK_SIZE):
		# --- RIGHT (+X) ---
		var has_faces: bool = false
		for z in range(CHUNK_SIZE):
			for y in range(CHUNK_HEIGHT):
				var bt: int = blocks[x][z][y]
				if bt != BlockRegistry.BlockType.AIR and (x + 1 >= CHUNK_SIZE or blocks[x + 1][z][y] == BlockRegistry.BlockType.AIR):
					mask[z][y] = bt
					has_faces = true
				else:
					mask[z][y] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, CHUNK_HEIGHT)
			for q in quads:
				var u: int = q[0]; var v: int = q[1]; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var color: Color = BlockRegistry.get_block_color(bt) * 0.9
				var ao0 = _calculate_ao_for_face(Vector3.RIGHT, x, v, u)
				var ao1 = _calculate_ao_for_face(Vector3.RIGHT, x, v, u + w - 1)
				var ao2 = _calculate_ao_for_face(Vector3.RIGHT, x, v + h - 1, u + w - 1)
				var ao3 = _calculate_ao_for_face(Vector3.RIGHT, x, v + h - 1, u)
				_emit_quad(st,
					Vector3(x + 1, v, u), Vector3(x + 1, v, u + w),
					Vector3(x + 1, v + h, u + w), Vector3(x + 1, v + h, u),
					Vector3.RIGHT, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

		# --- LEFT (-X) ---
		has_faces = false
		for z in range(CHUNK_SIZE):
			for y in range(CHUNK_HEIGHT):
				var bt: int = blocks[x][z][y]
				if bt != BlockRegistry.BlockType.AIR and (x - 1 < 0 or blocks[x - 1][z][y] == BlockRegistry.BlockType.AIR):
					mask[z][y] = bt
					has_faces = true
				else:
					mask[z][y] = -1

		if has_faces:
			var quads = _run_greedy(mask, CHUNK_SIZE, CHUNK_HEIGHT)
			for q in quads:
				var u: int = q[0]; var v: int = q[1]; var w: int = q[2]; var h: int = q[3]; var bt: int = q[4]
				var color: Color = BlockRegistry.get_block_color(bt) * 0.9
				var ao0 = _calculate_ao_for_face(Vector3.LEFT, x, v, u + w - 1)
				var ao1 = _calculate_ao_for_face(Vector3.LEFT, x, v, u)
				var ao2 = _calculate_ao_for_face(Vector3.LEFT, x, v + h - 1, u)
				var ao3 = _calculate_ao_for_face(Vector3.LEFT, x, v + h - 1, u + w - 1)
				_emit_quad(st,
					Vector3(x, v, u + w), Vector3(x, v, u),
					Vector3(x, v + h, u), Vector3(x, v + h, u + w),
					Vector3.LEFT, color, [ao0[0], ao1[1], ao2[2], ao3[3]])

# ============================================================
# EMISSION D'UN QUAD FUSIONNE
# ============================================================

func _emit_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3, color: Color, ao: Array):
	var base: int = _vertex_count

	st.set_normal(normal)
	st.set_color(color * ao[0])
	st.add_vertex(v0)

	st.set_normal(normal)
	st.set_color(color * ao[1])
	st.add_vertex(v1)

	st.set_normal(normal)
	st.set_color(color * ao[2])
	st.add_vertex(v2)

	st.set_normal(normal)
	st.set_color(color * ao[3])
	st.add_vertex(v3)

	_vertex_count += 4

	# Deux triangles pour le quad
	st.add_index(base)
	st.add_index(base + 1)
	st.add_index(base + 2)
	st.add_index(base + 2)
	st.add_index(base + 3)
	st.add_index(base)

# ============================================================
# VISIBILITE ET AMBIENT OCCLUSION
# ============================================================

func _is_face_visible(x: int, y: int, z: int) -> bool:
	if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_HEIGHT or z < 0 or z >= CHUNK_SIZE:
		return true
	return blocks[x][z][y] == BlockRegistry.BlockType.AIR

func _is_block_solid(x: int, y: int, z: int) -> bool:
	if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_HEIGHT or z < 0 or z >= CHUNK_SIZE:
		return false
	return blocks[x][z][y] != BlockRegistry.BlockType.AIR

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
		return 0.4  # Coin très sombre

	var total = side1 + side2 + corner
	if total == 0:
		return 1.0  # Pleine luminosité
	elif total == 1:
		return 0.85  # Légèrement assombri
	elif total == 2:
		return 0.65  # Moyennement assombri
	else:
		return 0.5  # Très assombri

# ============================================================
# COLLISION
# ============================================================

func _create_collision():
	static_body = StaticBody3D.new()
	collision_shape = CollisionShape3D.new()

	var shape = ConcavePolygonShape3D.new()
	if mesh_instance and mesh_instance.mesh:
		shape.set_faces(mesh_instance.mesh.get_faces())

	collision_shape.shape = shape
	static_body.add_child(collision_shape)
	add_child(static_body)

# ============================================================
# ACCES AUX BLOCS
# ============================================================

func get_block(x: int, y: int, z: int) -> BlockRegistry.BlockType:
	if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_HEIGHT or z < 0 or z >= CHUNK_SIZE:
		return BlockRegistry.BlockType.AIR
	return blocks[x][z][y]

func set_block(x: int, y: int, z: int, block_type: BlockRegistry.BlockType):
	if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_HEIGHT or z < 0 or z >= CHUNK_SIZE:
		return

	blocks[x][z][y] = block_type
	_rebuild_mesh()

func _rebuild_mesh():
	if mesh_instance:
		mesh_instance.queue_free()
		mesh_instance = null
	if static_body:
		static_body.queue_free()
		static_body = null

	call_deferred("_deferred_rebuild")

func _deferred_rebuild():
	is_mesh_built = false
	build_mesh()
