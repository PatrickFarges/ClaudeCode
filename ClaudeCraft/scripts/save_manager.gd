extends Node

# Gestionnaire de sauvegarde/chargement du monde
# Structure : user://saves/World1/world.json + chunks/chunk_X_Z.dat

const SAVE_VERSION = 1
const AUTOSAVE_INTERVAL = 300.0  # 5 minutes
const CHUNK_DATA_SIZE = 16 * 16 * 256  # CHUNK_SIZE * CHUNK_SIZE * CHUNK_HEIGHT

var world_manager: WorldManager = null
var player: CharacterBody3D = null
var day_night_cycle: Node = null
var autosave_timer: float = 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("save_manager")
	await get_tree().process_frame
	world_manager = get_tree().get_first_node_in_group("world_manager")
	player = get_tree().get_first_node_in_group("player")
	var dnc_nodes = get_tree().get_nodes_in_group("day_night_cycle")
	if dnc_nodes.size() > 0:
		day_night_cycle = dnc_nodes[0]

func _process(delta):
	autosave_timer += delta
	if autosave_timer >= AUTOSAVE_INTERVAL:
		autosave_timer = 0.0
		save_world("World1")

# ============================================================
# SAUVEGARDE
# ============================================================

func save_world(world_name: String) -> bool:
	if not world_manager or not player:
		return false

	var save_dir = "user://saves/" + world_name
	var chunks_dir = save_dir + "/chunks"

	# Creer les dossiers
	DirAccess.make_dir_recursive_absolute(chunks_dir)

	# Nettoyer les anciens fichiers .dat (eviter les reliquats d'un seed different)
	var old_dir = DirAccess.open(chunks_dir)
	if old_dir:
		old_dir.list_dir_begin()
		var old_fname = old_dir.get_next()
		while old_fname != "":
			if old_fname.ends_with(".dat"):
				old_dir.remove(old_fname)
			old_fname = old_dir.get_next()
		old_dir.list_dir_end()

	# Construire les donnees JSON
	var data = {
		"version": SAVE_VERSION,
		"world_seed": world_manager.world_seed,
		"time": day_night_cycle.get_current_time() if day_night_cycle else 0.3,
		"player": _serialize_player(),
	}

	# Ecrire world.json
	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open(save_dir + "/world.json", FileAccess.WRITE)
	if not file:
		return false
	file.store_string(json_str)
	file.close()

	# Sauvegarder les chunks modifies
	var saved_count = 0
	for chunk_pos in world_manager.chunks:
		var chunk = world_manager.chunks[chunk_pos]
		if chunk.is_modified:
			if _save_chunk(chunks_dir, chunk_pos, chunk.blocks):
				saved_count += 1

	# Sauvegarder aussi les chunks deja dans saved_chunk_data (dechargees mais modifiees)
	for chunk_pos in world_manager.saved_chunk_data:
		if not world_manager.chunks.has(chunk_pos):
			var blocks_data = world_manager.saved_chunk_data[chunk_pos]
			if _save_chunk_raw(chunks_dir, chunk_pos, blocks_data):
				saved_count += 1

	print("[SaveManager] Sauvegarde terminee : ", saved_count, " chunks modifies")
	return true

func _serialize_player() -> Dictionary:
	var inv = {}
	for key in player.inventory:
		if player.inventory[key] > 0:
			inv[str(int(key))] = player.inventory[key]

	var slots = []
	for s in player.hotbar_slots:
		slots.append(int(s))

	return {
		"position": {"x": player.global_position.x, "y": player.global_position.y, "z": player.global_position.z},
		"rotation_y": player.rotation.y,
		"camera_rotation_x": player.camera.rotation.x if player.camera else 0.0,
		"health": player.current_health,
		"inventory": inv,
		"hotbar_slots": slots,
		"selected_slot": player.selected_slot,
	}

func _save_chunk(chunks_dir: String, chunk_pos: Vector3i, blocks: PackedByteArray) -> bool:
	var filename = chunks_dir + "/chunk_%d_%d.dat" % [chunk_pos.x, chunk_pos.z]
	var compressed = blocks.compress(FileAccess.COMPRESSION_GZIP)
	var file = FileAccess.open(filename, FileAccess.WRITE)
	if not file:
		return false
	file.store_32(compressed.size())
	file.store_buffer(compressed)
	file.close()
	return true

func _save_chunk_raw(chunks_dir: String, chunk_pos: Vector3i, blocks: PackedByteArray) -> bool:
	return _save_chunk(chunks_dir, chunk_pos, blocks)

# ============================================================
# CHARGEMENT
# ============================================================

