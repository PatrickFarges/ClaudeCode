extends CharacterBody3D
class_name PassiveMob

const BedrockEntity = preload("res://scripts/bedrock_entity.gd")

enum MobType { SHEEP, COW, CHICKEN, PIG, WOLF, HORSE }

# Bedrock model paths + textures — replaces old Sketchfab GLBs
const BEDROCK_BASE := "res://assets/Mobs/Bedrock/"
const MOB_DATA = {
	MobType.SHEEP: {
		"collision_size": Vector3(0.9, 1.3, 0.9),
		"geo_path": BEDROCK_BASE + "models/sheep.geo.json",
		"geo_id": "geometry.sheep.sheared.v1.8",
		"texture": "res://TexturesPack/Aurore Stone/assets/minecraft/textures/entity/sheep/sheep.png",
		"health": 8, "meat_name": "Mouton", "meat_count": 2,
		"bone_map": { "body": "body", "head": "head",
			"leg0": "leg0", "leg1": "leg1", "leg2": "leg2", "leg3": "leg3" },
	},
	MobType.COW: {
		"collision_size": Vector3(0.9, 1.4, 0.9),
		"geo_path": BEDROCK_BASE + "models/cow.geo.json",
		"geo_id": "geometry.cow.v1.8",
		"texture": BEDROCK_BASE + "textures/cow.png",
		"health": 10, "meat_name": "Boeuf", "meat_count": 3,
		"bone_map": { "body": "body", "head": "head",
			"leg0": "leg0", "leg1": "leg1", "leg2": "leg2", "leg3": "leg3" },
	},
	MobType.CHICKEN: {
		"collision_size": Vector3(0.5, 0.7, 0.5),
		"geo_path": BEDROCK_BASE + "models/chicken.geo.json",
		"geo_id": "geometry.chicken",
		"texture": BEDROCK_BASE + "textures/chicken.png",
		"health": 4, "meat_name": "Poulet", "meat_count": 1,
		"bone_map": { "body": "body", "head": "head",
			"leg0": "leg0", "leg1": "leg1",
			"wing0": "wing0", "wing1": "wing1" },
	},
	MobType.PIG: {
		"collision_size": Vector3(0.9, 0.9, 0.9),
		"geo_path": BEDROCK_BASE + "models/pig.geo.json",
		"geo_id": "geometry.pig.v1.8",
		"texture": BEDROCK_BASE + "textures/pig.png",
		"health": 10, "meat_name": "Porc", "meat_count": 3,
		"bone_map": { "body": "body", "head": "head",
			"leg0": "leg0", "leg1": "leg1", "leg2": "leg2", "leg3": "leg3" },
	},
	MobType.WOLF: {
		"collision_size": Vector3(0.6, 0.85, 0.6),
		"geo_path": BEDROCK_BASE + "models/wolf.geo.json",
		"geo_id": "geometry.wolf",
		"texture": BEDROCK_BASE + "textures/wolf.png",
		"health": 8, "meat_name": "Loup", "meat_count": 0,
		"bone_map": { "body": "body", "head": "head", "upperBody": "upperBody",
			"leg0": "leg0", "leg1": "leg1", "leg2": "leg2", "leg3": "leg3",
			"tail": "tail" },
	},
	MobType.HORSE: {
		"collision_size": Vector3(1.4, 1.6, 1.4),
		"geo_path": BEDROCK_BASE + "models/horse_v2.geo.json",
		"geo_id": "geometry.horse.v2",
		"texture": BEDROCK_BASE + "textures/horse.png",
		"health": 15, "meat_name": "Cheval", "meat_count": 0,
		"bone_map": { "body": "Body", "head": "Head", "neck": "Neck",
			"leg0": "Leg1A", "leg1": "Leg2A", "leg2": "Leg3A", "leg3": "Leg4A",
			"tail": "TailA" },
		"skip_bones": ["Saddle", "HeadSaddle", "SaddleMouthL", "SaddleMouthR",
			"SaddleMouthLine", "SaddleMouthLineR", "Bag1", "Bag2",
			"MuleEarL", "MuleEarR"],
	},
}

