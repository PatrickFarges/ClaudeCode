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

# Mobs passifs
var mobs: Array = []
const MAX_MOBS = 20

func _ready():
	# Générer un seed aléatoire si non défini
	if world_seed == 0:
		randomize()
		world_seed = randi()

	# Créer le générateur de chunks avec le seed du monde
	chunk_generator = ChunkGenerator.new()
	chunk_generator.set_world_seed(world_seed)
	add_child(chunk_generator)
	chunk_generator.chunk_generated.connect(_on_chunk_data_ready)

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

	# Créer le chunk avec les données générées
	var chunk = Chunk.new(chunk_pos, blocks, p_y_min, p_y_max)
	chunk.position = Vector3(chunk_pos.x * Chunk.CHUNK_SIZE, 0, chunk_pos.z * Chunk.CHUNK_SIZE)
	add_child(chunk)
	chunks[chunk_pos] = chunk

	# Lancer la construction du mesh en arrière-plan (thread dédié)
	chunk.build_mesh_async()

	# Tenter de spawn des mobs passifs
	_try_spawn_mobs(chunk_pos, chunk_data)

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
