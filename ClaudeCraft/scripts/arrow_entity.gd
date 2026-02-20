extends Node3D

## Entité flèche — projectile tiré par l'arc
## Physique simplifiée : gravité + drag + collision raycast

const GC = preload("res://scripts/game_config.gd")

# Physique MC-like
const GRAVITY = 20.0          # Accélération vers le bas (m/s²)
const AIR_DRAG = 0.99          # Friction par frame (MC: 0.99/tick)
const GROUND_LIFETIME = 60.0   # Secondes avant disparition une fois plantée
const MAX_LIFETIME = 30.0      # Secondes max en vol

# Dégâts
var base_damage: float = 6.0
var is_critical: bool = false
var velocity_factor: float = 1.0  # 0-1, basé sur la charge

# État
var direction: Vector3 = Vector3.ZERO
var speed: float = 0.0
var in_ground: bool = false
var lifetime: float = 0.0
var ground_timer: float = 0.0
var shooter: Node = null

# Visuel
var mesh_instance: MeshInstance3D = null
var trail_particles: CPUParticles3D = null

func _ready():
	_build_arrow_mesh()
	_add_trail_particles()

func initialize(origin: Vector3, dir: Vector3, charge_factor: float, shoot_node: Node = null):
	# Spawn légèrement en avant de la caméra pour éviter l'auto-collision
	global_position = origin + dir.normalized() * 0.8
	direction = dir.normalized()
	velocity_factor = charge_factor
	speed = charge_factor * 40.0  # Vitesse réduite pour mieux voir la flèche
	is_critical = charge_factor >= 1.0
	shooter = shoot_node
	_orient_to_direction()
	print("[Arrow] Spawned at %s dir=%s speed=%.1f factor=%.2f" % [str(global_position), str(direction), speed, charge_factor])

func _process(delta: float):
	lifetime += delta
	if lifetime > MAX_LIFETIME:
		queue_free()
		return

	if in_ground:
		ground_timer += delta
		if ground_timer > GROUND_LIFETIME:
			queue_free()
		return

	# Appliquer la gravité
	direction.y -= GRAVITY * delta / maxf(speed, 1.0)
	direction = direction.normalized()

	# Mouvement
	var move = direction * speed * delta

	# Collision raycast
	var space = get_world_3d().direct_space_state
	if space:
		var query = PhysicsRayQueryParameters3D.create(global_position, global_position + move)
		if shooter and is_instance_valid(shooter) and lifetime < 0.2:
			query.exclude = [shooter.get_rid()]
		var result = space.intersect_ray(query)
		if result:
			_on_hit(result)
			return

	global_position += move

	# Drag
	speed *= pow(AIR_DRAG, delta * 60.0)

	# Réorienter la flèche
	_orient_to_direction()

	# Dégâts aux mobs/NPCs
	_check_entity_hits()

func _on_hit(result: Dictionary):
	# Planter la flèche dans le bloc
	global_position = result.position - direction * 0.1
	in_ground = true
	speed = 0.0
	if trail_particles:
		trail_particles.emitting = false
	# Particules d'impact
	_spawn_impact_particles(result.position)
	# Son d'impact
	var audio = get_tree().get_first_node_in_group("audio_manager")
	if audio:
		audio.play_place_sound(BlockRegistry.BlockType.STONE, global_position)
	print("[Arrow] Hit block at %s" % str(result.position))

func _check_entity_hits():
	var hit_range = 1.2
	for mob in get_tree().get_nodes_in_group("passive_mobs"):
		if not is_instance_valid(mob):
			continue
		var dist = global_position.distance_to(mob.global_position + Vector3(0, 0.5, 0))
		if dist < hit_range:
			_damage_entity(mob)
			return
	for npc in get_tree().get_nodes_in_group("npc_villagers"):
		if not is_instance_valid(npc):
			continue
		var dist = global_position.distance_to(npc.global_position + Vector3(0, 0.8, 0))
		if dist < hit_range:
			_damage_entity(npc)
			return

func _damage_entity(entity: Node):
	var damage = _calculate_damage()
	# Knockback
	var kb_dir = direction * 8.0
	kb_dir.y = 3.0  # Un peu de lift
	if entity.has_method("take_hit"):
		entity.take_hit(damage, kb_dir)
	elif entity is CharacterBody3D:
		entity.velocity += kb_dir
	# Feedback visuel — chiffre de dégâts flottant
	_spawn_damage_number(entity.global_position + Vector3(0, 1.5, 0), damage)
	# Particules d'impact sur l'entité
	_spawn_hit_particles(entity.global_position + Vector3(0, 0.5, 0))
	in_ground = true
	speed = 0.0
	ground_timer = GROUND_LIFETIME - 3.0
	if trail_particles:
		trail_particles.emitting = false
	print("[Arrow] Hit entity! Damage: %d" % damage)

func _calculate_damage() -> int:
	var vel_mag = speed / 40.0  # Normaliser
	var dmg = ceili(vel_mag * base_damage)
	if is_critical:
		dmg += randi_range(1, ceili(dmg / 2.0) + 2)
	return maxi(1, dmg)

func _orient_to_direction():
	if direction.length_squared() < 0.001:
		return
	var yaw = atan2(direction.x, direction.z)
	var pitch = -asin(clampf(direction.y, -1.0, 1.0))
	rotation = Vector3(pitch, yaw, 0)

# ============================================================
# VISUEL — Mesh de la flèche
# ============================================================

