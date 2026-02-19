extends Node3D
class_name WorldManager

@export var render_distance: int = 4
@export var chunk_load_per_frame: int = 2
@export var unload_distance_margin: int = 3  # Marge pour éviter le clignotement

var chunks: Dictionary = {}
var player: CharacterBody3D
var last_player_chunk: Vector3i = Vector3i.ZERO  # Position précédente du joueur
var chunk_generator: ChunkGenerator
var world_seed: int = 0  # Seed du monde (0 = aléatoire)
var saved_chunk_data: Dictionary = {}  # Vector3i -> PackedByteArray (chunks modifiés à restaurer)

# Mobs passifs
var mobs: Array = []
const MAX_MOBS = 20

# PNJ villageois
const NpcVillagerScene = preload("res://scripts/npc_villager.gd")
var npcs: Array = []
const MAX_NPCS = 20

# POI Manager
var poi_manager: POIManager = null

func _ready():
	# Générer un seed aléatoire si non défini
	if world_seed == 0:
		randomize()
		world_seed = randi()

	# Créer le POI Manager
	poi_manager = POIManager.new()

	# Créer le générateur de chunks avec le seed du monde
	chunk_generator = ChunkGenerator.new()
	chunk_generator.set_world_seed(world_seed)
	add_child(chunk_generator)
	chunk_generator.chunk_generated.connect(_on_chunk_data_ready)

	# Charger les structures prédéfinies
	var struct_mgr = get_node_or_null("/root/StructureManager")
	if struct_mgr:
		var placements = struct_mgr.get_placement_data()
		if placements.size() > 0:
			chunk_generator.set_structure_placements(placements)
			print("WorldManager: %d structure(s) à placer" % placements.size())

	# Attendre que le joueur soit prêt
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	if player:
		last_player_chunk = _world_to_chunk(player.global_position)
		_update_chunks()

func _process(_delta):
	if player:
		var current_chunk = _world_to_chunk(player.global_position)

		# Ne mettre à jour que si le joueur a changé de chunk
		if current_chunk != last_player_chunk:
			last_player_chunk = current_chunk
			_update_chunks()

func _update_chunks():
	if not player:
		return
	
	var player_chunk_pos = _world_to_chunk(player.global_position)
	
	# Préparer la liste des chunks à charger
	var chunks_to_load = []
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var chunk_pos = Vector3i(player_chunk_pos.x + x, 0, player_chunk_pos.z + z)
			var distance = abs(x) + abs(z)
			
			if not chunks.has(chunk_pos) and not chunk_generator.is_generating(chunk_pos):
				chunks_to_load.append({"pos": chunk_pos, "distance": distance})
	
	# Trier par distance (les plus proches en premier)
	chunks_to_load.sort_custom(func(a, b): return a["distance"] < b["distance"])
	
	# Envoyer les chunks à générer (max 10 par update)
	var queued = 0
	for chunk_data in chunks_to_load:
		if queued >= 10:
			break
		chunk_generator.queue_chunk_generation(chunk_data["pos"], chunk_data["distance"])
		queued += 1
	
	# Décharger les chunks trop loin
	_unload_distant_chunks(player_chunk_pos)

func _on_chunk_data_ready(chunk_data: Dictionary):
	"""Appelé quand un chunk a été généré dans un thread"""
	var chunk_pos = chunk_data["position"]
	var blocks = chunk_data["blocks"]
	var p_y_min: int = chunk_data.get("y_min", 0)
	var p_y_max: int = chunk_data.get("y_max", Chunk.CHUNK_HEIGHT - 1)

	# Si un chunk existe déjà à cette position (race condition après load), le libérer
	if chunks.has(chunk_pos):
		var old_chunk = chunks[chunk_pos]
		old_chunk.queue_free()
		chunks.erase(chunk_pos)

	# Remplacer par les données sauvegardées si ce chunk a été modifié
	if saved_chunk_data.has(chunk_pos):
		blocks = saved_chunk_data[chunk_pos].duplicate()
		# Recalculer y_min/y_max pour les données restaurées
		p_y_min = Chunk.CHUNK_HEIGHT
		p_y_max = 0
		for bx in range(Chunk.CHUNK_SIZE):
			var x_off = bx * Chunk.CHUNK_SIZE * Chunk.CHUNK_HEIGHT
			for bz in range(Chunk.CHUNK_SIZE):
				var xz_off = x_off + bz * Chunk.CHUNK_HEIGHT
				for by in range(Chunk.CHUNK_HEIGHT):
					if blocks[xz_off + by] != 0:
						if by < p_y_min:
							p_y_min = by
						if by > p_y_max:
							p_y_max = by
		if p_y_min > p_y_max:
			p_y_min = 0
			p_y_max = 0

	# Créer le chunk avec les données générées
	var chunk = Chunk.new(chunk_pos, blocks, p_y_min, p_y_max)
	chunk.position = Vector3(chunk_pos.x * Chunk.CHUNK_SIZE, 0, chunk_pos.z * Chunk.CHUNK_SIZE)
	if saved_chunk_data.has(chunk_pos):
		chunk.is_modified = true
	add_child(chunk)
	chunks[chunk_pos] = chunk

	# Lancer la construction du mesh en arrière-plan (thread dédié)
	chunk.build_mesh_async()

	# Scanner le chunk pour les POI (workstations)
	if poi_manager:
		poi_manager.scan_chunk(chunk_pos, blocks)

	# Tenter de spawn des mobs passifs
	_try_spawn_mobs(chunk_pos, chunk_data)

	# Tenter de spawn des PNJ villageois
	_try_spawn_npcs(chunk_pos, chunk_data)

