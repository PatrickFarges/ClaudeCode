extends Node3D
class_name WorldManager

@export var render_distance: int = 4
@export var chunk_load_per_frame: int = 2
@export var unload_distance_margin: int = 3  # Marge pour éviter le clignotement
@export var max_mesh_builds_per_frame: int = 2  # Limite de mesh construits par frame

var chunks: Dictionary = {}
var player: CharacterBody3D
var last_player_chunk: Vector3i = Vector3i.ZERO  # Position précédente du joueur
var chunk_generator: ChunkGenerator
var pending_meshes: Array = []  # Chunks en attente de construction de mesh
var world_seed: int = 0  # Seed du monde (0 = aléatoire)

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
		
		# Construire les meshes des chunks prêts
		_build_pending_meshes()

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
	
	# Créer le chunk avec les données générées
	var chunk = Chunk.new(chunk_pos, blocks)
	chunk.position = Vector3(chunk_pos.x * Chunk.CHUNK_SIZE, 0, chunk_pos.z * Chunk.CHUNK_SIZE)
	add_child(chunk)
	chunks[chunk_pos] = chunk
	
	# Ajouter à la liste des meshes à construire
	pending_meshes.append(chunk)

func _build_pending_meshes():
	"""Construire les meshes des chunks en attente (thread principal)"""
	var built = 0
	while built < max_mesh_builds_per_frame and pending_meshes.size() > 0:
		var chunk = pending_meshes.pop_front()
		if chunk and is_instance_valid(chunk):
			chunk.build_mesh()
			built += 1

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
