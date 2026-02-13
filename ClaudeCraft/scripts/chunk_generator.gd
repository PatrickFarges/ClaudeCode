extends Node
class_name ChunkGenerator

# v6.2 : Vrais arbres 3D avec couronnes de feuilles !
# - Chêne (forêt) : tronc + couronne 5x5x4
# - Bouleau (plaine) : tronc + couronne 3x3x3
# - Pin (montagne) : tronc + couronne conique
# - Cactus (désert) : inchangé
# Technique : 2 passes — terrain d'abord, puis arbres sur le chunk entier

signal chunk_generated(chunk_data: Dictionary)

const MAX_THREADS = 4
const CHUNK_SIZE = 16
const CHUNK_HEIGHT = 256
const SEA_LEVEL = 64
const TREE_MARGIN = 3  # Marge depuis le bord du chunk (évite couronnes coupées)

var thread_pool: Array[Thread] = []
var generation_queue: Array = []
var active_generations: Dictionary = {}
var queue_mutex: Mutex = Mutex.new()
var should_exit: bool = false
var world_seed: int = 0

func set_world_seed(seed_value: int):
	world_seed = seed_value

func get_world_seed() -> int:
	return world_seed

func _init():
	for i in range(MAX_THREADS):
		var thread = Thread.new()
		thread_pool.append(thread)

func _ready():
	for i in range(MAX_THREADS):
		thread_pool[i].start(_thread_worker.bind(i))

func queue_chunk_generation(chunk_pos: Vector3i, priority: int = 0):
	queue_mutex.lock()
	if not active_generations.has(chunk_pos):
		generation_queue.append({
			"position": chunk_pos,
			"priority": priority,
			"timestamp": Time.get_ticks_msec()
		})
		generation_queue.sort_custom(_sort_by_priority)
	queue_mutex.unlock()

func _sort_by_priority(a: Dictionary, b: Dictionary) -> bool:
	return a["priority"] < b["priority"]