# Texture cache: path → Texture2D
static var _tex_cache: Dictionary = {}

var mob_type: MobType = MobType.SHEEP
var chunk_position: Vector3i = Vector3i.ZERO
var _spawn_pos: Vector3 = Vector3.ZERO

var health: int = 10
var move_speed: float = 1.5
var wander_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var is_moving: bool = false
var gravity_val: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var world_manager = null
var _model_root: Node3D = null
var _hurt_flash_timer: float = 0.0

# Bone references for skeletal animation
var _bone_body: Node3D = null
var _bone_head: Node3D = null
var _bone_neck: Node3D = null   # horse only
var _bone_upper: Node3D = null  # wolf upperBody
var _bone_tail: Node3D = null
var _bone_legs: Array = []      # [leg0, leg1, leg2, leg3]
var _bone_wings: Array = []     # chicken [wing0, wing1]

# Animation state — MC-authentic limbSwing system
var _limb_swing: float = 0.0      # Continuous walk cycle counter (distance-based)
var _limb_swing_amount: float = 0.0  # 0..1 speed factor (0=idle, 1=full run)
var _idle_time: float = 0.0       # Time accumulator for idle animations
var _age_ticks: float = 0.0       # Continuous time for time-based anims (chicken wings)

# Store bind-pose rotations for legs
var _leg_bind_rots: Array = []
var _head_bind_rot := Vector3.ZERO
var _body_bind_rot := Vector3.ZERO

func setup(type: MobType, pos: Vector3, chunk_pos: Vector3i):
	mob_type = type
	_spawn_pos = pos
	chunk_position = chunk_pos
	health = MOB_DATA[type]["health"]

func _ready():
	position = _spawn_pos
	_create_bedrock_model()
	_create_collision()
	_pick_new_wander()
	rotation.y = randf() * TAU
	world_manager = get_tree().get_first_node_in_group("world_manager")
	add_to_group("passive_mobs")

# ============================================================
#  MODEL CREATION
# ============================================================

func _create_bedrock_model():
	var data: Dictionary = MOB_DATA[mob_type]
	var geo_path: String = data["geo_path"]
	var geo_id: String = data["geo_id"]
	var texture: Texture2D = _load_texture(data["texture"])
	if not texture:
		_create_fallback_mesh()
		return

	# Build model from Bedrock geometry
	var skip: Array = data.get("skip_bones", [])
	var model := BedrockEntity.build_model(geo_path, texture, geo_id, skip)
	if not model:
		_create_fallback_mesh()
		return

	_model_root = model
	add_child(model)

	# Grab bone references
	var bone_map: Dictionary = data["bone_map"]
	_bone_body = _find_bone(model, bone_map.get("body", ""))
	_bone_head = _find_bone(model, bone_map.get("head", ""))
	_bone_neck = _find_bone(model, bone_map.get("neck", ""))
	_bone_upper = _find_bone(model, bone_map.get("upperBody", ""))
	_bone_tail = _find_bone(model, bone_map.get("tail", ""))

	# Legs
	_bone_legs.clear()
	_leg_bind_rots.clear()
	for key in ["leg0", "leg1", "leg2", "leg3"]:
		var bname: String = bone_map.get(key, "")
		var bone := _find_bone(model, bname)
		_bone_legs.append(bone)
		_leg_bind_rots.append(bone.rotation_degrees if bone else Vector3.ZERO)

	# Wings (chicken)
	_bone_wings.clear()
	for key in ["wing0", "wing1"]:
		var bname: String = bone_map.get(key, "")
		if bname != "":
			var bone := _find_bone(model, bname)
			if bone:
				_bone_wings.append(bone)

	# Save bind rotations
	if _bone_head:
		_head_bind_rot = _bone_head.rotation_degrees
	if _bone_body:
		_body_bind_rot = _bone_body.rotation_degrees

static func _load_texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex = load(path) as Texture2D
	if tex:
		_tex_cache[path] = tex
	else:
		push_warning("[PassiveMob] Cannot load texture: " + path)
	return tex

