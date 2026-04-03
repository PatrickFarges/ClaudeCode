## BedrockAnimPlayer v1.0.0
## Moteur d'animation Bedrock pour ClaudeCraft.
## Charge les animations JSON Bedrock, évalue les expressions Molang par frame,
## et applique les transformations directement aux bones du Skeleton3D.
## Remplace complètement l'AnimationPlayer de Godot pour un contrôle total.
##
## Usage:
##   var bap = BedrockAnimPlayer.new()
##   add_child(bap)
##   bap.setup(skeleton_3d, bone_rest_map)
##   bap.load_animations("res://data/animations/humanoid.animation.json")
##   bap.play("animation.humanoid.move")
##
## Changelog:
## v1.0.0 - Implémentation initiale : chargement JSON, évaluateur Molang, machine à états

class_name BedrockAnimPlayer
extends Node

const APP_VERSION := "1.0.0"

# ─── Signals ─────────────────────────────────────────────────────────────────
signal animation_started(anim_name: String)
signal animation_finished(anim_name: String)
signal state_changed(controller_name: String, old_state: String, new_state: String)

# ─── Configuration ───────────────────────────────────────────────────────────
## Skeleton3D cible
var skeleton: Skeleton3D = null

## Évaluateur Molang (partagé)
var molang: MolangEvaluator = null

## Animations chargées : { "animation.name" : AnimData }
var animations: Dictionary = {}

## Controllers chargés : { "controller.name" : ControllerData }
var controllers: Dictionary = {}

## Pre-animation scripts (Molang expressions évaluées avant chaque frame)
var pre_animation_scripts: Array[String] = []

## Variables d'entité persistantes (variable.*)
var variables: Dictionary = {}

## Mapping bone name -> bone index (cache)
var _bone_map: Dictionary = {}

## Bone rest rotations (pour 'this' et reset)
var _bone_rest: Dictionary = {}  # bone_name -> Quaternion

## Animations actuellement actives avec leur blend weight
## [{ "name": str, "weight": float, "time": float, "loop": bool, "length": float, "override": bool }]
var _active_anims: Array = []

## États des controllers : { controller_name: current_state_name }
var _controller_states: Dictionary = {}

## Timer global
var _life_time: float = 0.0
var _distance_moved: float = 0.0
var _move_speed: float = 0.0

## Paused
var paused: bool = false

## Speed multiplier
var speed_scale: float = 1.0

## Entity state queries (set by the game code)
var entity_queries: Dictionary = {}

# ─── Structures internes ─────────────────────────────────────────────────────

class AnimData:
	var name: String
	var loop: bool = false
	var length: float = 0.0
	var override_previous: bool = false
	var anim_time_update: String = ""  # Molang expression for custom time
	var blend_weight_expr: String = ""  # Molang expression for blend weight
	var bones: Dictionary = {}  # bone_name -> BoneAnimData

class BoneAnimData:
	var rotation = null    # Static [x,y,z], keyframe dict, or Molang expression array
	var position = null    # Same
	var scale = null       # Same
	var relative_to_entity: bool = false

class ControllerData:
	var name: String
	var initial_state: String = "default"
	var states: Dictionary = {}  # state_name -> StateData

class StateData:
	var animations: Array = []  # [{"name": str, "condition": str}]
	var transitions: Array = []  # [{"target": str, "condition": str}]
	var blend_transition: float = 0.0


# ─── Setup ───────────────────────────────────────────────────────────────────

func setup(skel: Skeleton3D) -> void:
	skeleton = skel
	molang = MolangEvaluator.new()

	# Build bone map
	_bone_map.clear()
	_bone_rest.clear()
	for i in range(skeleton.get_bone_count()):
		var bname := skeleton.get_bone_name(i).to_lower()
		_bone_map[bname] = i
		_bone_rest[bname] = skeleton.get_bone_rest(i).basis.get_rotation_quaternion()