func _thread_worker(thread_id: int):
	while not should_exit:
		var chunk_data = null
		
		queue_mutex.lock()
		if generation_queue.size() > 0:
			chunk_data = generation_queue.pop_front()
			if chunk_data:
				active_generations[chunk_data["position"]] = true
		queue_mutex.unlock()
		
		if chunk_data:
			var generated = _generate_chunk_data(chunk_data["position"])
			call_deferred("_on_chunk_generated", generated)
			
			queue_mutex.lock()
			active_generations.erase(chunk_data["position"])
			queue_mutex.unlock()
		else:
			OS.delay_msec(10)

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _generate_chunk_data(chunk_pos: Vector3i) -> Dictionary:
	var blocks = []
	blocks.resize(CHUNK_SIZE)
	
	# ============================================================
	# NOISES
	# ============================================================
	var seed_base = world_seed

	var terrain_noise = FastNoiseLite.new()
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	terrain_noise.seed = seed_base + 1234
	terrain_noise.frequency = 0.005
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrain_noise.fractal_octaves = 5
	terrain_noise.fractal_lacunarity = 2.0
	terrain_noise.fractal_gain = 0.45

	var elevation_noise = FastNoiseLite.new()
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	elevation_noise.seed = seed_base + 5555
	elevation_noise.frequency = 0.003
	elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	elevation_noise.fractal_octaves = 3
	elevation_noise.fractal_gain = 0.4

	var temp_noise = FastNoiseLite.new()
	temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	temp_noise.seed = seed_base + 9012
	temp_noise.frequency = 0.006
	temp_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	temp_noise.fractal_octaves = 2
	temp_noise.fractal_gain = 0.4

	var humid_noise = FastNoiseLite.new()
	humid_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	humid_noise.seed = seed_base + 3456
	humid_noise.frequency = 0.008
	humid_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	humid_noise.fractal_octaves = 2
	humid_noise.fractal_gain = 0.4

	var cave1 = FastNoiseLite.new()
	cave1.noise_type = FastNoiseLite.TYPE_PERLIN
	cave1.seed = seed_base + 7890
	cave1.frequency = 0.08

	var cave2 = FastNoiseLite.new()
	cave2.noise_type = FastNoiseLite.TYPE_PERLIN
	cave2.seed = seed_base + 2345
	cave2.frequency = 0.06

	var cave3 = FastNoiseLite.new()
	cave3.noise_type = FastNoiseLite.TYPE_PERLIN
	cave3.seed = seed_base + 6789
	cave3.frequency = 0.04

	var ore_noise = FastNoiseLite.new()
	ore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ore_noise.seed = seed_base + 4444
	ore_noise.frequency = 0.1
	
	# ============================================================
	# PASSE 1 : Générer le terrain + stocker heightmap et biome_map
	# ============================================================
	var heightmap = []  # [x][z] = surface height
	var biome_map = []  # [x][z] = biome id
	heightmap.resize(CHUNK_SIZE)
	biome_map.resize(CHUNK_SIZE)
	var y_min: int = CHUNK_HEIGHT
	var y_max: int = 0

	for x in range(CHUNK_SIZE):
		blocks[x] = []
		blocks[x].resize(CHUNK_SIZE)
		heightmap[x] = []
		heightmap[x].resize(CHUNK_SIZE)
		biome_map[x] = []
		biome_map[x].resize(CHUNK_SIZE)

		for z in range(CHUNK_SIZE):
			blocks[x][z] = []
			blocks[x][z].resize(CHUNK_HEIGHT)

			var wx = chunk_pos.x * CHUNK_SIZE + x
			var wz = chunk_pos.z * CHUNK_SIZE + z

			var n = (terrain_noise.get_noise_2d(wx, wz) + 1.0) / 2.0
			n = clampf(n, 0.0, 1.0)

			var elev = (elevation_noise.get_noise_2d(wx, wz) + 1.0) / 2.0
			elev = clampf(elev, 0.0, 1.0)

			var t = (temp_noise.get_noise_2d(wx, wz) + 1.0) / 2.0
			var h = (humid_noise.get_noise_2d(wx, wz) + 1.0) / 2.0
			var biome = _get_biome(t, h)

			var height = _get_continuous_height(n, elev)

			heightmap[x][z] = height
			biome_map[x][z] = biome

			for y in range(CHUNK_HEIGHT):
				var block = BlockRegistry.BlockType.AIR

				if y < height:
					block = _get_block(y, height, biome)

					if y >= 2 and y < SEA_LEVEL - 2 and _is_cave(wx, y, wz, cave1, cave2, cave3):
						block = BlockRegistry.BlockType.AIR

				blocks[x][z][y] = block
				if block != BlockRegistry.BlockType.AIR:
					if y < y_min:
						y_min = y
					if y > y_max:
						y_max = y

	# ============================================================
	# PASSE 1.5 : Placement des minerais près des grottes
	# ============================================================
	for ox in range(CHUNK_SIZE):
		for oz in range(CHUNK_SIZE):
			var owx = chunk_pos.x * CHUNK_SIZE + ox
			var owz = chunk_pos.z * CHUNK_SIZE + oz
			for oy in range(2, 60):
				if blocks[ox][oz][oy] == BlockRegistry.BlockType.STONE:
					var near_cave = false
					if oy > 0 and blocks[ox][oz][oy - 1] == BlockRegistry.BlockType.AIR:
						near_cave = true
					elif oy < CHUNK_HEIGHT - 1 and blocks[ox][oz][oy + 1] == BlockRegistry.BlockType.AIR:
						near_cave = true
					elif ox > 0 and blocks[ox - 1][oz][oy] == BlockRegistry.BlockType.AIR:
						near_cave = true
					elif ox < CHUNK_SIZE - 1 and blocks[ox + 1][oz][oy] == BlockRegistry.BlockType.AIR:
						near_cave = true
					elif oz > 0 and blocks[ox][oz - 1][oy] == BlockRegistry.BlockType.AIR:
						near_cave = true
					elif oz < CHUNK_SIZE - 1 and blocks[ox][oz + 1][oy] == BlockRegistry.BlockType.AIR:
						near_cave = true

					if near_cave:
						var ore_val = ore_noise.get_noise_3d(owx, oy, owz)
						if oy < 25 and ore_val > 0.8:
							blocks[ox][oz][oy] = BlockRegistry.BlockType.GOLD_ORE
						elif oy < 40 and ore_val > 0.7:
							blocks[ox][oz][oy] = BlockRegistry.BlockType.IRON_ORE
						elif ore_val > 0.6:
							blocks[ox][oz][oy] = BlockRegistry.BlockType.COAL_ORE

	# ============================================================
	# PASSE 2 : Placer les arbres et végétation (sur le chunk entier)
	# ============================================================
	_place_all_vegetation(blocks, heightmap, biome_map, chunk_pos)

	# ============================================================
	# PASSE 3 : Remplissage eau sous SEA_LEVEL
	# ============================================================
	for wx2 in range(CHUNK_SIZE):
		for wz2 in range(CHUNK_SIZE):
			for wy in range(SEA_LEVEL, 0, -1):
				if blocks[wx2][wz2][wy] == BlockRegistry.BlockType.AIR:
					blocks[wx2][wz2][wy] = BlockRegistry.BlockType.WATER
				elif blocks[wx2][wz2][wy] != BlockRegistry.BlockType.WATER:
					break

	# Ajuster y_max pour les couronnes d'arbres et l'eau
	if y_max > 0:
		y_max = mini(y_max + 15, CHUNK_HEIGHT - 1)
	if y_max < SEA_LEVEL:
		y_max = SEA_LEVEL

	# ============================================================
	# Convertir en PackedByteArray pour accès rapide dans le meshing
	# ============================================================
	var packed_blocks: PackedByteArray = PackedByteArray()
	packed_blocks.resize(CHUNK_SIZE * CHUNK_SIZE * CHUNK_HEIGHT)
	for bx in range(CHUNK_SIZE):
		var x_off: int = bx * CHUNK_SIZE * CHUNK_HEIGHT
		for bz in range(CHUNK_SIZE):
			var xz_off: int = x_off + bz * CHUNK_HEIGHT
			for by in range(y_min, y_max + 1):
				var bt: int = blocks[bx][bz][by]
				if bt != 0:
					packed_blocks[xz_off + by] = bt

	return {"position": chunk_pos, "blocks": packed_blocks, "y_min": y_min, "y_max": y_max}