func _find_bone(root: Node3D, bname: String) -> Node3D:
	if bname == "":
		return null
	if root.name == bname:
		return root
	for child in root.get_children():
		if child is Node3D:
			var found := _find_bone(child as Node3D, bname)
			if found:
				return found
	return null

func _create_fallback_mesh():
	var mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	var data = MOB_DATA[mob_type]
	box.size = data["collision_size"]
	mesh_instance.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.8, 0.8)
	mat.roughness = 0.8
	mesh_instance.material_override = mat
	mesh_instance.position.y = data["collision_size"].y / 2.0
	_model_root = mesh_instance
	add_child(mesh_instance)

func _create_collision():
	var data = MOB_DATA[mob_type]
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = data["collision_size"]
	col.shape = shape
	col.position.y = data["collision_size"].y / 2.0
	add_child(col)

# ============================================================
#  PHYSICS + AI
# ============================================================

func _physics_process(delta):
	if _hurt_flash_timer > 0:
		_hurt_flash_timer -= delta
		if _hurt_flash_timer <= 0:
			_reset_model_color()

	if not is_on_floor():
		velocity.y -= gravity_val * delta

	wander_timer -= delta
	if wander_timer <= 0:
		_pick_new_wander()

	if is_moving and is_on_floor():
		if world_manager:
			var ahead_pos = global_position + wander_direction * 1.0
			var ahead_block = world_manager.get_block_at_position(ahead_pos.floor())
			var below_ahead = world_manager.get_block_at_position((ahead_pos - Vector3(0, 1, 0)).floor())
			if ahead_block == BlockRegistry.BlockType.WATER or below_ahead == BlockRegistry.BlockType.AIR:
				_pick_new_wander()
				is_moving = false

		velocity.x = wander_direction.x * move_speed
		velocity.z = wander_direction.z * move_speed

		if wander_direction.length_squared() > 0.01:
			# Bedrock models face -Z, so negate direction for correct facing
			rotation.y = atan2(-wander_direction.x, -wander_direction.z)

		var speed := Vector2(velocity.x, velocity.z).length()
		# MC EntityLivingBase.onLivingUpdate():
		#   float f = sqrt(motionX² + motionZ²);
		#   limbSwingAmount += (f * 4.0 - limbSwingAmount) * 0.4;  // per tick
		#   limbSwing += limbSwingAmount;                           // per tick
		# Conversion: speed (blocks/sec) / 20 = speed per tick
		var speed_per_tick := speed / 20.0
		var mc_target := clampf(speed_per_tick * 4.0, 0.0, 1.0)
		# Smoothing: MC uses 0.4 per tick → frame-rate independent
		var smooth := 1.0 - pow(0.6, delta * 20.0)  # 0.6 = 1 - 0.4, 20 ticks/sec
		_limb_swing_amount = lerpf(_limb_swing_amount, mc_target, smooth)
		# MC: limbSwing += limbSwingAmount per tick = limbSwingAmount * 20 per sec
		_limb_swing += _limb_swing_amount * 20.0 * delta
		_animate_walk(delta)
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0, move_speed * 2.0)
		# Smoothly decay limb swing amount to 0 (same MC smoothing)
		var smooth_stop := 1.0 - pow(0.6, delta * 20.0)
		_limb_swing_amount = lerpf(_limb_swing_amount, 0.0, smooth_stop)
		_animate_idle(delta)

	# Always tick age for time-based animations (chicken wings etc.)
	_age_ticks += delta * 20.0  # Convert to MC tick rate (20 ticks/sec)

	move_and_slide()

# ============================================================
#  SKELETAL ANIMATION — MC-authentic formulas (from MC 1.12 source)
#
#  MC EntityLivingBase.onLivingUpdate():
#    limbSwingAmount += (sqrt(motionX²+motionZ²) * 4.0 - limbSwingAmount) * 0.4
#    limbSwing += limbSwingAmount
#
#  ModelQuadruped.setRotationAngles():
#    leg.rotateAngleX = cos(limbSwing * 0.6662) * 1.4 * limbSwingAmount
#    Diagonal pairs: legs 0,3 together; legs 1,2 opposite (π phase shift)
#    At cow walk speed (~1.5 b/s): limbSwingAmount ≈ 0.3, amplitude ≈ 24°
#    Walk cycle period ≈ 1.6 seconds
# ============================================================

