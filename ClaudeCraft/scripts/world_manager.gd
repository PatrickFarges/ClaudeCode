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
var open_doors: Dictionary = {}  # Vector3i -> true (positions des portes ouvertes)
# Métadonnées porte : facing (0=N, 1=S, 2=E, 3=W), hinge ("left"/"right")
var door_data: Dictionary = {}  # Vector3i -> { "facing": int, "hinge": String }
var pane_orientation: Dictionary = {}  # Vector3i -> int (0=N-S along Z, 1=E-W along X)

func _toggle_door_key(key: Vector3i):
	if open_doors.has(key):
		open_doors.erase(key)
	else:
		open_doors[key] = true

func _is_door_block(pos: Vector3i) -> bool:
	var bt = get_block_at_position(Vector3(pos.x, pos.y, pos.z))
	return bt == BlockRegistry.BlockType.OAK_DOOR or bt == BlockRegistry.BlockType.IRON_DOOR

func _get_door_partner(key: Vector3i) -> Vector3i:
	# Retourne le second bloc de la porte (haut ou bas)
	var above = key + Vector3i(0, 1, 0)
	var below = key + Vector3i(0, -1, 0)
	if _is_door_block(above):
		return above
	elif _is_door_block(below):
		return below
	return key

func _get_door_bottom(key: Vector3i) -> Vector3i:
	var below = key + Vector3i(0, -1, 0)
	if _is_door_block(below):
		return below
	return key

func get_door_facing(wx: int, wy: int, wz: int) -> int:
	var key = Vector3i(wx, wy, wz)
	# Chercher les data sur ce bloc ou son partenaire
	if door_data.has(key):
		return door_data[key]["facing"]
	var bottom = _get_door_bottom(key)
	if door_data.has(bottom):
		return door_data[bottom]["facing"]
	return 0

func get_door_hinge(wx: int, wy: int, wz: int) -> String:
	var key = Vector3i(wx, wy, wz)
	if door_data.has(key):
		return door_data[key]["hinge"]
	var bottom = _get_door_bottom(key)
	if door_data.has(bottom):
		return door_data[bottom]["hinge"]
	return "left"

func place_door(world_pos: Vector3, block_type: BlockRegistry.BlockType, facing: int, hinge: String = "left"):
	var key = Vector3i(int(floor(world_pos.x)), int(floor(world_pos.y)), int(floor(world_pos.z)))
	var above = key + Vector3i(0, 1, 0)
	set_block_at_position(world_pos, block_type)
	set_block_at_position(Vector3(above.x, above.y, above.z), block_type)
	door_data[key] = { "facing": facing, "hinge": hinge }

func remove_door(world_pos: Vector3) -> BlockRegistry.BlockType:
	var key = Vector3i(int(floor(world_pos.x)), int(floor(world_pos.y)), int(floor(world_pos.z)))
	var partner = _get_door_partner(key)
	var bottom = _get_door_bottom(key)
	var bt = get_block_at_position(Vector3(key.x, key.y, key.z))
	# Supprimer les deux blocs
	set_block_at_position(Vector3(key.x, key.y, key.z), BlockRegistry.BlockType.AIR)
	if partner != key:
		set_block_at_position(Vector3(partner.x, partner.y, partner.z), BlockRegistry.BlockType.AIR)
	# Nettoyer les données
	open_doors.erase(key)
	open_doors.erase(partner)
	door_data.erase(bottom)
	return bt