func _unload_distant_chunks(player_chunk_pos: Vector3i):
	var chunks_to_remove = []
	
	# Utiliser une plus grande distance pour le déchargement (hysteresis)
	var unload_distance = render_distance + unload_distance_margin
	
	for chunk_pos in chunks.keys():
		var distance = abs(chunk_pos.x - player_chunk_pos.x) + abs(chunk_pos.z - player_chunk_pos.z)
		if distance > unload_distance:
			chunks_to_remove.append(chunk_pos)
	
	for chunk_pos in chunks_to_remove:
		var chunk = chunks[chunk_pos]
		# Conserver les données des chunks modifiés pour les restaurer plus tard
		if chunk.is_modified:
			saved_chunk_data[chunk_pos] = chunk.blocks.duplicate()
		chunk.queue_free()
		chunks.erase(chunk_pos)

	# Supprimer les mobs des chunks déchargés
	var remaining_mobs = []
	for mob_data in mobs:
		if chunks_to_remove.has(mob_data["chunk_pos"]):
			if is_instance_valid(mob_data["mob"]):
				mob_data["mob"].queue_free()
		else:
			remaining_mobs.append(mob_data)
	mobs = remaining_mobs

	# Supprimer les NPCs des chunks déchargés + libérer leurs POI
	var remaining_npcs = []
	for npc_data in npcs:
		if chunks_to_remove.has(npc_data["chunk_pos"]):
			if is_instance_valid(npc_data["npc"]):
				var npc = npc_data["npc"]
				if poi_manager and npc.claimed_poi != Vector3i(-9999, -9999, -9999):
					poi_manager.release_poi(npc.claimed_poi)
				npc.queue_free()
		else:
			remaining_npcs.append(npc_data)
	npcs = remaining_npcs

	# Retirer les POI des chunks déchargés
	if poi_manager:
		for chunk_pos in chunks_to_remove:
			poi_manager.remove_chunk_pois(chunk_pos)

func _world_to_chunk(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_pos.x / Chunk.CHUNK_SIZE),
		0,
		floori(world_pos.z / Chunk.CHUNK_SIZE)
	)

func get_block_at_position(world_pos: Vector3) -> BlockRegistry.BlockType:
	var chunk_pos = _world_to_chunk(world_pos)
	var local_pos = Vector3i(
		int(world_pos.x) % Chunk.CHUNK_SIZE,
		int(world_pos.y),
		int(world_pos.z) % Chunk.CHUNK_SIZE
	)
	
	if local_pos.x < 0:
		local_pos.x += Chunk.CHUNK_SIZE
	if local_pos.z < 0:
		local_pos.z += Chunk.CHUNK_SIZE
	
	if chunks.has(chunk_pos):
		return chunks[chunk_pos].get_block(local_pos.x, local_pos.y, local_pos.z)
	
	return BlockRegistry.BlockType.AIR

func set_block_at_position(world_pos: Vector3, block_type: BlockRegistry.BlockType):
	var chunk_pos = _world_to_chunk(world_pos)
	var local_pos = Vector3i(
		int(world_pos.x) % Chunk.CHUNK_SIZE,
		int(world_pos.y),
		int(world_pos.z) % Chunk.CHUNK_SIZE
	)
	
	if local_pos.x < 0:
		local_pos.x += Chunk.CHUNK_SIZE
	if local_pos.z < 0:
		local_pos.z += Chunk.CHUNK_SIZE
	
	if chunks.has(chunk_pos):
		chunks[chunk_pos].set_block(local_pos.x, local_pos.y, local_pos.z, block_type)

func break_block_at_position(world_pos: Vector3):
	set_block_at_position(world_pos, BlockRegistry.BlockType.AIR)

func place_block_at_position(world_pos: Vector3, block_type: BlockRegistry.BlockType):
	set_block_at_position(world_pos, block_type)