# MC constants — from ModelQuadruped.setRotationAngles()
const MC_LEG_FREQ := 0.6662    # Walk cycle frequency (rad per limbSwing unit)
const MC_LEG_AMP := 1.4        # Max leg swing amplitude in RADIANS (≈80°)

func _animate_walk(_delta: float):
	var swing := _limb_swing
	var amount := _limb_swing_amount

	# --- Quadruped legs (MC diagonal pairs) ---
	# MC formula: cos(limbSwing * 0.6662) * 1.4 * limbSwingAmount
	var leg_rad: float = cos(swing * MC_LEG_FREQ) * MC_LEG_AMP * amount
	var leg_deg: float = rad_to_deg(leg_rad)

	if _bone_legs.size() >= 4:
		# Legs 0,3 swing together; legs 1,2 swing opposite (π phase shift)
		if _bone_legs[0]: _bone_legs[0].rotation_degrees.x = _leg_bind_rots[0].x + leg_deg
		if _bone_legs[1]: _bone_legs[1].rotation_degrees.x = _leg_bind_rots[1].x - leg_deg
		if _bone_legs[2]: _bone_legs[2].rotation_degrees.x = _leg_bind_rots[2].x - leg_deg
		if _bone_legs[3]: _bone_legs[3].rotation_degrees.x = _leg_bind_rots[3].x + leg_deg
	elif _bone_legs.size() >= 2:
		# Chicken: 2 legs, same formula
		if _bone_legs[0]: _bone_legs[0].rotation_degrees.x = _leg_bind_rots[0].x + leg_deg
		if _bone_legs[1]: _bone_legs[1].rotation_degrees.x = _leg_bind_rots[1].x - leg_deg

	# --- Chicken wings (time-based, not walk-based) ---
	# MC: rightWing.rotateAngleZ = ageInTicks; leftWing.rotateAngleZ = -ageInTicks
	# We use a sinusoidal variant since Bedrock wings are differently mounted
	if _bone_wings.size() >= 2:
		# Flap faster when moving, slower when idle
		var wing_speed := 1.0 + amount * 3.0
		var wing_amp := 20.0 + amount * 25.0  # 20° idle, up to 45° while running
		var wing_angle := sin(_age_ticks * 0.4 * wing_speed) * wing_amp
		_bone_wings[0].rotation_degrees.z = wing_angle
		_bone_wings[1].rotation_degrees.z = -wing_angle

	# --- Head: no bob during walk in MC (only yaw/pitch from look direction) ---
	# Keep head at bind pose during walk
	if _bone_head:
		_bone_head.rotation_degrees.x = _head_bind_rot.x
		_bone_head.rotation_degrees.y = 0.0

	# --- Wolf/Horse tail wag (MC: same formula as legs but on Y axis) ---
	if _bone_tail:
		if mob_type == MobType.WOLF:
			# MC wolf: tail.rotateAngleY = cos(limbSwing * 0.6662) * 1.4 * limbSwingAmount
			var tail_rad := cos(swing * MC_LEG_FREQ) * MC_LEG_AMP * amount
			_bone_tail.rotation_degrees.y = rad_to_deg(tail_rad)
		else:
			# Horse: gentle sway
			var tail_sway := sin(_age_ticks * 0.07) * 15.0
			_bone_tail.rotation_degrees.y = tail_sway

