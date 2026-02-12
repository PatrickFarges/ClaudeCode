extends Node3D
class_name BlockHighlighter

# Système de viseur de bloc + feedback visuel de minage

var mesh_instance: MeshInstance3D  # Outline wireframe
var crack_instance: MeshInstance3D  # Overlay de minage (s'assombrit)
var material: StandardMaterial3D
var crack_material: StandardMaterial3D
var current_block_pos: Vector3 = Vector3.ZERO
var is_visible: bool = false
var current_color: Color = Color.WHITE
var _mining_progress: float = 0.0

func _ready():
	# ============================================================
	# WIREFRAME OUTLINE (le contour blanc du bloc visé)
	# ============================================================
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 1, 1, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	
	_create_outline_mesh()
	mesh_instance.material_override = material
	mesh_instance.visible = false
	
	# ============================================================
	# CRACK OVERLAY (cube semi-transparent qui s'assombrit pendant le minage)
	# ============================================================
	crack_instance = MeshInstance3D.new()
	add_child(crack_instance)
	
	crack_material = StandardMaterial3D.new()
	crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crack_material.albedo_color = Color(0, 0, 0, 0)  # Invisible au départ
	crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crack_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	crack_material.no_depth_test = true
	
	_create_crack_mesh()
	crack_instance.material_override = crack_material
	crack_instance.visible = false

func _create_outline_mesh():
	"""Créer un cube wireframe (lignes)"""
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_LINES)
	
	var corners = [
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 1, 0), Vector3(1, 1, 0),
		Vector3(1, 1, 1), Vector3(0, 1, 1)
	]
	
	# Légèrement plus grand que le bloc pour être visible
	for i in range(corners.size()):
		corners[i] -= Vector3(0.5, 0.5, 0.5)
		corners[i] *= 1.01
		corners[i] += Vector3(0.5, 0.5, 0.5)
	
	var edges = [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7]
	]
	
	for edge in edges:
		surface_tool.set_color(Color.WHITE)
		surface_tool.add_vertex(corners[edge[0]])
		surface_tool.add_vertex(corners[edge[1]])
	
	mesh_instance.mesh = surface_tool.commit()

func _create_crack_mesh():
	"""Créer un cube plein semi-transparent pour l'overlay de minage"""
	var box = BoxMesh.new()
	box.size = Vector3(1.005, 1.005, 1.005)  # Légèrement plus grand
	crack_instance.mesh = box
	# Décaler pour centrer sur le bloc
	crack_instance.position = Vector3(0.5, 0.5, 0.5)

func update_position(block_pos: Vector3, visible: bool, color: Color = Color(1, 1, 1, 0.6)):
	"""Mettre à jour la position et visibilité du highlighter"""
	if not material:
		return
	if block_pos != current_block_pos or visible != is_visible or color != current_color:
		current_block_pos = block_pos
		is_visible = visible
		current_color = color
		
		if visible:
			global_position = block_pos
			material.albedo_color = color
			mesh_instance.visible = true
		else:
			mesh_instance.visible = false
			crack_instance.visible = false
			_mining_progress = 0.0

func set_mining_progress(progress: float):
	"""Mettre à jour le feedback visuel du minage (0.0 à 1.0)"""
	if not material or not crack_material:
		return  # Pas encore initialisé
	_mining_progress = clampf(progress, 0.0, 1.0)
	
	if _mining_progress <= 0.0:
		# Pas de minage — juste l'outline normal
		material.albedo_color = current_color
		crack_instance.visible = false
		return
	
	# Montrer le crack overlay
	crack_instance.visible = true
	
	# Couleur de l'outline selon la progression
	if _mining_progress < 0.25:
		material.albedo_color = Color(1.0, 1.0, 0.5, 0.8)  # Jaune
	elif _mining_progress < 0.50:
		material.albedo_color = Color(1.0, 0.7, 0.2, 0.9)  # Orange
	elif _mining_progress < 0.75:
		material.albedo_color = Color(1.0, 0.4, 0.1, 0.9)  # Orange-rouge
	else:
		material.albedo_color = Color(1.0, 0.15, 0.1, 1.0)  # Rouge vif
	
	# Overlay de minage : de transparent à sombre
	var alpha = _mining_progress * 0.55  # Max 0.55 d'opacité
	crack_material.albedo_color = Color(0.05, 0.05, 0.05, alpha)
	
	# Léger effet de "pulse" quand on est proche de casser
	if _mining_progress > 0.75:
		var pulse = sin(Time.get_ticks_msec() * 0.012) * 0.02
		crack_instance.scale = Vector3.ONE * (1.0 + pulse)
	else:
		crack_instance.scale = Vector3.ONE

func hide_highlight():
	"""Cacher le highlighter"""
	if mesh_instance:
		mesh_instance.visible = false
	if crack_instance:
		crack_instance.visible = false
	is_visible = false
	_mining_progress = 0.0