func _find_adjacent_door(key: Vector3i, facing: int) -> Vector3i:
	# Cherche une porte adjacente (même facing) pour double porte
	var offsets: Array
	if facing == 0 or facing == 1:  # N/S → chercher à gauche/droite sur X
		offsets = [Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
	else:  # E/W → chercher à gauche/droite sur Z
		offsets = [Vector3i(0, 0, -1), Vector3i(0, 0, 1)]
	for off in offsets:
		var adj = key + off
		if _is_door_block(adj):
			var adj_bottom = _get_door_bottom(adj)
			if door_data.has(adj_bottom) and door_data[adj_bottom]["facing"] == facing:
				return adj
	return Vector3i(-9999, -9999, -9999)

func toggle_door_pair(world_pos: Vector3):
	var key = Vector3i(int(floor(world_pos.x)), int(floor(world_pos.y)), int(floor(world_pos.z)))
	var bottom = _get_door_bottom(key)
	var partner = _get_door_partner(key)
	# Toggle les deux blocs de cette porte
	_toggle_door_key(key)
	if partner != key:
		_toggle_door_key(partner)
	# Chercher une double porte adjacente et la toggler aussi
	var facing = get_door_facing(key.x, key.y, key.z)
	var adj = _find_adjacent_door(bottom, facing)
	if adj.x != -9999:
		var adj_partner = _get_door_partner(adj)
		_toggle_door_key(adj)
		if adj_partner != adj:
			_toggle_door_key(adj_partner)
		# Rebuild chunk de la porte adjacente si différent
		var adj_chunk = _world_to_chunk(Vector3(adj.x, adj.y, adj.z))
		var my_chunk = _world_to_chunk(world_pos)
		if adj_chunk != my_chunk and chunks.has(adj_chunk):
			chunks[adj_chunk]._rebuild_mesh()
	# Un seul rebuild
	var chunk_pos = _world_to_chunk(world_pos)
	if chunks.has(chunk_pos):
		chunks[chunk_pos]._rebuild_mesh()

func rebuild_chunk_at(world_pos: Vector3):
	var chunk_pos = _world_to_chunk(world_pos)
	if chunks.has(chunk_pos):
		chunks[chunk_pos]._rebuild_mesh()

func is_door_open(wx: int, wy: int, wz: int) -> bool:
	return open_doors.has(Vector3i(wx, wy, wz))

# PNJ villageois
const NpcVillagerScene = preload("res://scripts/npc_villager.gd")
const VProfession = preload("res://scripts/villager_profession.gd")
const POIManagerScript = preload("res://scripts/poi_manager.gd")
var npcs: Array = []
const MAX_NPCS = 20

# POI Manager
var poi_manager = null

# Village
var _village_spawned: bool = false
const VILLAGE_NPC_COUNT = 0  # Inhibé — remettre à 9 pour mode Settlers

# ── Mobs ──
var mobs: Array = []
const MAX_MOBS = 60
const MOBS_PER_CHUNK_PASSIVE = 2  # max passive mobs spawned per chunk
const MOBS_PER_CHUNK_HOSTILE = 1  # max hostile mobs spawned per chunk
const MOB_SPAWN_MIN_DIST = 24.0   # min distance from player to spawn
const MOB_SPAWN_MAX_DIST = 64.0   # max distance from player to spawn
var _mob_spawn_timer: float = 0.0
const MOB_SPAWN_INTERVAL = 3.0    # check spawn/respawn every 3s
var _spawned_chunks: Dictionary = {}  # chunk_pos -> true (already spawned passive)
var _pending_mob_chunks: Array = []   # [Vector3i] — chunk positions waiting for mesh
var _pending_chunk_data: Array = []   # Buffer de chunks générés en attente d'instanciation
const MAX_CHUNK_INSTANTIATE_PER_FRAME: int = 2
const COLLISION_DISTANCE: int = 3     # Chunks à ≤3 Manhattan = collision active
const COLLISION_REMOVE_DISTANCE: int = 5  # Au-delà = collision retirée
var _mob_glbs_preloaded: bool = false

func _ready():
	# Générer un seed aléatoire si non défini
	if world_seed == 0:
		randomize()
		world_seed = randi()

	# Créer le POI Manager
	poi_manager = POIManagerScript.new()

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
			#print("WorldManager: %d structure(s) à placer" % placements.size())

	# Attendre que le joueur soit prêt
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	if player:
		# Phase 1 : trouver les coordonnees XZ terrestres (noise, instantane)
		_find_land_spawn_xz()
		# Mettre le joueur en hauteur et invisible pendant le chargement
		player.global_position.y = 200.0
		player.set_physics_process(false)
		player.visible = false
		_spawn_pending = true
		last_player_chunk = _world_to_chunk(player.global_position)
		_update_chunks()

# === SPAWN ROBUSTE ===
var _spawn_pending: bool = false
var _spawn_enable_timer: int = 0  # frames avant de reactiver le joueur

func _find_land_spawn_xz():
	"""Phase 1 : trouver des coordonnees XZ sur terre ferme via noise (instantane)."""
	if not chunk_generator or not player:
		return
	var px = int(player.global_position.x)
	var pz = int(player.global_position.z)
	var start_biome = chunk_generator.get_biome_at(px, pz)
	if start_biome <= 3:
		#print("WorldManager: spawn XZ OK (%d, %d) biome=%d" % [px, pz, start_biome])
		return
	# Chercher la terre la plus proche en spirale
	#print("WorldManager: spawn en eau (biome %d), recherche spirale..." % start_biome)
	for radius in range(1, 500):
		var steps = maxi(radius * 8, 8)
		for step in range(steps):
			var angle = step * TAU / steps
			var wx = px + int(cos(angle) * radius * 8)
			var wz = pz + int(sin(angle) * radius * 8)
			if chunk_generator.get_biome_at(wx, wz) <= 3:
				player.global_position.x = wx
				player.global_position.z = wz
				#print("WorldManager: terre trouvee a (%d, %d) rayon=%d" % [wx, wz, radius])
				return
	#print("WorldManager: pas de terre trouvee, spawn par defaut")

func _finalize_spawn():
	"""Phase 2 : une fois le chunk genere, scanner les blocs reels pour trouver le sol."""
	var spawn_chunk = _world_to_chunk(player.global_position)
	if not chunks.has(spawn_chunk):
		return  # Chunk pas encore pret, on reessaie au prochain frame
	var chunk = chunks[spawn_chunk]
	if not chunk.is_mesh_built:
		return  # Mesh pas encore construit
	# Scanner du haut vers le bas pour trouver le sol solide
	var lx = int(player.global_position.x) - spawn_chunk.x * Chunk.CHUNK_SIZE
	var lz = int(player.global_position.z) - spawn_chunk.z * Chunk.CHUNK_SIZE
	lx = clampi(lx, 1, Chunk.CHUNK_SIZE - 2)
	lz = clampi(lz, 1, Chunk.CHUNK_SIZE - 2)
	var offset = lx * Chunk.CHUNK_SIZE * Chunk.CHUNK_HEIGHT + lz * Chunk.CHUNK_HEIGHT
	for y in range(Chunk.CHUNK_HEIGHT - 1, 0, -1):
		var bt = chunk.blocks[offset + y]
		if bt == 0 or bt == BlockRegistry.BlockType.WATER:
			continue
		# Ignorer feuilles, troncs, vegetation, torches
		if bt == BlockRegistry.BlockType.LEAVES or bt == BlockRegistry.BlockType.WOOD:
			continue
		if bt >= BlockRegistry.BlockType.SPRUCE_LOG and bt <= BlockRegistry.BlockType.CHERRY_LEAVES:
			continue
		if bt >= 98 and bt <= 103:  # Cross-mesh vegetation
			continue
		if bt == BlockRegistry.BlockType.TORCH or bt == BlockRegistry.BlockType.LANTERN:
			continue
		# Sol solide trouve — spawn 3 blocs au-dessus + attendre collision
		var spawn_y = y + 3
		player.global_position.y = spawn_y
		player.velocity = Vector3.ZERO
		player.spawn_position = player.global_position
		_spawn_pending = false
		_spawn_enable_timer = 10  # attendre 10 frames pour la collision
		#print("WorldManager: SPAWN FINAL a (%d, %d, %d) bloc=%d" % [
		#	int(player.global_position.x), spawn_y, int(player.global_position.z), bt])
		return
	# Aucun sol trouve — fallback haut
	player.global_position.y = 120
	player.velocity = Vector3.ZERO
	player.spawn_position = player.global_position
	_spawn_pending = false
	_spawn_enable_timer = 10
	#print("WorldManager: SPAWN fallback Y=120 (pas de sol dans le chunk)")

func _process(_delta):
	# Instancier les chunks en attente (max 2/frame)
	if _pending_chunk_data.size() > 0:
		_process_pending_chunks()

	# Spawn en attente — verifier si le chunk est pret
	if _spawn_pending:
		_finalize_spawn()

	# Attendre que la collision soit creee avant d'activer le joueur
	if _spawn_enable_timer > 0:
		_spawn_enable_timer -= 1
		if _spawn_enable_timer == 0 and player:
			player.set_physics_process(true)
			player.visible = true
			#print("WorldManager: joueur active (collision prete)")

	# Collision différée : créer/supprimer selon distance joueur (1/frame)
	if player:
		_update_chunk_collisions()

	if player:
		var current_chunk = _world_to_chunk(player.global_position)

		# Ne mettre à jour que si le joueur a changé de chunk
		if current_chunk != last_player_chunk:
			last_player_chunk = current_chunk
			_update_chunks()

		# Mob spawning timer (hostile at night + passive respawn)
		_mob_spawn_timer += _delta
		if _mob_spawn_timer >= MOB_SPAWN_INTERVAL:
			_mob_spawn_timer = 0.0
			_try_spawn_mobs()
			_try_respawn_passive_mobs()

		# Preload mob GLBs once (after first chunks are loaded, avoid startup freeze)
		if not _mob_glbs_preloaded and chunks.size() >= 4:
			_mob_glbs_preloaded = true
			_preload_mob_glbs()

		# Deferred passive mob spawning — wait for chunk mesh to be built AND db loaded
		if _mob_glbs_preloaded and not _pending_mob_chunks.is_empty():
			_process_pending_mob_spawns()

func _update_chunk_collisions():
	var player_chunk = _world_to_chunk(player.global_position)
	# Priorité absolue : chunk du joueur + 4 voisins directs (jamais throttlé)
	for offset in [Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
		var cp = player_chunk + offset
		if chunks.has(cp):
			var c = chunks[cp]
			if c.is_mesh_built and not c.has_collision:
				c.create_collision()
	# Reste : 1 collision par frame max
	var created_this_frame = 0
	for chunk_pos in chunks:
		var chunk = chunks[chunk_pos]
		if not chunk.is_mesh_built:
			continue
		var dist = abs(chunk_pos.x - player_chunk.x) + abs(chunk_pos.z - player_chunk.z)
		if dist <= COLLISION_DISTANCE and dist > 1 and not chunk.has_collision:
			chunk.create_collision()
			created_this_frame += 1
			if created_this_frame >= 1:
				return  # Max 1 collision créée par frame pour les chunks lointains
		elif dist > COLLISION_REMOVE_DISTANCE and chunk.has_collision:
			chunk.remove_collision()

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
	"""Appelé quand un chunk a été généré dans un thread — bufferisé"""
	_pending_chunk_data.append(chunk_data)

func _process_pending_chunks():
	"""Instancie max 2 chunks par frame depuis le buffer"""
	var processed = 0
	while processed < MAX_CHUNK_INSTANTIATE_PER_FRAME and _pending_chunk_data.size() > 0:
		var chunk_data = _pending_chunk_data.pop_front()
		_instantiate_chunk(chunk_data)
		processed += 1

func _instantiate_chunk(chunk_data: Dictionary):
	var _t0 = Time.get_ticks_msec()
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

	# Scanner le chunk pour les POI (workstations) — limité au range y utile
	if poi_manager:
		poi_manager.scan_chunk(chunk_pos, blocks, p_y_min, p_y_max)

	# Tenter de spawn le village (une seule fois, près du joueur)
	if not _village_spawned and player:
		_try_spawn_village(chunk_pos, chunk_data)

	# Queue mob spawn — will execute once the chunk mesh+collision is built
	if not _spawned_chunks.has(chunk_pos):
		_spawned_chunks[chunk_pos] = true
		_pending_mob_chunks.append(chunk_pos)

	var _t_inst = Time.get_ticks_msec() - _t0
	if _t_inst > 5:
		#print("[WorldManager] instantiate chunk %s: %dms" % [str(chunk_pos), _t_inst])
		pass

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
		# Plafonner à 100 chunks sauvegardés pour éviter le bloat mémoire
		if chunk.is_modified and saved_chunk_data.size() < 100:
			saved_chunk_data[chunk_pos] = chunk.blocks.duplicate()
		chunk.queue_free()
		chunks.erase(chunk_pos)

	# Set pour lookup O(1) au lieu de Array.has() O(n)
	var remove_set: Dictionary = {}
	for cp in chunks_to_remove:
		remove_set[cp] = true

	# Supprimer les NPCs des chunks déchargés + libérer leurs POI
	var village_mgr = get_node_or_null("/root/VillageManager")
	var remaining_npcs = []
	for npc_data in npcs:
		if remove_set.has(npc_data["chunk_pos"]):
			if is_instance_valid(npc_data["npc"]):
				var npc = npc_data["npc"]
				if poi_manager and npc.claimed_poi != Vector3i(-9999, -9999, -9999):
					poi_manager.release_poi(npc.claimed_poi)
				if village_mgr:
					village_mgr.unregister_villager(npc)
				npc.queue_free()
		else:
			remaining_npcs.append(npc_data)
	npcs = remaining_npcs

	# Retirer les POI des chunks déchargés
	if poi_manager:
		for chunk_pos in chunks_to_remove:
			poi_manager.remove_chunk_pois(chunk_pos)

	# Allow mob respawn in unloaded chunks + clean pending queue
	for chunk_pos in chunks_to_remove:
		_spawned_chunks.erase(chunk_pos)
	# Purge pending mob spawns for unloaded chunks
	if not _pending_mob_chunks.is_empty():
		_pending_mob_chunks = _pending_mob_chunks.filter(func(cp): return not remove_set.has(cp))

func _world_to_chunk(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_pos.x / Chunk.CHUNK_SIZE),
		0,
		floori(world_pos.z / Chunk.CHUNK_SIZE)
	)

func get_block_at_position(world_pos: Vector3) -> BlockRegistry.BlockType:
	var chunk_pos = _world_to_chunk(world_pos)
	# floori au lieu de int() — int() tronque vers 0, floori vers -inf
	var local_pos = Vector3i(
		floori(world_pos.x) % Chunk.CHUNK_SIZE,
		floori(world_pos.y),
		floori(world_pos.z) % Chunk.CHUNK_SIZE
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
		floori(world_pos.x) % Chunk.CHUNK_SIZE,
		floori(world_pos.y),
		floori(world_pos.z) % Chunk.CHUNK_SIZE
	)

	if local_pos.x < 0:
		local_pos.x += Chunk.CHUNK_SIZE
	if local_pos.z < 0:
		local_pos.z += Chunk.CHUNK_SIZE
	
	if chunks.has(chunk_pos):
		chunks[chunk_pos].set_block(local_pos.x, local_pos.y, local_pos.z, block_type)

func break_block_at_position(world_pos: Vector3):
	var broken_type = get_block_at_position(world_pos)
	# Si on casse une porte, supprimer la paire entière
	if BlockRegistry.is_door(broken_type):
		var door_bt = remove_door(world_pos)
		_broken_extras.clear()
		# Ne pas ajouter aux extras — le bloc principal est déjà compté par l'appelant
		# Mais il faut signaler que c'est une porte (l'appelant ne doit pas re-ajouter)
		_broken_extras.append(door_bt)
		return
	set_block_at_position(world_pos, BlockRegistry.BlockType.AIR)
	# Nettoyer orientation vitre si applicable
	var bkey = Vector3i(int(floor(world_pos.x)), int(floor(world_pos.y)), int(floor(world_pos.z)))
	pane_orientation.erase(bkey)
	_broken_extras.clear()
	# Supprimer la végétation décorative posée sur le bloc cassé
	var above_pos = world_pos + Vector3(0, 1, 0)
	var above_type = get_block_at_position(above_pos)
	if BlockRegistry.is_cross_mesh(above_type):
		set_block_at_position(above_pos, BlockRegistry.BlockType.AIR)
		_broken_extras.append(above_type)
	# Supprimer les torches supportées par ce bloc (au-dessus + 4 adjacents)
	var torch_checks = [
		above_pos,
		world_pos + Vector3(1, 0, 0),
		world_pos + Vector3(-1, 0, 0),
		world_pos + Vector3(0, 0, 1),
		world_pos + Vector3(0, 0, -1),
	]
	for check_pos in torch_checks:
		if get_block_at_position(check_pos) == BlockRegistry.BlockType.TORCH:
			set_block_at_position(check_pos, BlockRegistry.BlockType.AIR)
			_broken_extras.append(BlockRegistry.BlockType.TORCH)
	# Supprimer les portes dont le bloc support a été cassé (adjacents + dessous)
	var door_checks = [
		above_pos,
		world_pos + Vector3(1, 0, 0), world_pos + Vector3(-1, 0, 0),
		world_pos + Vector3(0, 0, 1), world_pos + Vector3(0, 0, -1),
	]
	for check_pos in door_checks:
		var check_type = get_block_at_position(check_pos)
		if BlockRegistry.is_door(check_type):
			# Vérifier si cette porte a encore un support (bloc solide en dessous du bas de la porte)
			var door_bottom_key = Vector3i(int(floor(check_pos.x)), int(floor(check_pos.y)), int(floor(check_pos.z)))
			var door_bottom = _get_door_bottom(door_bottom_key)
			var support_pos = Vector3(door_bottom.x, door_bottom.y - 1, door_bottom.z)
			var support_type = get_block_at_position(support_pos)
			if not BlockRegistry.is_solid(support_type):
				var door_bt = remove_door(check_pos)
				_broken_extras.append(door_bt)

var _broken_extras: Array = []

func get_and_clear_broken_extras() -> Array:
	var extras = _broken_extras.duplicate()
	_broken_extras.clear()
	return extras

func place_block_at_position(world_pos: Vector3, block_type: BlockRegistry.BlockType):
	set_block_at_position(world_pos, block_type)

# ============================================================
# API MONDE — interface découplée pour village_manager / npc_villager
# Les modules externes passent UNIQUEMENT par ces méthodes.
# Les accès directs à chunks[], chunk.blocks[], chunk._rebuild_mesh()
# sont interdits en dehors de world_manager.gd et chunk.gd.
# ============================================================

func is_chunk_loaded(chunk_pos: Vector3i) -> bool:
	return chunks.has(chunk_pos)

func get_chunk_y_max(chunk_pos: Vector3i) -> int:
	if chunks.has(chunk_pos):
		return chunks[chunk_pos].y_max
	return 120

func get_chunk_y_min(chunk_pos: Vector3i) -> int:
	if chunks.has(chunk_pos):
		return chunks[chunk_pos].y_min
	return 0

func find_surface_y(wx: int, wz: int) -> int:
	# Trouver le Y de surface (bloc solide le plus haut, ignore eau et cross-mesh)
	var chunk_pos = Vector3i(floori(float(wx) / Chunk.CHUNK_SIZE), 0, floori(float(wz) / Chunk.CHUNK_SIZE))
	var start_y = 120
	if chunks.has(chunk_pos):
		start_y = mini(chunks[chunk_pos].y_max + 1, Chunk.CHUNK_HEIGHT - 1)
	for y in range(start_y, 0, -1):
		var bt = get_block_at_position(Vector3(wx, y, wz))
		if bt != BlockRegistry.BlockType.AIR and bt != BlockRegistry.BlockType.WATER and not BlockRegistry.is_cross_mesh(bt):
			return y
	return -1

func find_ground_y(wx: int, wz: int) -> int:
	# Trouver le Y du SOL (ignore feuilles, troncs, herbe, végétation)
	var flora_set = { 77: true, 78: true, 79: true, 80: true, 81: true, 82: true }
	var chunk_pos = Vector3i(floori(float(wx) / Chunk.CHUNK_SIZE), 0, floori(float(wz) / Chunk.CHUNK_SIZE))
	var start_y = 120
	if chunks.has(chunk_pos):
		start_y = mini(chunks[chunk_pos].y_max + 1, Chunk.CHUNK_HEIGHT - 1)
	for y in range(start_y, 0, -1):
		var bt = get_block_at_position(Vector3(wx, y, wz))
		if bt == BlockRegistry.BlockType.AIR or bt == BlockRegistry.BlockType.WATER:
			continue
		if BlockRegistry.LEAF_TYPES.has(bt) or BlockRegistry.WOOD_TYPES.has(bt) or flora_set.has(bt):
			continue
		return y
	return -1

func set_block_raw(world_pos: Vector3, block_type: int) -> Vector3i:
	# Set un bloc SANS rebuild mesh — pour les opérations batch.
	# Retourne le chunk_pos affecté (pour rebuild groupé après).
	var chunk_pos = _world_to_chunk(world_pos)
	if not chunks.has(chunk_pos):
		return Vector3i(-9999, 0, -9999)
	var local_x = floori(world_pos.x) % Chunk.CHUNK_SIZE
	var local_z = floori(world_pos.z) % Chunk.CHUNK_SIZE
	if local_x < 0:
		local_x += Chunk.CHUNK_SIZE
	if local_z < 0:
		local_z += Chunk.CHUNK_SIZE
	var local_y = floori(world_pos.y)
	if local_y < 0 or local_y >= Chunk.CHUNK_HEIGHT:
		return Vector3i(-9999, 0, -9999)
	chunks[chunk_pos].blocks[local_x * 4096 + local_z * 256 + local_y] = block_type
	chunks[chunk_pos].is_modified = true
	return chunk_pos

func rebuild_chunk_by_key(chunk_pos: Vector3i):
	# Rebuild mesh d'un chunk identifié par sa clé Vector3i
	if chunks.has(chunk_pos):
		chunks[chunk_pos]._rebuild_mesh()

func get_block_raw_in_chunk(chunk_pos: Vector3i, lx: int, ly: int, lz: int) -> int:
	# Lecture brute d'un bloc par coordonnées locales dans un chunk.
	# Pour les scans bulk haute perf (find_closest_block, etc.)
	if not chunks.has(chunk_pos):
		return 0
	return chunks[chunk_pos].blocks[lx * 4096 + lz * 256 + ly]

func scan_blocks_in_chunks(from_pos: Vector3, chunk_radius: int, acceptable_set: Dictionary, max_results: int = 20, sampling: int = 2) -> Array:
	# Scan bulk : cherche des blocs d'un type donné dans les chunks chargés.
	# Retourne un Array de Vector3i (positions monde). Échantillonnage 1/sampling.
	var results: Array = []
	var from_chunk = _world_to_chunk(from_pos)
	var chunk_list: Array = []
	for cx in range(from_chunk.x - chunk_radius, from_chunk.x + chunk_radius + 1):
		for cz in range(from_chunk.z - chunk_radius, from_chunk.z + chunk_radius + 1):
			var cp = Vector3i(cx, 0, cz)
			if chunks.has(cp):
				chunk_list.append(cp)
	chunk_list.sort_custom(func(a, b):
		var da = abs(a.x - from_chunk.x) + abs(a.z - from_chunk.z)
		var db = abs(b.x - from_chunk.x) + abs(b.z - from_chunk.z)
		return da < db)

	for cp in chunk_list:
		var chunk = chunks[cp]
		var blocks = chunk.blocks
		var y_start = maxi(chunk.y_min, 1)
		var y_end = mini(chunk.y_max + 1, Chunk.CHUNK_HEIGHT)
		for lx in range(0, Chunk.CHUNK_SIZE, sampling):
			var x_off = lx * Chunk.CHUNK_SIZE * Chunk.CHUNK_HEIGHT
			for lz in range(0, Chunk.CHUNK_SIZE, sampling):
				var xz_off = x_off + lz * Chunk.CHUNK_HEIGHT
				for ly in range(y_start, y_end):
					var bt = blocks[xz_off + ly]
					if acceptable_set.has(bt):
						results.append(Vector3i(
							cp.x * Chunk.CHUNK_SIZE + lx,
							ly,
							cp.z * Chunk.CHUNK_SIZE + lz
						))
		if results.size() >= max_results:
			break
	return results

func scan_surface_blocks_in_chunks(from_pos: Vector3, chunk_radius: int, acceptable_set: Dictionary, sampling: int = 2) -> Array:
	# Scan bulk surface : ne retourne que les blocs avec AIR au-dessus.
	# Retourne un Array de Vector3i + distance (pour tri côté appelant).
	var results: Array = []
	var from_chunk = _world_to_chunk(from_pos)
	for cx in range(from_chunk.x - chunk_radius, from_chunk.x + chunk_radius + 1):
		for cz in range(from_chunk.z - chunk_radius, from_chunk.z + chunk_radius + 1):
			var cp = Vector3i(cx, 0, cz)
			if not chunks.has(cp):
				continue
			var chunk = chunks[cp]
			var blocks_data = chunk.blocks
			var y_start = maxi(chunk.y_min, 1)
			var y_end = mini(chunk.y_max + 1, Chunk.CHUNK_HEIGHT - 1)
			for lx in range(0, Chunk.CHUNK_SIZE, sampling):
				var x_off = lx * Chunk.CHUNK_SIZE * Chunk.CHUNK_HEIGHT
				for lz in range(0, Chunk.CHUNK_SIZE, sampling):
					var xz_off = x_off + lz * Chunk.CHUNK_HEIGHT
					for ly in range(y_start, y_end):
						var bt = blocks_data[xz_off + ly]
						if acceptable_set.has(bt):
							if blocks_data[xz_off + ly + 1] == 0:  # AIR au-dessus
								results.append(Vector3i(
									cx * Chunk.CHUNK_SIZE + lx,
									ly,
									cz * Chunk.CHUNK_SIZE + lz
								))
	return results

func scan_poi_at_chunk(chunk_pos: Vector3i):
	# Scanner les POI d'un chunk — encapsule l'accès à poi_manager + chunk.blocks
	if poi_manager and chunks.has(chunk_pos):
		var chunk = chunks[chunk_pos]
		poi_manager.scan_chunk(chunk_pos, chunk.blocks, chunk.y_min, chunk.y_max)

func add_npc_to_world(npc: Node, chunk_pos: Vector3i):
	# Ajouter un PNJ au monde — encapsule l'accès à npcs[] et poi_manager
	if poi_manager:
		npc.poi_manager = poi_manager
	get_parent().call_deferred("add_child", npc)
	npcs.append({"npc": npc, "chunk_pos": chunk_pos})

func get_loaded_chunk_keys_in_range(center: Vector3i, radius_blocks: int) -> Array:
	# Retourne les clés des chunks chargés dans un rayon donné (en blocs)
	var result: Array = []
	var min_cx = floori(float(center.x - radius_blocks) / Chunk.CHUNK_SIZE)
	var max_cx = floori(float(center.x + radius_blocks) / Chunk.CHUNK_SIZE)
	var min_cz = floori(float(center.z - radius_blocks) / Chunk.CHUNK_SIZE)
	var max_cz = floori(float(center.z + radius_blocks) / Chunk.CHUNK_SIZE)
	for cx_i in range(min_cx, max_cx + 1):
		for cz_i in range(min_cz, max_cz + 1):
			var cp = Vector3i(cx_i, 0, cz_i)
			if chunks.has(cp):
				result.append(cp)
	return result

func get_modified_chunks_data() -> Array:
	# Retourne les chunks modifiés pour la sauvegarde : [{pos: Vector3i, blocks: PackedByteArray}]
	var result: Array = []
	for chunk_pos in chunks:
		var chunk = chunks[chunk_pos]
		if chunk.is_modified:
			result.append({"pos": chunk_pos, "blocks": chunk.blocks})
	return result

func free_all_chunks():
	# Supprime tous les chunks du monde (pour le chargement d'une sauvegarde)
	for chunk_pos in chunks.keys():
		chunks[chunk_pos].queue_free()
	chunks.clear()

# ============================================================
# PNJ VILLAGEOIS
# ============================================================

func _try_spawn_village(chunk_pos: Vector3i, chunk_data: Dictionary):
	# Spawn le village seulement dans le chunk du joueur
	var player_chunk = _world_to_chunk(player.global_position)
	if chunk_pos != player_chunk:
		return

	_village_spawned = true

	var packed_blocks = chunk_data["blocks"]
	var village_mgr = get_node_or_null("/root/VillageManager")

	# Centre du village = position du joueur
	var center_x = int(player.global_position.x) % Chunk.CHUNK_SIZE
	var center_z = int(player.global_position.z) % Chunk.CHUNK_SIZE
	if center_x < 0:
		center_x += Chunk.CHUNK_SIZE
	if center_z < 0:
		center_z += Chunk.CHUNK_SIZE

	# Trouver la surface au centre
	var center_surface_y = -1
	for y in range(Chunk.CHUNK_HEIGHT - 1, 0, -1):
		var bt = packed_blocks[center_x * 4096 + center_z * 256 + y]
		if bt != 0 and bt != BlockRegistry.BlockType.WATER:
			center_surface_y = y + 1
			break

	if center_surface_y < 0:
		return

	# Téléporter le joueur à la surface (le chunk_data contient déjà les blocs, donc center_surface_y est fiable)
	# Le joueur doit être AU-DESSUS de la surface pour ne pas tomber dans une grotte
	if player and center_surface_y > 0 and center_surface_y < 200:
		player.global_position.y = center_surface_y + 3.0
		player.velocity = Vector3.ZERO
		#print("Player: téléporté à la surface Y=%d" % (center_surface_y + 3))

	var village_center = Vector3(
		chunk_pos.x * Chunk.CHUNK_SIZE + center_x + 0.5,
		center_surface_y,
		chunk_pos.z * Chunk.CHUNK_SIZE + center_z + 0.5
	)

	if village_mgr:
		village_mgr.set_village_center(village_center)

	# L'aplanissement est désormais géré par le bâtisseur via VillageManager.flatten_plan

	# Spawn 9 villageois groupés — professions FIXES et optimisées :
	# 1 BUCHERON (récolte bois), 2 MINEUR (galerie souterraine),
	# 1 FORGERON (craft outils/lingots), 2 BATISSEUR (aplanir + construire en parallèle),
	# 1 MENUISIER (craft planches/meubles), 1 FERMIER (récolte diverse), 1 BOULANGER
	var VILLAGE_PROFESSIONS = [
		VProfession.Profession.BUCHERON,   # PNJ 0
		VProfession.Profession.BATISSEUR,  # PNJ 1
		VProfession.Profession.MINEUR,     # PNJ 2
		VProfession.Profession.MINEUR,     # PNJ 3
		VProfession.Profession.FORGERON,   # PNJ 4
		VProfession.Profession.BATISSEUR,  # PNJ 5
		VProfession.Profession.MENUISIER,  # PNJ 6
		VProfession.Profession.FERMIER,    # PNJ 7
		VProfession.Profession.BOULANGER,  # PNJ 8
	]

	var spawned = 0
	for i in range(VILLAGE_NPC_COUNT):
		var offset_x = randi_range(-4, 4)
		var offset_z = randi_range(-4, 4)
		var lx = clampi(center_x + offset_x, 0, Chunk.CHUNK_SIZE - 1)
		var lz = clampi(center_z + offset_z, 0, Chunk.CHUNK_SIZE - 1)

		var surface_y = -1
		for y in range(Chunk.CHUNK_HEIGHT - 1, 0, -1):
			var bt = packed_blocks[lx * 4096 + lz * 256 + y]
			if bt != 0 and bt != BlockRegistry.BlockType.WATER:
				surface_y = y + 1
				break

		if surface_y < 0 or surface_y >= Chunk.CHUNK_HEIGHT - 2:
			continue

		# Profession fixe selon l'index
		var prof = VILLAGE_PROFESSIONS[i] if i < VILLAGE_PROFESSIONS.size() else 0

		var world_x = chunk_pos.x * Chunk.CHUNK_SIZE + lx + 0.5
		var world_z = chunk_pos.z * Chunk.CHUNK_SIZE + lz + 0.5
		var spawn_pos = Vector3(world_x, surface_y, world_z)

		var npc = NpcVillagerScene.new()
		npc.setup(i, spawn_pos, chunk_pos, prof)
		if poi_manager:
			npc.poi_manager = poi_manager
		get_parent().call_deferred("add_child", npc)
		npcs.append({"npc": npc, "chunk_pos": chunk_pos})

		if village_mgr:
			village_mgr.register_villager(npc)

		spawned += 1

	#print("WorldManager: village spawné avec %d villageois à %s" % [spawned, str(village_center)])

	# Le village ennemi sera spawné par VillageManager quand le joueur atteint Phase 4

func _spawn_enemy_village(player_village_center: Vector3):
	# Spawner le village ennemi à ~500 blocs dans une direction cardinale aléatoire
	var EnemyVillageScript = preload("res://scripts/enemy_village.gd")
	var WarManagerScript = preload("res://scripts/war_manager.gd")

	var directions = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var dir = directions[randi() % 4]
	var distance = randi_range(400, 600)  # 400-600 blocs
	var enemy_center = player_village_center + dir * distance
	enemy_center.y = 70  # altitude estimée (pas de chunks chargés là-bas)

	# Créer le village ennemi
	var enemy = EnemyVillageScript.new()
	enemy.name = "EnemyVillage"
	enemy.add_to_group("enemy_village")
	get_parent().call_deferred("add_child", enemy)
	enemy.call_deferred("initialize", enemy_center, 70)

	# Créer le war manager
	var war_mgr = WarManagerScript.new()
	war_mgr.name = "WarManager"
	get_parent().call_deferred("add_child", war_mgr)

	#print("WorldManager: village ennemi initialisé à %s (distance: %d blocs, direction: %s)" % [
	#	str(enemy_center), distance, str(dir)])

func _flatten_village_area(chunk_pos: Vector3i, packed_blocks: PackedByteArray, cx: int, cz: int, ref_y: int):
	# Supprimer les blocs gênants au-dessus du sol dans un rayon de 6 blocs
	# Pour que les villageois puissent naviguer librement autour du village
	var radius = 6
	var cleared = 0
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var lx = cx + dx
			var lz = cz + dz
			if lx < 0 or lx >= Chunk.CHUNK_SIZE or lz < 0 or lz >= Chunk.CHUNK_SIZE:
				continue
			# Trouver la surface locale
			var local_surface_y = -1
			for y in range(Chunk.CHUNK_HEIGHT - 1, 0, -1):
				var bt = packed_blocks[lx * 4096 + lz * 256 + y]
				if bt != 0 and bt != BlockRegistry.BlockType.WATER:
					local_surface_y = y
					break
			if local_surface_y < 0:
				continue
			# Si la surface est 1-2 blocs PLUS HAUTE que le centre → casser les blocs en trop
			var diff = local_surface_y - ref_y
			if diff >= 1 and diff <= 3:
				for remove_y in range(ref_y + 1, local_surface_y + 1):
					var idx = lx * 4096 + lz * 256 + remove_y
					if packed_blocks[idx] != 0:
						packed_blocks[idx] = 0  # AIR
						cleared += 1
	if cleared > 0:
		#print("WorldManager: terrain aplati — %d blocs retirés autour du village" % cleared)
		pass

# ============================================================
#  MOB SPAWNING
# ============================================================

func _process_pending_mob_spawns():
	"""Process queued mob spawns — only when chunk mesh+collision is ready.
	Max 3 per frame, uses chunk.blocks directly (no copy)."""
	var still_pending = []
	var processed = 0
	for cp in _pending_mob_chunks:
		if not chunks.has(cp):
			continue  # chunk unloaded, drop
		var chunk = chunks[cp]
		if chunk.is_mesh_built and processed < 3:
			_try_spawn_passive_mobs_in_chunk(cp, chunk.blocks)
			processed += 1
		else:
			still_pending.append(cp)  # mesh not ready OR over frame limit → retry next frame
	_pending_mob_chunks = still_pending

func _get_biome_at_chunk(chunk_pos: Vector3i) -> int:
	# Sample biome at center of chunk using the chunk generator noises
	if chunk_generator:
		var wx = chunk_pos.x * Chunk.CHUNK_SIZE + 8
		var wz = chunk_pos.z * Chunk.CHUNK_SIZE + 8
		return chunk_generator.get_biome_at(wx, wz)
	return 3  # default plains

func _find_ground_y_in_chunk(blocks: PackedByteArray, lx: int, lz: int) -> int:
	"""Find the GROUND surface Y (ignoring trees, vegetation, torches).
	Returns the Y of the solid ground block where a mob can stand."""
	var offset = lx * Chunk.CHUNK_SIZE * Chunk.CHUNK_HEIGHT + lz * Chunk.CHUNK_HEIGHT
	for y in range(Chunk.CHUNK_HEIGHT - 1, 0, -1):
		var bt = blocks[offset + y]
		if bt == 0 or bt == BlockRegistry.BlockType.WATER:
			continue
		# Skip non-ground blocks: leaves, logs, vegetation, torches, etc.
		if bt == BlockRegistry.BlockType.LEAVES or \
		   bt == BlockRegistry.BlockType.WOOD or \
		   bt == BlockRegistry.BlockType.CACTUS or \
		   bt == BlockRegistry.BlockType.TORCH or \
		   bt >= BlockRegistry.BlockType.SPRUCE_LOG and bt <= BlockRegistry.BlockType.CHERRY_LEAVES:
			continue
		# Skip cross-mesh vegetation (SHORT_GRASS=98, FERN=99, etc.)
		if bt >= 98 and bt <= 103:
			continue
		# Found solid ground — verify 2 blocks of air above for mob to stand
		if y + 2 < Chunk.CHUNK_HEIGHT:
			var above1 = blocks[offset + y + 1]
			var above2 = blocks[offset + y + 2]
			# Air, vegetation, or leaves above = OK
			var a1_clear = (above1 == 0 or above1 >= 98 and above1 <= 103 or above1 == BlockRegistry.BlockType.LEAVES)
			var a2_clear = (above2 == 0 or above2 >= 98 and above2 <= 103 or above2 == BlockRegistry.BlockType.LEAVES)
			if a1_clear and a2_clear:
				return y
		else:
			return y
	return -1

func _try_spawn_passive_mobs_in_chunk(chunk_pos: Vector3i, blocks: PackedByteArray, force: bool = false):
	"""Spawn mobs when a new chunk is generated — uses mob_database.json."""
	mobs = mobs.filter(func(m): return is_instance_valid(m))
	# Compter seulement les mobs proches du joueur (pas ceux qui vont despawn)
	var nearby_count = 0
	if player:
		for m in mobs:
			if is_instance_valid(m) and m.global_position.distance_to(player.global_position) < 80.0:
				nearby_count += 1
	else:
		nearby_count = mobs.size()
	if nearby_count >= MAX_MOBS:
		return

	# Spawn in ~50% of chunks (skip si pas forcé par le respawn)
	if not force and randf() > 0.5:
		return

	var biome = _get_biome_at_chunk(chunk_pos)
	var is_day = true
	var dnc = get_tree().get_first_node_in_group("day_night_cycle")
	if dnc:
		var hour = dnc.get_hour()
		is_day = hour >= 6.0 and hour < 18.0

	# Pick mob list based on time of day
	var mob_list: Array = []
	if is_day:
		mob_list = PassiveMob.BIOME_DAY_MOBS.get(biome, [])
	else:
		mob_list = PassiveMob.BIOME_NIGHT_MOBS.get(biome, [])
	if mob_list.is_empty():
		return

	# Filter mobs : aquatiques seulement en ocean/riviere, terrestres ailleurs
	var is_water_biome = biome == 4 or biome == 6  # OCEAN ou RIVER
	var filtered: Array = []
	for mid in mob_list:
		var mdata = PassiveMob.get_mob_data(mid)
		var beh = mdata.get("behavior", "passive")
		if is_day and (beh == "hostile" or beh == "boss"):
			continue
		var special: Array = mdata.get("special", [])
		var is_aquatic = "needs_water" in special
		if is_aquatic and not is_water_biome:
			continue  # Pas de mobs aquatiques sur terre
		if not is_aquatic and is_water_biome:
			continue  # Pas de mobs terrestres dans l'ocean
		filtered.append(mid)
	if filtered.is_empty():
		return

	# Pick 1-2 mobs — respect spawn_group for the chosen mob
	var chosen_id: String = filtered[randi() % filtered.size()]
	var chosen_data = PassiveMob.get_mob_data(chosen_id)
	var group_min = int(chosen_data.get("spawn_group_min", 1))
	var group_max = int(chosen_data.get("spawn_group_max", 2))
	var max_chunk = int(chosen_data.get("max_per_chunk", 4))
	var count = mini(randi_range(group_min, group_max), max_chunk)

	# Count existing mobs of this type in nearby chunks
	var existing_count = 0
	for m in mobs:
		if is_instance_valid(m) and m is PassiveMob and m.mob_id == chosen_id:
			if m.chunk_position.distance_to(Vector3(chunk_pos)) < 3:
				existing_count += 1
	count = mini(count, max_chunk - existing_count)

	for i in range(count):
		if mobs.size() >= MAX_MOBS:
			break
		for _attempt in range(4):
			var lx = randi_range(2, 13)
			var lz = randi_range(2, 13)
			var sy = _find_ground_y_in_chunk(blocks, lx, lz)
			if sy >= 10 and sy <= 200:
				# Check spawn_below_y constraint
				var max_y = int(chosen_data.get("spawn_below_y", 999))
				if sy > max_y:
					continue
				var wx = chunk_pos.x * Chunk.CHUNK_SIZE + lx
				var wz = chunk_pos.z * Chunk.CHUNK_SIZE + lz
				_spawn_mob_by_id(chosen_id, Vector3(wx + 0.5, sy + 1.0, wz + 0.5), chunk_pos)
				break

func _try_spawn_mobs():
	"""Periodic spawn check — spawns hostile mobs at night near the player."""
	mobs = mobs.filter(func(m): return is_instance_valid(m))
	if mobs.size() >= MAX_MOBS:
		return

	var dnc = get_tree().get_first_node_in_group("day_night_cycle")
	if not dnc or not player:
		return
	var hour = dnc.get_hour()
	var is_night = hour < 6.0 or hour >= 18.0

	if not is_night:
		return  # Hostile mobs only spawn at night

	# Count current hostile mobs PROCHES du joueur
	var hostile_count = 0
	for m in mobs:
		if is_instance_valid(m) and m is PassiveMob and m._behavior == PassiveMob.Behavior.HOSTILE:
			if m.global_position.distance_to(player.global_position) < 80.0:
				hostile_count += 1
	if hostile_count >= 20:
		return

	var player_pos = player.global_position
	var spawned_this_cycle = 0
	for _i in range(8):
		var angle = randf() * TAU
		var dist = randf_range(MOB_SPAWN_MIN_DIST, MOB_SPAWN_MAX_DIST)
		var spawn_x = player_pos.x + cos(angle) * dist
		var spawn_z = player_pos.z + sin(angle) * dist
		var spawn_chunk = _world_to_chunk(Vector3(spawn_x, 0, spawn_z))
		if not chunks.has(spawn_chunk):
			continue

		var chunk = chunks[spawn_chunk]
		var lx = int(spawn_x) - spawn_chunk.x * Chunk.CHUNK_SIZE
		var lz = int(spawn_z) - spawn_chunk.z * Chunk.CHUNK_SIZE
		lx = clampi(lx, 0, Chunk.CHUNK_SIZE - 1)
		lz = clampi(lz, 0, Chunk.CHUNK_SIZE - 1)
		var sy = _find_ground_y_in_chunk(chunk.blocks, lx, lz)
		if sy < 10 or sy > 200:
			continue

		var biome = _get_biome_at_chunk(spawn_chunk)
		# Get night mobs for this biome — includes hostile mobs
		var night_mobs: Array = PassiveMob.BIOME_NIGHT_MOBS.get(biome, [])
		# Filter to hostile-only, exclude aquatic
		var hostile_list: Array = []
		for mid in night_mobs:
			var mdata = PassiveMob.get_mob_data(mid)
			var special: Array = mdata.get("special", [])
			if "needs_water" in special:
				continue
			var beh = mdata.get("behavior", "passive")
			if beh == "hostile" or beh == "neutral":
				var spawn_time = mdata.get("spawn_time", "day")
				if spawn_time == "night" or spawn_time == "both":
					hostile_list.append(mid)
		if hostile_list.is_empty():
			continue

		var chosen_id = hostile_list[randi() % hostile_list.size()]
		var spawn_pos = Vector3(spawn_x, sy + 1.0, spawn_z)
		_spawn_mob_by_id(chosen_id, spawn_pos, spawn_chunk)
		spawned_this_cycle += 1
		if spawned_this_cycle >= 3:  # Up to 3 mobs per cycle
			break

func _try_respawn_passive_mobs():
	"""Periodic passive mob respawn — fills nearby loaded chunks that have few mobs.
	This compensates for mobs that despawned when the player moved away."""
	if not _mob_glbs_preloaded or not player:
		return
	mobs = mobs.filter(func(m): return is_instance_valid(m))
	var nearby_count = 0
	for m in mobs:
		if is_instance_valid(m) and m.global_position.distance_to(player.global_position) < 80.0:
			nearby_count += 1
	# Only respawn if population is low
	if nearby_count >= MAX_MOBS:
		return
	var player_chunk = _world_to_chunk(player.global_position)
	# Collecter les chunks proches du joueur (distance 2 à render_distance)
	var candidate_chunks: Array = []
	for cp in chunks:
		var dist = abs(cp.x - player_chunk.x) + abs(cp.z - player_chunk.z)
		if dist >= 2 and dist <= render_distance and chunks[cp].is_mesh_built:
			candidate_chunks.append(cp)
	candidate_chunks.shuffle()
	# Plus agressif quand la population est basse
	var max_spawns = 4 if nearby_count < MAX_MOBS / 3 else 2
	var spawned = 0
	for cp in candidate_chunks:
		if spawned >= max_spawns:
			break
		# Pas de skip aléatoire — le respawn est déjà limité à toutes les 5s
		_try_spawn_passive_mobs_in_chunk(cp, chunks[cp].blocks, true)
		spawned += 1

func _preload_mob_glbs():
	"""Preload all mob GLB scenes + load mob database."""
	PassiveMob.load_database()
	for mid in PassiveMob.get_all_converted_mob_ids():
		var data = PassiveMob.get_mob_data(mid)
		var glb_path = data.get("glb_path", "")
		if glb_path != "" and ResourceLoader.exists(glb_path):
			PassiveMob._load_glb(glb_path)

func _spawn_mob_by_id(id: String, pos: Vector3, chunk_pos: Vector3i):
	var mob = PassiveMob.new()
	mob.setup_from_id(id, pos, chunk_pos)
	add_child(mob)
	mobs.append(mob)