func load_world(world_name: String) -> bool:
	var save_dir = "user://saves/" + world_name
	var json_path = save_dir + "/world.json"

	if not FileAccess.file_exists(json_path):
		return false

	# Lire world.json
	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return false
	var json_str = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_str) != OK:
		return false
	var data = json.data

	# Vider le monde actuel
	_clear_world()

	# Restaurer le seed
	var seed_val = int(data.get("world_seed", 0))
	world_manager.world_seed = seed_val
	world_manager.chunk_generator.set_world_seed(seed_val)

	# Charger les chunks sauvegardes dans saved_chunk_data
	world_manager.saved_chunk_data.clear()
	var chunks_dir = save_dir + "/chunks"
	if DirAccess.dir_exists_absolute(chunks_dir):
		var dir = DirAccess.open(chunks_dir)
		if dir:
			dir.list_dir_begin()
			var fname = dir.get_next()
			while fname != "":
				if fname.ends_with(".dat") and fname.begins_with("chunk_"):
					var loaded = _load_chunk_file(chunks_dir + "/" + fname, fname)
					if loaded:
						world_manager.saved_chunk_data[loaded["pos"]] = loaded["blocks"]
				fname = dir.get_next()
			dir.list_dir_end()

	# Restaurer le joueur
	if data.has("player"):
		_restore_player(data["player"])

	# Restaurer le temps
	if day_night_cycle and data.has("time"):
		day_night_cycle.set_time(float(data["time"]))

	# Forcer la regeneration des chunks autour du joueur
	world_manager.last_player_chunk = Vector3i(-9999, 0, -9999)
	world_manager._update_chunks()

	print("[SaveManager] Chargement termine : ", world_manager.saved_chunk_data.size(), " chunks modifies restaures")
	return true

func _clear_world():
	# Vider la queue de generation
	world_manager.chunk_generator.clear_queue()

	# Supprimer tous les chunks
	for chunk_pos in world_manager.chunks.keys():
		var chunk = world_manager.chunks[chunk_pos]
		chunk.queue_free()
	world_manager.chunks.clear()

	# Supprimer les mobs
	for mob_data in world_manager.mobs:
		if is_instance_valid(mob_data["mob"]):
			mob_data["mob"].queue_free()
	world_manager.mobs.clear()

func _load_chunk_file(filepath: String, fname: String) -> Variant:
	# Extraire X et Z du nom : chunk_X_Z.dat
	var base = fname.replace("chunk_", "").replace(".dat", "")
	var parts = base.split("_")
	if parts.size() != 2:
		return null

	var cx = int(parts[0])
	var cz = int(parts[1])

	var file = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		return null

	var compressed_size = file.get_32()
	var compressed_data = file.get_buffer(compressed_size)
	file.close()

	var blocks = compressed_data.decompress(CHUNK_DATA_SIZE, FileAccess.COMPRESSION_GZIP)
	if blocks.size() != CHUNK_DATA_SIZE:
		return null

	return {"pos": Vector3i(cx, 0, cz), "blocks": blocks}

func _restore_player(pdata: Dictionary):
	if not player:
		return

	# Position
	if pdata.has("position"):
		var pos = pdata["position"]
		player.global_position = Vector3(float(pos["x"]), float(pos["y"]), float(pos["z"]))

	# Rotation
	if pdata.has("rotation_y"):
		player.rotation.y = float(pdata["rotation_y"])
	if pdata.has("camera_rotation_x") and player.camera:
		player.camera.rotation.x = float(pdata["camera_rotation_x"])

	# Sante
	if pdata.has("health"):
		player.current_health = int(pdata["health"])

	# Inventaire
	if pdata.has("inventory"):
		# Reset inventaire
		for key in player.inventory:
			player.inventory[key] = 0
		# Restaurer
		var inv = pdata["inventory"]
		for key_str in inv:
			var bt = int(key_str)
			player.inventory[bt] = int(inv[key_str])

	# Hotbar
	if pdata.has("hotbar_slots"):
		var slots = pdata["hotbar_slots"]
		for i in range(mini(slots.size(), player.hotbar_slots.size())):
			player.hotbar_slots[i] = int(slots[i])

	# Slot selectionne
	if pdata.has("selected_slot"):
		player.selected_slot = int(pdata["selected_slot"])
		player._update_selected_block()

	# Reset etats
	player.velocity = Vector3.ZERO
	player._was_on_floor = true
	player.is_dead = false

func has_save(world_name: String) -> bool:
	return FileAccess.file_exists("user://saves/" + world_name + "/world.json")