func _place_all_vegetation(blocks: Array, heightmap: Array, biome_map: Array, chunk_pos: Vector3i):
	"""Placer toute la végétation — les arbres ont accès au chunk entier pour leurs couronnes"""
	
	for x in range(CHUNK_SIZE):
		for z in range(CHUNK_SIZE):
			var height = heightmap[x][z]
			var biome = biome_map[x][z]
			var wx = chunk_pos.x * CHUNK_SIZE + x
			var wz = chunk_pos.z * CHUNK_SIZE + z
			
			if height >= CHUNK_HEIGHT - 20 or height < SEA_LEVEL - 5:
				continue
			
			match biome:
				0:  # DESERT — Cactus (pas besoin de 3D)
					if _hash_2d(wx, wz, 19) < 2:
						var h = 2 + _hash_2d(wx, wz, 3)
						for i in range(h):
							if height + i < CHUNK_HEIGHT:
								blocks[x][z][height + i] = BlockRegistry.BlockType.CACTUS
				
				1:  # FOREST — Chênes denses
					if _hash_2d(wx, wz, 9) < 1:  # ~11% density
						_place_oak_tree(blocks, x, z, height, wx, wz)
				
				2:  # MOUNTAIN — Pins (seulement sous la neige)
					if height < 120 and _hash_2d(wx, wz, 15) < 1:
						_place_pine_tree(blocks, x, z, height, wx, wz)
				
				3:  # PLAINS — Bouleaux épars
					if _hash_2d(wx, wz, 25) < 1:  # ~4% density
						_place_birch_tree(blocks, x, z, height, wx, wz)

func _place_oak_tree(blocks: Array, x: int, z: int, ground_y: int, wx: int = 0, wz: int = 0):
	"""
	Chêne classique style Minecraft :
	- Tronc : 4-6 blocs de WOOD
	- Couronne : 2 couches de 5x5 (coins enlevés) + 2 couches de 3x3
	"""
	var trunk_height = 4 + _hash_2d(wx * 7, wz * 13, 3)  # 4-6
	
	# Vérifier qu'on a la place (marge du chunk pour la couronne)
	if x < TREE_MARGIN or x >= CHUNK_SIZE - TREE_MARGIN:
		return
	if z < TREE_MARGIN or z >= CHUNK_SIZE - TREE_MARGIN:
		return
	if ground_y + trunk_height + 4 >= CHUNK_HEIGHT:
		return
	
	# --- Tronc ---
	for i in range(trunk_height):
		blocks[x][z][ground_y + i] = BlockRegistry.BlockType.WOOD
	
	# --- Couronne ---
	var crown_base = ground_y + trunk_height - 2  # Commence 2 blocs sous le sommet du tronc
	
	# Couche 0 et 1 : 5x5 avec coins enlevés
	for layer in range(2):
		var y = crown_base + layer
		if y >= CHUNK_HEIGHT:
			continue
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var nx = x + dx
				var nz = z + dz
				# Enlever les 4 coins
				if abs(dx) == 2 and abs(dz) == 2:
					continue
				if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
					# Ne pas écraser le tronc ou d'autres blocs solides
					if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
						blocks[nx][nz][y] = BlockRegistry.BlockType.LEAVES
	
	# Couche 2 et 3 : 3x3
	for layer in range(2, 4):
		var y = crown_base + layer
		if y >= CHUNK_HEIGHT:
			continue
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var nx = x + dx
				var nz = z + dz
				# Enlever les coins de la couche du haut
				if layer == 3 and abs(dx) == 1 and abs(dz) == 1:
					continue
				if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
					if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
						blocks[nx][nz][y] = BlockRegistry.BlockType.LEAVES