## Charge un fichier d'animation JSON Bedrock.
func load_animations(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("BedrockAnimPlayer: impossible de lire " + path)
		return 0

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("BedrockAnimPlayer: JSON parse error dans " + path)
		return 0

	var data: Dictionary = json.data
	if not data.has("animations"):
		return 0

	var count := 0
	for anim_name in data["animations"]:
		var anim_dict: Dictionary = data["animations"][anim_name]
		var anim := AnimData.new()
		anim.name = anim_name
		anim.loop = anim_dict.get("loop", false)
		anim.length = anim_dict.get("animation_length", 0.0)
		anim.override_previous = anim_dict.get("override_previous_animation", false)
		if anim_dict.has("anim_time_update"):
			anim.anim_time_update = str(anim_dict["anim_time_update"])
		if anim_dict.has("blend_weight"):
			anim.blend_weight_expr = str(anim_dict["blend_weight"])

		# Parse bones
		if anim_dict.has("bones"):
			for bone_name in anim_dict["bones"]:
				var bone_dict: Dictionary = anim_dict["bones"][bone_name]
				var bone_anim := BoneAnimData.new()

				if bone_dict.has("rotation"):
					bone_anim.rotation = bone_dict["rotation"]
				if bone_dict.has("position"):
					bone_anim.position = bone_dict["position"]
				if bone_dict.has("scale"):
					bone_anim.scale = bone_dict["scale"]
				if bone_dict.has("relative_to"):
					var rel = bone_dict["relative_to"]
					if rel is Dictionary and rel.get("rotation", "") == "entity":
						bone_anim.relative_to_entity = true

				anim.bones[bone_name.to_lower()] = bone_anim

		# Auto-detect length from keyframes
		if anim.length <= 0.0:
			anim.length = _detect_anim_length(anim)
		if anim.length <= 0.0:
			anim.length = 1.0  # Expressions-only anims: 1s default

		animations[anim_name] = anim
		count += 1

	return count


## Charge un fichier d'animation controller JSON Bedrock.
func load_controllers(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return 0

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return 0

	var data: Dictionary = json.data
	if not data.has("animation_controllers"):
		return 0

	var count := 0
	for ctrl_name in data["animation_controllers"]:
		var ctrl_dict: Dictionary = data["animation_controllers"][ctrl_name]
		var ctrl := ControllerData.new()
		ctrl.name = ctrl_name
		ctrl.initial_state = ctrl_dict.get("initial_state", "default")

		if ctrl_dict.has("states"):
			for state_name in ctrl_dict["states"]:
				var state_dict: Dictionary = ctrl_dict["states"][state_name]
				var state := StateData.new()

				# Animations dans l'état
				if state_dict.has("animations"):
					for anim_entry in state_dict["animations"]:
						if anim_entry is String:
							state.animations.append({"name": anim_entry, "condition": ""})
						elif anim_entry is Dictionary:
							for anim_name in anim_entry:
								var cond = anim_entry[anim_name]
								state.animations.append({"name": anim_name, "condition": str(cond) if cond is String else ""})

				# Transitions
				if state_dict.has("transitions"):
					for trans_entry in state_dict["transitions"]:
						if trans_entry is Dictionary:
							for target in trans_entry:
								state.transitions.append({"target": target, "condition": str(trans_entry[target])})

				state.blend_transition = state_dict.get("blend_transition", 0.0)
				ctrl.states[state_name] = state

		controllers[ctrl_name] = ctrl
		_controller_states[ctrl_name] = ctrl.initial_state
		count += 1

	return count


## Mappe un nom court d'animation vers le nom complet.
## Ex: anim_aliases["move"] = "animation.humanoid.move"
var anim_aliases: Dictionary = {}

func set_alias(short_name: String, full_name: String) -> void:
	anim_aliases[short_name] = full_name

func _resolve_anim_name(name: String) -> String:
	return anim_aliases.get(name, name)


# ─── Playback Control ───────────────────────────────────────────────────────

## Joue une animation (additive par défaut).
func play(anim_name: String, weight: float = 1.0) -> void:
	var resolved := _resolve_anim_name(anim_name)
	if not animations.has(resolved):
		return

	# Check if already active
	for entry in _active_anims:
		if entry["name"] == resolved:
			entry["weight"] = weight
			entry["time"] = 0.0
			return

	var anim: AnimData = animations[resolved]
	_active_anims.append({
		"name": resolved,
		"weight": weight,
		"time": 0.0,
		"loop": anim.loop,
		"length": anim.length,
		"override": anim.override_previous,
	})
	animation_started.emit(resolved)


## Arrête une animation.
func stop(anim_name: String) -> void:
	var resolved := _resolve_anim_name(anim_name)
	for i in range(_active_anims.size() - 1, -1, -1):
		if _active_anims[i]["name"] == resolved:
			_active_anims.remove_at(i)
			animation_finished.emit(resolved)
			return


## Arrête toutes les animations.
func stop_all() -> void:
	_active_anims.clear()


## Vérifie si une animation est active.
func is_playing(anim_name: String) -> bool:
	var resolved := _resolve_anim_name(anim_name)
	for entry in _active_anims:
		if entry["name"] == resolved:
			return true
	return false


# ─── Active Controller ──────────────────────────────────────────────────────

## Active un controller (le met en route).
func activate_controller(ctrl_name: String) -> void:
	if controllers.has(ctrl_name):
		var ctrl: ControllerData = controllers[ctrl_name]
		_controller_states[ctrl_name] = ctrl.initial_state


# ─── Entity State Updates ───────────────────────────────────────────────────
## Appelé par le code jeu chaque frame pour mettre à jour l'état de l'entité.

func update_movement(delta: float, velocity: Vector3, distance_moved: float) -> void:
	_move_speed = velocity.length()
	_distance_moved = distance_moved


func set_query(key: String, value: float) -> void:
	entity_queries[key] = value


# ─── Main Loop ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if paused or skeleton == null:
		return

	var dt := delta * speed_scale
	_life_time += dt

	# Update Molang context
	_update_molang_context(dt)

	# Evaluate pre-animation scripts
	for script_expr in pre_animation_scripts:
		if not script_expr.is_empty():
			# Pre-animation scripts can set variables
			_eval_pre_anim(script_expr)

	# Evaluate controllers -> update active animations
	_evaluate_controllers()

	# Update animation times
	_update_anim_times(dt)

	# Apply all active animations to bones
	_apply_animations_to_skeleton()


func _update_molang_context(dt: float) -> void:
	# Timing
	molang.context["query.life_time"] = fmod(_life_time, 1000.0)
	molang.context["query.delta_time"] = dt

	# Movement
	molang.context["query.modified_distance_moved"] = _distance_moved
	molang.context["query.modified_move_speed"] = _move_speed
	molang.context["query.ground_speed"] = _move_speed
	molang.context["query.walk_distance"] = _distance_moved

	# Entity queries
	for key in entity_queries:
		molang.context[key] = entity_queries[key]

	# Variables
	for key in variables:
		molang.context["variable." + key] = variables[key]

	# gliding_speed_value = move speed (normalise le swing des bras/jambes)
	if not molang.context.has("variable.gliding_speed_value") or molang.context["variable.gliding_speed_value"] < 0.01:
		molang.context["variable.gliding_speed_value"] = maxf(_move_speed, 0.1)


func _eval_pre_anim(script_text: String) -> void:
	# Pre-animation scripts are semicolon-separated assignments
	# e.g. "variable.tcos0 = (Math.cos(query.modified_distance_moved * 38.17) * query.modified_move_speed / variable.gliding_speed_value) * 57.3;"
	# We need to parse assignments: "variable.x = expression"
	var parts := script_text.split(";")
	for part in parts:
		part = part.strip_edges()
		if part.is_empty():
			continue
		var eq_pos := part.find("=")
		if eq_pos < 0:
			# Just evaluate as expression
			molang.evaluate(part)
			continue
		# Check it's not == or !=
		if eq_pos + 1 < part.length() and part[eq_pos + 1] == "=":
			molang.evaluate(part)
			continue
		if eq_pos > 0 and part[eq_pos - 1] == "!":
			molang.evaluate(part)
			continue

		var var_name := part.substr(0, eq_pos).strip_edges()
		var expr := part.substr(eq_pos + 1).strip_edges()

		# Expand shorthands
		if var_name.begins_with("v."):
			var_name = "variable." + var_name.substr(2)

		var value := molang.evaluate(expr)
		molang.context[var_name] = value
		# Also store in variables dict if it's a variable
		if var_name.begins_with("variable."):
			variables[var_name.substr(9)] = value


func _evaluate_controllers() -> void:
	for ctrl_name in _controller_states:
		if not controllers.has(ctrl_name):
			continue
		var ctrl: ControllerData = controllers[ctrl_name]
		var current_state_name: String = _controller_states[ctrl_name]
		if not ctrl.states.has(current_state_name):
			continue
		var current_state: StateData = ctrl.states[current_state_name]

		# Check transitions
		for trans in current_state.transitions:
			if trans["condition"].is_empty():
				continue
			var cond_result := molang.evaluate(trans["condition"])
			if cond_result != 0.0:
				var old_state := current_state_name
				_controller_states[ctrl_name] = trans["target"]
				state_changed.emit(ctrl_name, old_state, trans["target"])
				break

	# Build active animations from controllers
	_active_anims.clear()
	for ctrl_name in _controller_states:
		if not controllers.has(ctrl_name):
			continue
		var ctrl: ControllerData = controllers[ctrl_name]
		var state_name: String = _controller_states[ctrl_name]
		if not ctrl.states.has(state_name):
			continue
		var state: StateData = ctrl.states[state_name]

		for anim_entry in state.animations:
			var anim_name: String = _resolve_anim_name(anim_entry["name"])
			if not animations.has(anim_name):
				continue

			var weight := 1.0
			if not anim_entry["condition"].is_empty():
				weight = molang.evaluate(anim_entry["condition"])
				if weight == 0.0:
					continue

			# Don't add duplicates
			var found := false
			for existing in _active_anims:
				if existing["name"] == anim_name:
					existing["weight"] = maxf(existing["weight"], weight)
					found = true
					break

			if not found:
				var anim: AnimData = animations[anim_name]
				_active_anims.append({
					"name": anim_name,
					"weight": weight,
					"time": _get_anim_time(anim),
					"loop": anim.loop,
					"length": anim.length,
					"override": anim.override_previous,
				})


func _get_anim_time(anim: AnimData) -> float:
	if not anim.anim_time_update.is_empty():
		return molang.evaluate(anim.anim_time_update)
	return 0.0  # Will be incremented by _update_anim_times


func _update_anim_times(dt: float) -> void:
	for entry in _active_anims:
		var anim_name: String = entry["name"]
		if animations.has(anim_name):
			var anim: AnimData = animations[anim_name]
			if anim.anim_time_update.is_empty():
				# Time-based animation
				entry["time"] += dt
				if entry["loop"] and entry["length"] > 0.0:
					entry["time"] = fmod(entry["time"], entry["length"])
				elif not entry["loop"] and entry["time"] >= entry["length"]:
					entry["time"] = entry["length"]
			else:
				# Custom time expression (e.g. distance-based)
				entry["time"] = molang.evaluate(anim.anim_time_update)


func _apply_animations_to_skeleton() -> void:
	if skeleton == null:
		return

	# Reset all bones to rest pose
	skeleton.reset_bone_poses()

	# Accumulated transforms per bone: bone_idx -> { rot: Vector3, pos: Vector3, scl: Vector3 }
	var accumulated: Dictionary = {}

	for entry in _active_anims:
		var anim_name: String = entry["name"]
		if not animations.has(anim_name):
			continue
		var anim: AnimData = animations[anim_name]
		var weight: float = entry["weight"]
		var anim_time: float = entry["time"]

		# Blend weight from expression
		if not anim.blend_weight_expr.is_empty():
			weight *= molang.evaluate(anim.blend_weight_expr)

		if weight <= 0.001:
			continue

		# Set anim_time in context
		molang.context["query.anim_time"] = anim_time

		# Evaluate each bone
		for bone_name in anim.bones:
			var bone_idx: int = _bone_map.get(bone_name, -1)
			if bone_idx < 0:
				continue

			var bone_anim: BoneAnimData = anim.bones[bone_name]

			if not accumulated.has(bone_idx):
				accumulated[bone_idx] = {
					"rot": Vector3.ZERO,
					"pos": Vector3.ZERO,
					"scl": Vector3.ONE,
					"has_rot": false,
					"has_pos": false,
					"has_scl": false,
				}

			var acc: Dictionary = accumulated[bone_idx]

			# Set 'this' values for the evaluator
			var current_rot := acc["rot"]
			var current_pos := acc["pos"]

			# Override previous = reset accumulated
			if anim.override_previous:
				current_rot = Vector3.ZERO
				current_pos = Vector3.ZERO
				acc["rot"] = Vector3.ZERO
				acc["pos"] = Vector3.ZERO
				acc["scl"] = Vector3.ONE

			# ─── Rotation ────────────────────────────────────────────
			if bone_anim.rotation != null:
				var rot := _evaluate_channel(bone_anim.rotation, anim_time, anim.length, current_rot)
				acc["rot"] += rot * weight
				acc["has_rot"] = true

			# ─── Position ────────────────────────────────────────────
			if bone_anim.position != null:
				var pos := _evaluate_channel(bone_anim.position, anim_time, anim.length, current_pos)
				acc["pos"] += pos * weight
				acc["has_pos"] = true

			# ─── Scale ───────────────────────────────────────────────
			if bone_anim.scale != null:
				var scl := _evaluate_scale_channel(bone_anim.scale, anim_time, anim.length)
				acc["scl"] = acc["scl"] * scl  # Multiply scales
				acc["has_scl"] = true

	# Apply accumulated transforms to skeleton
	for bone_idx in accumulated:
		var acc: Dictionary = accumulated[bone_idx]

		if acc["has_rot"]:
			var rot_deg: Vector3 = acc["rot"]
			# Bedrock +X=forward, +Y=left ; GLB/Godot +X=backward, +Y=right
			# → nier X et Y, garder Z
			var quat := _euler_deg_to_quat(-rot_deg.x, -rot_deg.y, rot_deg.z)
			skeleton.set_bone_pose_rotation(bone_idx, quat)

		if acc["has_pos"]:
			var pos: Vector3 = acc["pos"]
			# Bedrock position: 1/16th units
			var scale_factor := 1.0 / 16.0
			skeleton.set_bone_pose_position(bone_idx,
				Vector3(pos.x * scale_factor, pos.y * scale_factor, pos.z * scale_factor))

		if acc["has_scl"]:
			var scl: Vector3 = acc["scl"]
			skeleton.set_bone_pose_scale(bone_idx, scl)


# ─── Channel Evaluation ─────────────────────────────────────────────────────

## Évalue un canal d'animation (rotation ou position).
## Le canal peut être:
##   - Un tableau [x, y, z] (statique ou avec expressions)
##   - Un dict de keyframes { "0.0": [x,y,z], "0.5": [x,y,z], ... }
##   - Un nombre simple (uniform)
func _evaluate_channel(channel, anim_time: float, anim_length: float, current: Vector3) -> Vector3:
	if channel == null:
		return Vector3.ZERO

	# Simple number -> uniform
	if channel is float or channel is int:
		var v := float(channel)
		return Vector3(v, v, v)

	# Array [x, y, z] -> static or expression
	if channel is Array:
		return _eval_vec3_array(channel, current)

	# Dictionary -> keyframe timeline
	if channel is Dictionary:
		return _evaluate_keyframe_timeline(channel, anim_time, anim_length, current)

	# String -> single expression for all axes? Rare but handle it
	if channel is String:
		var v := molang.evaluate(channel, 0.0)
		return Vector3(v, v, v)

	return Vector3.ZERO


func _evaluate_scale_channel(channel, anim_time: float, anim_length: float) -> Vector3:
	if channel == null:
		return Vector3.ONE

	# Simple number -> uniform scale
	if channel is float or channel is int:
		var v := float(channel)
		return Vector3(v, v, v)

	# Array -> per-axis
	if channel is Array:
		return _eval_vec3_array(channel, Vector3.ONE)

	# Dictionary -> keyframes
	if channel is Dictionary:
		return _evaluate_keyframe_timeline(channel, anim_time, anim_length, Vector3.ONE)

	if channel is String:
		var v := molang.evaluate(channel)
		return Vector3(v, v, v)

	return Vector3.ONE


func _eval_vec3_array(arr: Array, current: Vector3) -> Vector3:
	var result := Vector3.ZERO
	for i in range(mini(arr.size(), 3)):
		var v = arr[i]
		if v is float or v is int:
			result[i] = float(v)
		elif v is String:
			molang.this_value = current[i]
			result[i] = molang.evaluate(v, current[i])
		elif v is Array:
			# Nested array? Take first element
			if not v.is_empty():
				if v[0] is float or v[0] is int:
					result[i] = float(v[0])
	return result


func _evaluate_keyframe_timeline(timeline: Dictionary, anim_time: float, anim_length: float, current: Vector3) -> Vector3:
	# Sort keyframe times
	var times: Array = []
	for key in timeline:
		times.append(float(key))
	times.sort()

	if times.is_empty():
		return Vector3.ZERO

	# Find surrounding keyframes
	var t := anim_time
	if t <= times[0]:
		return _eval_keyframe_value(timeline[str(times[0])], current, 0.0)
	if t >= times[times.size() - 1]:
		return _eval_keyframe_value(timeline[str(times[times.size() - 1])], current, 1.0)

	# Find the two surrounding keyframes
	var idx := 0
	for i in range(times.size() - 1):
		if t >= times[i] and t < times[i + 1]:
			idx = i
			break

	var t0: float = times[idx]
	var t1: float = times[idx + 1]
	var lerp_t := (t - t0) / (t1 - t0) if t1 > t0 else 0.0

	# Set key_frame_lerp_time for expressions
	molang.context["query.key_frame_lerp_time"] = lerp_t

	var key0_str := str(t0)
	var key1_str := str(t1)

	# Handle int keys (JSON might store "0" vs "0.0")
	if not timeline.has(key0_str):
		key0_str = str(int(t0)) if t0 == float(int(t0)) else key0_str
	if not timeline.has(key1_str):
		key1_str = str(int(t1)) if t1 == float(int(t1)) else key1_str

	var val0 = timeline.get(key0_str, timeline.get(str(int(t0)), [0, 0, 0]))
	var val1 = timeline.get(key1_str, timeline.get(str(int(t1)), [0, 0, 0]))

	# Get post value of key0 and pre value of key1
	var v0 := _get_keyframe_post(val0, current, lerp_t)
	var v1 := _get_keyframe_pre(val1, current, lerp_t)

	# Linear interpolation
	return v0.lerp(v1, lerp_t)


func _eval_keyframe_value(value, current: Vector3, lerp_t: float) -> Vector3:
	if value is Array:
		return _eval_vec3_array(value, current)
	if value is Dictionary:
		# Pre/post format
		if value.has("post"):
			molang.context["query.key_frame_lerp_time"] = lerp_t
			return _eval_vec3_array(value["post"], current)
		if value.has("pre"):
			return _eval_vec3_array(value["pre"], current)
	if value is float or value is int:
		var v := float(value)
		return Vector3(v, v, v)
	return Vector3.ZERO


func _get_keyframe_post(value, current: Vector3, lerp_t: float) -> Vector3:
	if value is Array:
		return _eval_vec3_array(value, current)
	if value is Dictionary:
		if value.has("post"):
			molang.context["query.key_frame_lerp_time"] = lerp_t
			return _eval_vec3_array(value["post"], current)
		# Fallback to pre
		if value.has("pre"):
			return _eval_vec3_array(value["pre"], current)
	if value is float or value is int:
		var v := float(value)
		return Vector3(v, v, v)
	return Vector3.ZERO


func _get_keyframe_pre(value, current: Vector3, lerp_t: float) -> Vector3:
	if value is Array:
		return _eval_vec3_array(value, current)
	if value is Dictionary:
		if value.has("pre"):
			molang.context["query.key_frame_lerp_time"] = lerp_t
			return _eval_vec3_array(value["pre"], current)
		if value.has("post"):
			return _eval_vec3_array(value["post"], current)
	if value is float or value is int:
		var v := float(value)
		return Vector3(v, v, v)
	return Vector3.ZERO


# ─── Euler → Quaternion ──────────────────────────────────────────────────────

## Bedrock euler (degrees, XYZ) → Godot Quaternion. Ordre ZYX intrinsèque.
func _euler_deg_to_quat(x_deg: float, y_deg: float, z_deg: float) -> Quaternion:
	var x := deg_to_rad(x_deg)
	var y := deg_to_rad(y_deg)
	var z := deg_to_rad(z_deg)
	var cx := cos(x * 0.5)
	var sx := sin(x * 0.5)
	var cy := cos(y * 0.5)
	var sy := sin(y * 0.5)
	var cz := cos(z * 0.5)
	var sz := sin(z * 0.5)
	return Quaternion(
		sx * cy * cz - cx * sy * sz,
		cx * sy * cz + sx * cy * sz,
		cx * cy * sz - sx * sy * cz,
		cx * cy * cz + sx * sy * sz
	)


# ─── Utilities ───────────────────────────────────────────────────────────────

func _detect_anim_length(anim: AnimData) -> float:
	var max_time := 0.0
	for bone_name in anim.bones:
		var bone_anim: BoneAnimData = anim.bones[bone_name]
		for channel in [bone_anim.rotation, bone_anim.position, bone_anim.scale]:
			if channel is Dictionary:
				for key in channel:
					var t := float(key)
					if t > max_time:
						max_time = t
	return max_time


## Retourne les noms de toutes les animations chargées.
func get_animation_list() -> Array[String]:
	var names: Array[String] = []
	for key in animations:
		names.append(key)
	return names


## Debug: affiche l'état actuel.
func get_debug_info() -> String:
	var info := "BedrockAnimPlayer v" + APP_VERSION + "\n"
	info += "Animations: " + str(animations.size()) + "\n"
	info += "Controllers: " + str(controllers.size()) + "\n"
	info += "Active anims: "
	for entry in _active_anims:
		info += entry["name"].get_file() + " (w=" + str(snapped(entry["weight"], 0.01)) + ") "
	info += "\nController states: "
	for ctrl in _controller_states:
		info += ctrl.get_file() + "=" + _controller_states[ctrl] + " "
	return info