func _build_arrow_mesh():
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)

	# Construire la flèche à partir de la texture d'item
	var tex_path = GC.get_item_texture_path() + "arrow.png"
	var abs_path = ProjectSettings.globalize_path(tex_path)
	var img = Image.new()

	if img.load(abs_path) == OK:
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != 16 or img.get_height() != 16:
			img.resize(16, 16, Image.INTERPOLATE_NEAREST)
		mesh_instance.mesh = _build_flat_arrow(img)
	else:
		# Fallback : bâton visible
		var box = BoxMesh.new()
		box.size = Vector3(0.06, 0.06, 0.8)
		mesh_instance.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.4, 0.2)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_instance.material_override = mat
		print("[Arrow] Fallback mesh (texture not found: %s)" % abs_path)

	mesh_instance.rotation_degrees = Vector3(0, 0, 45)
	mesh_instance.scale = Vector3(1.5, 1.5, 1.5)

func _build_flat_arrow(img: Image) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var length = 0.8
	var width = 0.2

	var tex = ImageTexture.create_from_image(img)
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var h = length * 0.5
	var w = width * 0.5
	# Quad 1 (horizontal)
	st.set_uv(Vector2(0, 1)); st.set_normal(Vector3(0, 1, 0)); st.add_vertex(Vector3(-w, 0, -h))
	st.set_uv(Vector2(1, 1)); st.set_normal(Vector3(0, 1, 0)); st.add_vertex(Vector3(w, 0, -h))
	st.set_uv(Vector2(1, 0)); st.set_normal(Vector3(0, 1, 0)); st.add_vertex(Vector3(w, 0, h))
	st.set_uv(Vector2(0, 1)); st.set_normal(Vector3(0, 1, 0)); st.add_vertex(Vector3(-w, 0, -h))
	st.set_uv(Vector2(1, 0)); st.set_normal(Vector3(0, 1, 0)); st.add_vertex(Vector3(w, 0, h))
	st.set_uv(Vector2(0, 0)); st.set_normal(Vector3(0, 1, 0)); st.add_vertex(Vector3(-w, 0, h))
	# Quad 2 (vertical)
	st.set_uv(Vector2(0, 1)); st.set_normal(Vector3(1, 0, 0)); st.add_vertex(Vector3(0, -w, -h))
	st.set_uv(Vector2(1, 1)); st.set_normal(Vector3(1, 0, 0)); st.add_vertex(Vector3(0, w, -h))
	st.set_uv(Vector2(1, 0)); st.set_normal(Vector3(1, 0, 0)); st.add_vertex(Vector3(0, w, h))
	st.set_uv(Vector2(0, 1)); st.set_normal(Vector3(1, 0, 0)); st.add_vertex(Vector3(0, -w, -h))
	st.set_uv(Vector2(1, 0)); st.set_normal(Vector3(1, 0, 0)); st.add_vertex(Vector3(0, w, h))
	st.set_uv(Vector2(0, 0)); st.set_normal(Vector3(1, 0, 0)); st.add_vertex(Vector3(0, -w, h))
	st.commit(mesh)
	return mesh

# ============================================================
# PARTICULES
# ============================================================

func _add_trail_particles():
	trail_particles = CPUParticles3D.new()
	trail_particles.amount = 8
	trail_particles.lifetime = 0.4
	trail_particles.explosiveness = 0.0
	trail_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	trail_particles.direction = Vector3(0, 0, -1)
	trail_particles.spread = 10.0
	trail_particles.initial_velocity_min = 0.3
	trail_particles.initial_velocity_max = 1.0
	trail_particles.gravity = Vector3(0, -2, 0)
	trail_particles.scale_amount_min = 0.02
	trail_particles.scale_amount_max = 0.05
	trail_particles.color = Color(1, 1, 0.7, 0.8) if is_critical else Color(0.8, 0.8, 0.8, 0.6)
	var box = BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	trail_particles.mesh = box
	add_child(trail_particles)

func _spawn_impact_particles(pos: Vector3):
	var particles = CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 8
	particles.lifetime = 0.5
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.1
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 3.0
	particles.gravity = Vector3(0, -10, 0)
	particles.scale_amount_min = 0.03
	particles.scale_amount_max = 0.07
	particles.color = Color(0.6, 0.5, 0.4)
	var box = BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	particles.mesh = box
	get_tree().root.add_child(particles)
	particles.global_position = pos
	particles.restart()
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)

func _spawn_hit_particles(pos: Vector3):
	var particles = CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 12
	particles.lifetime = 0.4
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.2
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 5.0
	particles.gravity = Vector3(0, -12, 0)
	particles.scale_amount_min = 0.05
	particles.scale_amount_max = 0.1
	particles.color = Color(0.9, 0.2, 0.2)  # Rouge sang
	var box = BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	particles.mesh = box
	get_tree().root.add_child(particles)
	particles.global_position = pos
	particles.restart()
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)

func _spawn_damage_number(pos: Vector3, damage: int):
	# Créer un label 3D flottant avec les dégâts
	var label = Label3D.new()
	label.text = str(damage)
	label.font_size = 48
	label.outline_size = 8
	label.modulate = Color(1, 0.3, 0.3) if is_critical else Color(1, 1, 1)
	label.outline_modulate = Color(0, 0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.01
	get_tree().root.add_child(label)
	label.global_position = pos

	# Animation : monter + fade out
	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", pos + Vector3(0, 1.5, 0), 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.3)
	tween.set_parallel(false)
	tween.tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
	)
