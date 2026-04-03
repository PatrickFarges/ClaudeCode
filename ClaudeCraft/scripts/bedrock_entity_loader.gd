## BedrockEntityLoader v1.0.0
## Charge les entity definitions Bedrock et configure un BedrockAnimPlayer.
## Lit les fichiers JSON d'entité, résout les aliases animation/controller,
## charge automatiquement les fichiers nécessaires.
##
## Usage:
##   var loader = BedrockEntityLoader.new()
##   loader.configure_entity(bap, "skeleton")  # ou "zombie", "cow", etc.
##
## Changelog:
## v1.0.0 - Implémentation initiale

class_name BedrockEntityLoader

const APP_VERSION := "1.0.0"

# Paths de base (relatifs à res://)
const ANIM_DIR := "res://data/animations/"
const CTRL_DIR := "res://data/animation_controllers/"
const ENTITY_DIR := "res://data/entity_definitions/"

# Cache des entity definitions chargées
static var _entity_cache: Dictionary = {}

# Mapping entity_id → animation file prefix
# La plupart des entités utilisent des fichiers nommés <entity>.animation.json
# Mais certaines partagent des fichiers (humanoid, etc.)
static var _anim_file_map: Dictionary = {}  # animation_name → file loaded from


## Configure un BedrockAnimPlayer pour une entité donnée.
## entity_id : "skeleton", "zombie", "cow", "player", etc.
static func configure_entity(bap: BedrockAnimPlayer, entity_id: String) -> bool:
	var entity_def := _load_entity_def(entity_id)
	if entity_def.is_empty():
		# Fallback: essayer de charger directement les fichiers d'animation de l'entité
		return _configure_fallback(bap, entity_id)

	var desc: Dictionary = entity_def.get("minecraft:client_entity", {}).get("description", {})
	if desc.is_empty():
		return _configure_fallback(bap, entity_id)

	# 1. Pre-animation scripts
	var scripts: Dictionary = desc.get("scripts", {})
	var pre_anims: Array = scripts.get("pre_animation", [])
	for script_expr in pre_anims:
		if script_expr is String and not script_expr.is_empty():
			bap.pre_animation_scripts.append(script_expr)

	# 2. Animation aliases et chargement des fichiers
	var anim_map: Dictionary = desc.get("animations", {})
	var files_loaded: Dictionary = {}  # Track which files we've loaded

	for short_name in anim_map:
		var full_name: String = anim_map[short_name]
		bap.set_alias(short_name, full_name)

		# Determine which file to load based on animation name
		var file := _guess_anim_file(full_name)
		if not file.is_empty() and not files_loaded.has(file):
			var path := ANIM_DIR + file
			if FileAccess.file_exists(path):
				bap.load_animations(path)
				files_loaded[file] = true

	# 3. Animation controllers
	var ctrl_list: Array = desc.get("animation_controllers", [])
	var ctrl_files_loaded: Dictionary = {}

	for ctrl_entry in ctrl_list:
		if ctrl_entry is Dictionary:
			for short_name in ctrl_entry:
				var ctrl_full: String = ctrl_entry[short_name]
				var ctrl_file := _guess_ctrl_file(ctrl_full)
				if not ctrl_file.is_empty() and not ctrl_files_loaded.has(ctrl_file):
					var path := CTRL_DIR + ctrl_file
					if FileAccess.file_exists(path):
						bap.load_controllers(path)
						ctrl_files_loaded[ctrl_file] = true
				# Activate the controller
				bap.activate_controller(ctrl_full)

	return true


## Configure un BedrockAnimPlayer en mode fallback (pas d'entity definition).
## Charge les fichiers d'animation correspondant à l'entity_id.
static func _configure_fallback(bap: BedrockAnimPlayer, entity_id: String) -> bool:
	var loaded := false

	# Try entity-specific animation file
	var anim_file := entity_id + ".animation.json"
	var anim_path := ANIM_DIR + anim_file
	if FileAccess.file_exists(anim_path):
		bap.load_animations(anim_path)
		loaded = true

	# Also load humanoid animations (shared by many mobs)
	var humanoid_path := ANIM_DIR + "humanoid.animation.json"
	if FileAccess.file_exists(humanoid_path):
		bap.load_animations(humanoid_path)
		loaded = true

	# Load humanoid controller
	var ctrl_path := CTRL_DIR + "humanoid.animation_controllers.json"
	if FileAccess.file_exists(ctrl_path):
		bap.load_controllers(ctrl_path)

	# Default pre_animation for humanoids
	bap.pre_animation_scripts.append(
		"variable.tcos0 = (math.cos(query.modified_distance_moved * 38.17) * query.modified_move_speed / variable.gliding_speed_value) * 57.3;"
	)

	return loaded


## Charge et cache une entity definition.
static func _load_entity_def(entity_id: String) -> Dictionary:
	if _entity_cache.has(entity_id):
		return _entity_cache[entity_id]

	var path := ENTITY_DIR + entity_id + ".entity.json"
	if not FileAccess.file_exists(path):
		_entity_cache[entity_id] = {}
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		_entity_cache[entity_id] = {}
		return {}

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		_entity_cache[entity_id] = {}
		return {}

	_entity_cache[entity_id] = json.data
	return json.data


## Devine le fichier d'animation à charger depuis le nom complet de l'animation.
## Ex: "animation.humanoid.move" → "humanoid.animation.json"
##     "animation.skeleton.attack" → "skeleton.animation.json"
##     "animation.player.first_person" → "player.animation.json"
static func _guess_anim_file(anim_name: String) -> String:
	# animation.ENTITY.action_name
	var parts := anim_name.split(".")
	if parts.size() >= 3 and parts[0] == "animation":
		var entity := parts[1]
		# Some animation names use compound entities
		var fname := entity + ".animation.json"
		if FileAccess.file_exists(ANIM_DIR + fname):
			return fname
		# Try with more parts
		if parts.size() >= 4:
			var compound := entity + "_" + parts[2]
			fname = compound + ".animation.json"
			if FileAccess.file_exists(ANIM_DIR + fname):
				return fname
	return ""


## Devine le fichier de controller à charger.
## Ex: "controller.animation.humanoid.move" → "humanoid.animation_controllers.json"
static func _guess_ctrl_file(ctrl_name: String) -> String:
	# controller.animation.ENTITY.behavior
	var parts := ctrl_name.split(".")
	if parts.size() >= 4 and parts[0] == "controller" and parts[1] == "animation":
		var entity := parts[2]
		var fname := entity + ".animation_controllers.json"
		if FileAccess.file_exists(CTRL_DIR + fname):
			return fname
	return ""


## Retourne la liste de toutes les entités disponibles.
static func get_available_entities() -> Array[String]:
	var entities: Array[String] = []
	var dir := DirAccess.open(ENTITY_DIR)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while not fname.is_empty():
			if fname.ends_with(".entity.json"):
				entities.append(fname.replace(".entity.json", ""))
			fname = dir.get_next()
	entities.sort()
	return entities


## Retourne la liste de toutes les animations disponibles.
static func get_available_animations() -> Array[String]:
	var anims: Array[String] = []
	var dir := DirAccess.open(ANIM_DIR)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while not fname.is_empty():
			if fname.ends_with(".animation.json"):
				anims.append(fname.replace(".animation.json", ""))
			fname = dir.get_next()
	anims.sort()
	return anims