func _animate_idle(delta: float):
	_idle_time += delta

	# --- Smoothly return legs to bind pose ---
	for i in range(_bone_legs.size()):
		var leg = _bone_legs[i]
		if leg:
			var bind_x: float = _leg_bind_rots[i].x if i < _leg_bind_rots.size() else 0.0
			leg.rotation_degrees.x = lerpf(leg.rotation_degrees.x, bind_x, delta * 5.0)

	# --- Chicken wings: gentle idle flap ---
	if _bone_wings.size() >= 2:
		var idle_wing := sin(_age_ticks * 0.4) * 5.0  # Very subtle idle flap
		_bone_wings[0].rotation_degrees.z = lerpf(_bone_wings[0].rotation_degrees.z, idle_wing, delta * 5.0)
		_bone_wings[1].rotation_degrees.z = lerpf(_bone_wings[1].rotation_degrees.z, -idle_wing, delta * 5.0)

	# --- Head: slow idle look-around ---
	if _bone_head:
		var look_yaw := sin(_idle_time * 0.5) * 15.0
		var look_pitch := sin(_idle_time * 0.3) * 5.0
		_bone_head.rotation_degrees.y = lerpf(_bone_head.rotation_degrees.y, look_yaw, delta * 2.0)
		_bone_head.rotation_degrees.x = lerpf(_bone_head.rotation_degrees.x, _head_bind_rot.x + look_pitch, delta * 2.0)

	# --- Wolf tail: gentle resting wag ---
	# MC: when not angry, tail.rotateAngleY = cos(limbSwing * 0.6662) * 1.4 * limbSwingAmount
	# At idle limbSwingAmount ≈ 0, so tail is nearly still. Add a tiny happy wag.
	if _bone_tail:
		if mob_type == MobType.WOLF:
			var wag := sin(_idle_time * 3.0) * 8.0  # Gentle happy wag
			_bone_tail.rotation_degrees.y = lerpf(_bone_tail.rotation_degrees.y, wag, delta * 3.0)
		else:
			_bone_tail.rotation_degrees.y = lerpf(_bone_tail.rotation_degrees.y, 0.0, delta * 3.0)

	# --- Subtle breathing via body scale ---
	if _bone_body:
		var breath := 1.0 + sin(_idle_time * 2.0) * 0.01
		_bone_body.scale = Vector3(breath, breath, breath)

# ============================================================
#  DÉGÂTS ET MORT
# ============================================================

func take_hit(damage: int, knockback: Vector3 = Vector3.ZERO):
	health -= damage
	velocity += knockback
	_hurt_flash_timer = 0.3
	_flash_model_red()
	if health <= 0:
		_drop_loot()
		queue_free()

func _drop_loot():
	var data = MOB_DATA[mob_type]
	var meat_count = data["meat_count"]
	if meat_count <= 0:
		return
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node and player_node.has_method("heal"):
		var heal_amount = meat_count * 2
		player_node.heal(heal_amount)
		_spawn_loot_label(data["meat_name"], meat_count)

func _spawn_loot_label(item_name: String, count: int):
	var label = Label3D.new()
	label.text = "+%d %s" % [count, item_name]
	label.font_size = 36
	label.outline_size = 6
	label.modulate = Color(0.3, 1.0, 0.3)
	label.outline_modulate = Color(0, 0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.01
	get_tree().root.add_child(label)
	label.global_position = global_position + Vector3(0, 2.0, 0)

	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", global_position + Vector3(0, 3.5, 0), 1.5)
	tween.tween_property(label, "modulate:a", 0.0, 1.5).set_delay(0.5)
	tween.set_parallel(false)
	tween.tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
	)

func _flash_model_red():
	if _model_root:
		_apply_tint_recursive(_model_root, Color(2.0, 0.5, 0.5))

func _reset_model_color():
	if _model_root:
		_apply_tint_recursive(_model_root, Color(1, 1, 1))

func _apply_tint_recursive(node: Node, color: Color):
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		if mi.material_override and mi.material_override is StandardMaterial3D:
			mi.material_override.albedo_color = color
		elif mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				var mat = mi.get_active_material(i)
				if mat is StandardMaterial3D:
					mat.albedo_color = color
	for child in node.get_children():
		_apply_tint_recursive(child, color)

func _pick_new_wander():
	wander_timer = randf_range(2.0, 5.0)
	is_moving = randf() > 0.4
	if is_moving:
		var angle = randf() * TAU
		wander_direction = Vector3(cos(angle), 0, sin(angle)).normalized()