func _place_birch_tree(blocks: Array, x: int, z: int, ground_y: int, wx: int = 0, wz: int = 0):
	"""
	Bouleau (plaine) — plus fin et plus élégant :
	- Tronc : 5-7 blocs
	- Couronne : 3x3x2 + 1x1 au sommet
	"""
	var trunk_height = 5 + _hash_2d(wx * 11, wz * 7, 3)  # 5-7
	
	if x < 2 or x >= CHUNK_SIZE - 2:
		return
	if z < 2 or z >= CHUNK_SIZE - 2:
		return
	if ground_y + trunk_height + 3 >= CHUNK_HEIGHT:
		return
	
	# --- Tronc ---
	for i in range(trunk_height):
		blocks[x][z][ground_y + i] = BlockRegistry.BlockType.WOOD
	
	# --- Couronne --- 
	var crown_base = ground_y + trunk_height - 1
	
	# Couche 0 et 1 : 3x3
	for layer in range(2):
		var y = crown_base + layer
		if y >= CHUNK_HEIGHT:
			continue
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var nx = x + dx
				var nz = z + dz
				if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
					if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
						blocks[nx][nz][y] = BlockRegistry.BlockType.LEAVES
	
	# Couche 2 : juste le bloc central (pointe)
	var top_y = crown_base + 2
	if top_y < CHUNK_HEIGHT:
		if blocks[x][z][top_y] == BlockRegistry.BlockType.AIR:
			blocks[x][z][top_y] = BlockRegistry.BlockType.LEAVES

func _place_pine_tree(blocks: Array, x: int, z: int, ground_y: int, wx: int = 0, wz: int = 0):
	"""
	Pin (montagne) — forme conique :
	- Tronc : 6-9 blocs
	- Couronne : alternance de couches 5x5 et 3x3, se réduisant vers le haut
	"""
	var trunk_height = 6 + _hash_2d(wx * 5, wz * 17, 4)  # 6-9
	
	if x < TREE_MARGIN or x >= CHUNK_SIZE - TREE_MARGIN:
		return
	if z < TREE_MARGIN or z >= CHUNK_SIZE - TREE_MARGIN:
		return
	if ground_y + trunk_height + 5 >= CHUNK_HEIGHT:
		return
	
	# --- Tronc ---
	for i in range(trunk_height):
		blocks[x][z][ground_y + i] = BlockRegistry.BlockType.WOOD
	
	# --- Couronne conique ---
	# On part du bas de la couronne (large) vers le haut (étroit)
	var crown_start = ground_y + trunk_height - 4  # Commence 4 blocs sous le sommet
	
	# Couche 0 : croix 5x5 (bas de la couronne)
	_place_leaf_layer_cross(blocks, x, z, crown_start, 2)
	
	# Couche 1 : 3x3
	_place_leaf_layer_square(blocks, x, z, crown_start + 1, 1)
	
	# Couche 2 : croix 5x5
	_place_leaf_layer_cross(blocks, x, z, crown_start + 2, 2)
	
	# Couche 3 : 3x3
	_place_leaf_layer_square(blocks, x, z, crown_start + 3, 1)
	
	# Couche 4 : croix 3x3
	_place_leaf_layer_cross(blocks, x, z, crown_start + 4, 1)
	
	# Couche 5 : pointe (1 bloc)
	var tip_y = crown_start + 5
	if tip_y < CHUNK_HEIGHT:
		if blocks[x][z][tip_y] == BlockRegistry.BlockType.AIR:
			blocks[x][z][tip_y] = BlockRegistry.BlockType.LEAVES