# ============================================================
# MOBS PASSIFS
# ============================================================

func _try_spawn_mobs(chunk_pos: Vector3i, chunk_data: Dictionary):
	if mobs.size() >= MAX_MOBS:
		return

	# 10% de chance par chunk (déterministe via hash)
	var hash_val = abs((chunk_pos.x * 374761393 + chunk_pos.z * 668265263) >> 13) % 100
	if hash_val >= 10:
		return

	var packed_blocks = chunk_data["blocks"]
	var num_mobs = 1 + (hash_val % 2)

	for i in range(num_mobs):
		if mobs.size() >= MAX_MOBS:
			break

		var lx = ((hash_val + 1) * (i + 3) * 7) % 16
		var lz = ((hash_val + 1) * (i + 3) * 13) % 16

		# Trouver la surface (premier bloc non-AIR/non-WATER depuis le haut)
		var surface_y = -1
		var surface_block = 0
		for y in range(Chunk.CHUNK_HEIGHT - 1, 0, -1):
			var bt = packed_blocks[lx * 4096 + lz * 256 + y]
			if bt != 0 and bt != BlockRegistry.BlockType.WATER:
				surface_y = y + 1
				surface_block = bt
				break

		if surface_y < 0 or surface_y >= Chunk.CHUNK_HEIGHT - 2:
			continue

		# Seulement sur herbe ou sable
		var valid_blocks = [
			BlockRegistry.BlockType.GRASS,
			BlockRegistry.BlockType.DARK_GRASS,
			BlockRegistry.BlockType.SAND
		]
		if surface_block not in valid_blocks:
			continue

		# Choisir le type de mob
		var mob_type: PassiveMob.MobType
		if surface_block == BlockRegistry.BlockType.SAND:
			mob_type = PassiveMob.MobType.CHICKEN
		else:
			var type_hash = (hash_val + i * 31) % 3
			if type_hash == 0:
				mob_type = PassiveMob.MobType.SHEEP
			elif type_hash == 1:
				mob_type = PassiveMob.MobType.COW
			else:
				mob_type = PassiveMob.MobType.CHICKEN

		var world_x = chunk_pos.x * Chunk.CHUNK_SIZE + lx + 0.5
		var world_z = chunk_pos.z * Chunk.CHUNK_SIZE + lz + 0.5

		var mob = PassiveMob.new()
		mob.setup(mob_type, Vector3(world_x, surface_y, world_z), chunk_pos)
		get_parent().call_deferred("add_child", mob)
		mobs.append({"mob": mob, "chunk_pos": chunk_pos})

# ============================================================
# PNJ VILLAGEOIS
# ============================================================

func _try_spawn_npcs(chunk_pos: Vector3i, chunk_data: Dictionary):
	if npcs.size() >= MAX_NPCS:
		return

	# 5% de chance par chunk (hash avec offset pour éviter collision avec mobs)
	var hash_val = abs((chunk_pos.x * 374761393 + chunk_pos.z * 668265263 + 999983) >> 13) % 100
	if hash_val >= 5:
		return

	var packed_blocks = chunk_data["blocks"]

	var lx = ((hash_val + 1) * 11) % 16
	var lz = ((hash_val + 1) * 17) % 16

	# Trouver la surface
	var surface_y = -1
	var surface_block = 0
	for y in range(Chunk.CHUNK_HEIGHT - 1, 0, -1):
		var bt = packed_blocks[lx * 4096 + lz * 256 + y]
		if bt != 0 and bt != BlockRegistry.BlockType.WATER:
			surface_y = y + 1
			surface_block = bt
			break

	if surface_y < 0 or surface_y >= Chunk.CHUNK_HEIGHT - 2:
		return

	# Seulement sur herbe (pas sable)
	var valid_blocks = [
		BlockRegistry.BlockType.GRASS,
		BlockRegistry.BlockType.DARK_GRASS,
	]
	if surface_block not in valid_blocks:
		return

	# Assigner une profession déterministe via hash
	var prof = (hash_val * 7 + 3) % 9  # 0-8, réparti sur les 9 valeurs de Profession
	var model_index = VillagerProfession.get_model_for_profession(prof, hash_val)

	var world_x = chunk_pos.x * Chunk.CHUNK_SIZE + lx + 0.5
	var world_z = chunk_pos.z * Chunk.CHUNK_SIZE + lz + 0.5
	var spawn_pos = Vector3(world_x, surface_y, world_z)

	var npc = NpcVillagerScene.new()
	npc.setup(model_index, spawn_pos, chunk_pos, prof)
	if poi_manager:
		npc.poi_manager = poi_manager
	get_parent().call_deferred("add_child", npc)
	npcs.append({"npc": npc, "chunk_pos": chunk_pos})