func _place_leaf_layer_cross(blocks: Array, cx: int, cz: int, y: int, radius: int):
	"""Placer une couche de feuilles en forme de croix (+)"""
	if y < 0 or y >= CHUNK_HEIGHT:
		return
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			# Forme de croix : exclure les coins au-delà de distance Manhattan
			if abs(dx) + abs(dz) > radius:
				continue
			var nx = cx + dx
			var nz = cz + dz
			if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
				if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
					blocks[nx][nz][y] = BlockRegistry.BlockType.LEAVES

func _place_leaf_layer_square(blocks: Array, cx: int, cz: int, y: int, radius: int):
	"""Placer une couche de feuilles en carré plein"""
	if y < 0 or y >= CHUNK_HEIGHT:
		return
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var nx = cx + dx
			var nz = cz + dz
			if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
				if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
					blocks[nx][nz][y] = BlockRegistry.BlockType.LEAVES

# ============================================================
# TERRAIN (identique à v6.1)
# ============================================================

func _get_continuous_height(noise: float, elevation: float) -> int:
	var base_height = SEA_LEVEL - 2.0 + noise * 10.0
	var hill_factor = _smoothstep(0.25, 0.55, elevation)
	var hill_height = noise * 22.0 * hill_factor
	var mountain_factor = _smoothstep(0.5, 0.8, elevation)
	var mountain_noise = pow(noise, 1.8)
	var mountain_height = mountain_noise * 80.0 * mountain_factor
	var total = base_height + hill_height + mountain_height
	return int(clampf(total, 5.0, CHUNK_HEIGHT - 20.0))

func _get_biome(temp: float, humid: float) -> int:
	if temp > 0.65 and humid < 0.35:
		return 0  # DESERT
	elif temp > 0.45 and humid > 0.55:
		return 1  # FOREST
	elif temp < 0.35:
		return 2  # MOUNTAIN
	else:
		return 3  # PLAINS

func _is_cave(x: int, y: int, z: int, n1: FastNoiseLite, n2: FastNoiseLite, n3: FastNoiseLite) -> bool:
	var v1 = n1.get_noise_3d(x, y, z)
	var v2 = n2.get_noise_3d(x, y, z)
	var v3 = n3.get_noise_3d(x, y, z)
	var combined = abs(v1) * abs(v2)
	var large_cave = abs(v3) < 0.12
	var depth = 1.0 - (float(y) / SEA_LEVEL)
	var threshold = 0.02 + depth * 0.04
	return combined < threshold or large_cave

func _get_block(y: int, surface: int, biome: int) -> int:
	var depth = surface - y
	
	if y < 5:
		return BlockRegistry.BlockType.STONE
	if depth > 5 or y < SEA_LEVEL - 10:
		return BlockRegistry.BlockType.STONE
	
	match biome:
		0:
			return BlockRegistry.BlockType.SAND if depth <= 4 else BlockRegistry.BlockType.STONE
		1:
			if depth == 1:
				return BlockRegistry.BlockType.DARK_GRASS
			elif depth <= 4:
				return BlockRegistry.BlockType.DIRT
			else:
				return BlockRegistry.BlockType.STONE
		2:
			if depth == 1 and surface > 130:
				return BlockRegistry.BlockType.SNOW
			elif depth == 1 and surface > 100:
				return BlockRegistry.BlockType.GRAVEL
			elif depth <= 3:
				return BlockRegistry.BlockType.STONE
			elif depth <= 6:
				return BlockRegistry.BlockType.GRAVEL
			else:
				return BlockRegistry.BlockType.STONE
		3:
			if depth == 1:
				return BlockRegistry.BlockType.GRASS
			elif depth <= 4:
				return BlockRegistry.BlockType.DIRT
			else:
				return BlockRegistry.BlockType.STONE
		_:
			return BlockRegistry.BlockType.STONE

func _hash_2d(x: int, z: int, modulo: int) -> int:
	var hash_val = abs((x * 374761393 + z * 668265263) >> 13)
	return hash_val % modulo

func _on_chunk_generated(chunk_data: Dictionary):
	emit_signal("chunk_generated", chunk_data)

func get_queue_size() -> int:
	queue_mutex.lock()
	var size = generation_queue.size()
	queue_mutex.unlock()
	return size

func is_generating(chunk_pos: Vector3i) -> bool:
	queue_mutex.lock()
	var gen = active_generations.has(chunk_pos)
	queue_mutex.unlock()
	return gen

func clear_queue():
	queue_mutex.lock()
	generation_queue.clear()
	queue_mutex.unlock()

func _exit_tree():
	should_exit = true
	for thread in thread_pool:
		if thread.is_started():
			thread.wait_to_finish()
