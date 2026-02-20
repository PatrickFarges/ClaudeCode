extends Node
class_name ChunkGenerator

# v7.0 : Bois par biome, nouveaux minerais, variantes pierre, blocs naturels
# - Foret : chenes + chenes noirs
# - Plaines : bouleaux (BIRCH_LOG + BIRCH_LEAVES)
# - Montagne : sapins (SPRUCE_LOG + SPRUCE_LEAVES) + glace
# - Desert : cactus + acacias rares
# - Souterrain : deepslate, andesite/granite/diorite veins, diamant/cuivre

signal chunk_generated(chunk_data: Dictionary)

const MAX_THREADS = 4
const CHUNK_SIZE = 16
const CHUNK_HEIGHT = 256
const SEA_LEVEL = 64
const TREE_MARGIN = 3  # Marge depuis le bord du chunk (evite couronnes coupees)

var thread_pool: Array[Thread] = []
var generation_queue: Array = []
var active_generations: Dictionary = {}
var queue_mutex: Mutex = Mutex.new()
var should_exit: bool = false
var world_seed: int = 0
var _structure_placements: Array = []

func set_world_seed(seed_value: int):
	world_seed = seed_value

func set_structure_placements(data: Array):
	_structure_placements = data

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

	# Noise pour les variantes de pierre souterraine
	var stone_var_noise = FastNoiseLite.new()
	stone_var_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	stone_var_noise.seed = seed_base + 8888
	stone_var_noise.frequency = 0.06

	# ============================================================
	# PASSE 1 : Generer le terrain + stocker heightmap et biome_map
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
	# PASSE 1.5 : Variantes de pierre souterraine + minerais
	# ============================================================
	for ox in range(CHUNK_SIZE):
		for oz in range(CHUNK_SIZE):
			var owx = chunk_pos.x * CHUNK_SIZE + ox
			var owz = chunk_pos.z * CHUNK_SIZE + oz
			for oy in range(2, 80):
				if blocks[ox][oz][oy] != BlockRegistry.BlockType.STONE:
					continue

				# Deepslate en profondeur (y < 16)
				if oy < 16:
					blocks[ox][oz][oy] = BlockRegistry.BlockType.DEEPSLATE

				# Variantes de pierre en veines (y < 80)
				var sv = stone_var_noise.get_noise_3d(owx, oy, owz)
				if oy < 80 and blocks[ox][oz][oy] == BlockRegistry.BlockType.STONE:
					if sv > 0.45 and sv < 0.55:
						blocks[ox][oz][oy] = BlockRegistry.BlockType.ANDESITE
					elif sv > 0.6 and sv < 0.68:
						blocks[ox][oz][oy] = BlockRegistry.BlockType.GRANITE
					elif sv > 0.72 and sv < 0.78:
						blocks[ox][oz][oy] = BlockRegistry.BlockType.DIORITE

				# Minerais pres des grottes
				if blocks[ox][oz][oy] in [BlockRegistry.BlockType.STONE, BlockRegistry.BlockType.DEEPSLATE, BlockRegistry.BlockType.ANDESITE, BlockRegistry.BlockType.GRANITE, BlockRegistry.BlockType.DIORITE]:
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
						if oy < 16 and ore_val > 0.92:
							blocks[ox][oz][oy] = BlockRegistry.BlockType.DIAMOND_ORE
						elif oy < 25 and ore_val > 0.8:
							blocks[ox][oz][oy] = BlockRegistry.BlockType.GOLD_ORE
						elif oy < 40 and ore_val > 0.7:
							blocks[ox][oz][oy] = BlockRegistry.BlockType.IRON_ORE
						elif oy < 50 and ore_val > 0.55:
							blocks[ox][oz][oy] = BlockRegistry.BlockType.COPPER_ORE
						elif ore_val > 0.6:
							blocks[ox][oz][oy] = BlockRegistry.BlockType.COAL_ORE

	# ============================================================
	# PASSE 1.7 : Mousse sur les murs de grottes (rare)
	# ============================================================
	for ox in range(CHUNK_SIZE):
		for oz in range(CHUNK_SIZE):
			var owx = chunk_pos.x * CHUNK_SIZE + ox
			var owz = chunk_pos.z * CHUNK_SIZE + oz
			for oy in range(10, 50):
				if blocks[ox][oz][oy] == BlockRegistry.BlockType.STONE and _hash_2d(owx + oy * 31, owz + oy * 17, 40) < 1:
					# Verifier adjacent a une grotte
					var adj_air = false
					if oy > 0 and blocks[ox][oz][oy - 1] == BlockRegistry.BlockType.AIR:
						adj_air = true
					elif oy < CHUNK_HEIGHT - 1 and blocks[ox][oz][oy + 1] == BlockRegistry.BlockType.AIR:
						adj_air = true
					if adj_air:
						blocks[ox][oz][oy] = BlockRegistry.BlockType.MOSS_BLOCK

	# ============================================================
	# PASSE 2 : Placer les arbres et vegetation (sur le chunk entier)
	# ============================================================
	_place_all_vegetation(blocks, heightmap, biome_map, chunk_pos)

	# ============================================================
	# PASSE 3 : Remplissage eau sous SEA_LEVEL + glace en montagne
	# ============================================================
	for wx2 in range(CHUNK_SIZE):
		for wz2 in range(CHUNK_SIZE):
			var biome = biome_map[wx2][wz2]
			for wy in range(SEA_LEVEL, 0, -1):
				if blocks[wx2][wz2][wy] == BlockRegistry.BlockType.AIR:
					blocks[wx2][wz2][wy] = BlockRegistry.BlockType.WATER
					# Glace en surface dans les biomes froids
					if wy == SEA_LEVEL and biome == 2:
						blocks[wx2][wz2][wy] = BlockRegistry.BlockType.ICE
				elif blocks[wx2][wz2][wy] != BlockRegistry.BlockType.WATER:
					break

	# ============================================================
	# PASSE 3.5 : Argile pres de l'eau
	# ============================================================
	for cx in range(CHUNK_SIZE):
		for cz in range(CHUNK_SIZE):
			var cwx = chunk_pos.x * CHUNK_SIZE + cx
			var cwz = chunk_pos.z * CHUNK_SIZE + cz
			# Argile sous les blocs adjacents a l'eau
			for cy in range(SEA_LEVEL - 3, SEA_LEVEL):
				if blocks[cx][cz][cy] in [BlockRegistry.BlockType.SAND, BlockRegistry.BlockType.DIRT]:
					# Verifier s'il y a de l'eau a proximite
					var near_water = false
					if cy < CHUNK_HEIGHT - 1 and blocks[cx][cz][cy + 1] == BlockRegistry.BlockType.WATER:
						near_water = true
					if near_water and _hash_2d(cwx + cy * 7, cwz + cy * 13, 5) < 2:
						blocks[cx][cz][cy] = BlockRegistry.BlockType.CLAY

	# ============================================================
	# PASSE 4 : Appliquer les structures predefinies
	# ============================================================
	if _structure_placements.size() > 0:
		var struct_bounds = _apply_structures(blocks, chunk_pos)
		if struct_bounds.x < y_min:
			y_min = struct_bounds.x
		if struct_bounds.y > y_max:
			y_max = struct_bounds.y

	# Ajuster y_max pour les couronnes d'arbres et l'eau
	if y_max > 0:
		y_max = mini(y_max + 15, CHUNK_HEIGHT - 1)
	if y_max < SEA_LEVEL:
		y_max = SEA_LEVEL

	# ============================================================
	# Convertir en PackedByteArray pour acces rapide dans le meshing
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
	for x in range(CHUNK_SIZE):
		for z in range(CHUNK_SIZE):
			var height = heightmap[x][z]
			var biome = biome_map[x][z]
			var wx = chunk_pos.x * CHUNK_SIZE + x
			var wz = chunk_pos.z * CHUNK_SIZE + z

			if height >= CHUNK_HEIGHT - 20 or height < SEA_LEVEL - 5:
				continue

			match biome:
				0:  # DESERT — Cactus espacés + acacias rares
					if _hash_2d(wx, wz, 150) < 1:  # ~0.7% — cactus bien espacés
						var h = 1 + _hash_2d(wx, wz, 3)  # 1-3 blocs de haut
						for i in range(h):
							if height + i < CHUNK_HEIGHT:
								blocks[x][z][height + i] = BlockRegistry.BlockType.CACTUS
					elif _hash_2d(wx, wz, 40) < 1:  # ~2.5% acacia (plus d'arbres)
						_place_acacia_tree(blocks, x, z, height, wx, wz)

				1:  # FOREST — Chenes + chenes noirs
					if _hash_2d(wx, wz, 9) < 1:  # ~11% density
						if _hash_2d(wx * 3, wz * 5, 10) < 3:  # 30% dark oak
							_place_dark_oak_tree(blocks, x, z, height, wx, wz)
						else:
							_place_oak_tree(blocks, x, z, height, wx, wz)
					# Podzol en foret dense (~15%)
					if height > SEA_LEVEL and _hash_2d(wx + 7, wz + 3, 20) < 3:
						if blocks[x][z][height - 1] == BlockRegistry.BlockType.DARK_GRASS:
							blocks[x][z][height - 1] = BlockRegistry.BlockType.PODZOL

				2:  # MOUNTAIN — Sapins (seulement sous la neige)
					if height < 120 and _hash_2d(wx, wz, 15) < 1:
						_place_pine_tree(blocks, x, z, height, wx, wz)

				3:  # PLAINS — Bouleaux epars
					if _hash_2d(wx, wz, 25) < 1:  # ~4% density
						_place_birch_tree(blocks, x, z, height, wx, wz)

func _place_oak_tree(blocks: Array, x: int, z: int, ground_y: int, wx: int = 0, wz: int = 0):
	var trunk_height = 4 + _hash_2d(wx * 7, wz * 13, 3)  # 4-6

	if x < TREE_MARGIN or x >= CHUNK_SIZE - TREE_MARGIN:
		return
	if z < TREE_MARGIN or z >= CHUNK_SIZE - TREE_MARGIN:
		return
	if ground_y + trunk_height + 4 >= CHUNK_HEIGHT:
		return

	for i in range(trunk_height):
		blocks[x][z][ground_y + i] = BlockRegistry.BlockType.WOOD

	var crown_base = ground_y + trunk_height - 2

	for layer in range(2):
		var y = crown_base + layer
		if y >= CHUNK_HEIGHT:
			continue
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var nx = x + dx
				var nz = z + dz
				if abs(dx) == 2 and abs(dz) == 2:
					continue
				if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
					if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
						blocks[nx][nz][y] = BlockRegistry.BlockType.LEAVES

	for layer in range(2, 4):
		var y = crown_base + layer
		if y >= CHUNK_HEIGHT:
			continue
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var nx = x + dx
				var nz = z + dz
				if layer == 3 and abs(dx) == 1 and abs(dz) == 1:
					continue
				if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
					if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
						blocks[nx][nz][y] = BlockRegistry.BlockType.LEAVES

func _place_dark_oak_tree(blocks: Array, x: int, z: int, ground_y: int, wx: int = 0, wz: int = 0):
	"""Chene noir — similaire au chene mais avec DARK_OAK_LOG + DARK_OAK_LEAVES"""
	var trunk_height = 4 + _hash_2d(wx * 7, wz * 13, 3)

	if x < TREE_MARGIN or x >= CHUNK_SIZE - TREE_MARGIN:
		return
	if z < TREE_MARGIN or z >= CHUNK_SIZE - TREE_MARGIN:
		return
	if ground_y + trunk_height + 4 >= CHUNK_HEIGHT:
		return

	for i in range(trunk_height):
		blocks[x][z][ground_y + i] = BlockRegistry.BlockType.DARK_OAK_LOG

	var crown_base = ground_y + trunk_height - 2

	for layer in range(2):
		var y = crown_base + layer
		if y >= CHUNK_HEIGHT:
			continue
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				if abs(dx) == 2 and abs(dz) == 2:
					continue
				var nx = x + dx
				var nz = z + dz
				if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
					if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
						blocks[nx][nz][y] = BlockRegistry.BlockType.DARK_OAK_LEAVES

	for layer in range(2, 4):
		var y = crown_base + layer
		if y >= CHUNK_HEIGHT:
			continue
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				if layer == 3 and abs(dx) == 1 and abs(dz) == 1:
					continue
				var nx = x + dx
				var nz = z + dz
				if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
					if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
						blocks[nx][nz][y] = BlockRegistry.BlockType.DARK_OAK_LEAVES

func _place_birch_tree(blocks: Array, x: int, z: int, ground_y: int, wx: int = 0, wz: int = 0):
	"""Bouleau (plaine) — BIRCH_LOG + BIRCH_LEAVES"""
	var trunk_height = 5 + _hash_2d(wx * 11, wz * 7, 3)  # 5-7

	if x < 2 or x >= CHUNK_SIZE - 2:
		return
	if z < 2 or z >= CHUNK_SIZE - 2:
		return
	if ground_y + trunk_height + 3 >= CHUNK_HEIGHT:
		return

	for i in range(trunk_height):
		blocks[x][z][ground_y + i] = BlockRegistry.BlockType.BIRCH_LOG

	var crown_base = ground_y + trunk_height - 1

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
						blocks[nx][nz][y] = BlockRegistry.BlockType.BIRCH_LEAVES

	var top_y = crown_base + 2
	if top_y < CHUNK_HEIGHT:
		if blocks[x][z][top_y] == BlockRegistry.BlockType.AIR:
			blocks[x][z][top_y] = BlockRegistry.BlockType.BIRCH_LEAVES

func _place_pine_tree(blocks: Array, x: int, z: int, ground_y: int, wx: int = 0, wz: int = 0):
	"""Pin (montagne) — SPRUCE_LOG + SPRUCE_LEAVES, forme conique"""
	var trunk_height = 6 + _hash_2d(wx * 5, wz * 17, 4)  # 6-9

	if x < TREE_MARGIN or x >= CHUNK_SIZE - TREE_MARGIN:
		return
	if z < TREE_MARGIN or z >= CHUNK_SIZE - TREE_MARGIN:
		return
	if ground_y + trunk_height + 5 >= CHUNK_HEIGHT:
		return

	for i in range(trunk_height):
		blocks[x][z][ground_y + i] = BlockRegistry.BlockType.SPRUCE_LOG

	var crown_start = ground_y + trunk_height - 4

	_place_leaf_layer_cross(blocks, x, z, crown_start, 2, BlockRegistry.BlockType.SPRUCE_LEAVES)
	_place_leaf_layer_square(blocks, x, z, crown_start + 1, 1, BlockRegistry.BlockType.SPRUCE_LEAVES)
	_place_leaf_layer_cross(blocks, x, z, crown_start + 2, 2, BlockRegistry.BlockType.SPRUCE_LEAVES)
	_place_leaf_layer_square(blocks, x, z, crown_start + 3, 1, BlockRegistry.BlockType.SPRUCE_LEAVES)
	_place_leaf_layer_cross(blocks, x, z, crown_start + 4, 1, BlockRegistry.BlockType.SPRUCE_LEAVES)

	var tip_y = crown_start + 5
	if tip_y < CHUNK_HEIGHT:
		if blocks[x][z][tip_y] == BlockRegistry.BlockType.AIR:
			blocks[x][z][tip_y] = BlockRegistry.BlockType.SPRUCE_LEAVES

func _place_acacia_tree(blocks: Array, x: int, z: int, ground_y: int, wx: int = 0, wz: int = 0):
	"""Acacia (desert) — tronc penche, couronne plate"""
	var trunk_height = 4 + _hash_2d(wx * 3, wz * 11, 3)  # 4-6

	if x < TREE_MARGIN or x >= CHUNK_SIZE - TREE_MARGIN:
		return
	if z < TREE_MARGIN or z >= CHUNK_SIZE - TREE_MARGIN:
		return
	if ground_y + trunk_height + 3 >= CHUNK_HEIGHT:
		return

	# Tronc droit
	for i in range(trunk_height):
		blocks[x][z][ground_y + i] = BlockRegistry.BlockType.ACACIA_LOG

	# Couronne plate (2 couches, 5x5 puis 3x3)
	var crown_y = ground_y + trunk_height
	for layer in range(2):
		var y = crown_y + layer
		if y >= CHUNK_HEIGHT:
			continue
		var radius = 2 - layer
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if abs(dx) == radius and abs(dz) == radius:
					continue
				var nx = x + dx
				var nz = z + dz
				if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
					if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
						blocks[nx][nz][y] = BlockRegistry.BlockType.ACACIA_LEAVES

func _place_leaf_layer_cross(blocks: Array, cx: int, cz: int, y: int, radius: int, leaf_type: int = BlockRegistry.BlockType.LEAVES):
	if y < 0 or y >= CHUNK_HEIGHT:
		return
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if abs(dx) + abs(dz) > radius:
				continue
			var nx = cx + dx
			var nz = cz + dz
			if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
				if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
					blocks[nx][nz][y] = leaf_type

func _place_leaf_layer_square(blocks: Array, cx: int, cz: int, y: int, radius: int, leaf_type: int = BlockRegistry.BlockType.LEAVES):
	if y < 0 or y >= CHUNK_HEIGHT:
		return
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var nx = cx + dx
			var nz = cz + dz
			if nx >= 0 and nx < CHUNK_SIZE and nz >= 0 and nz < CHUNK_SIZE:
				if blocks[nx][nz][y] == BlockRegistry.BlockType.AIR:
					blocks[nx][nz][y] = leaf_type

# ============================================================
# STRUCTURES — Patch les blocs du chunk avec les structures placees
# ============================================================

func _apply_structures(blocks: Array, chunk_pos: Vector3i) -> Vector2i:
	var new_y_min: int = CHUNK_HEIGHT
	var new_y_max: int = 0

	var chunk_min_x: int = chunk_pos.x * CHUNK_SIZE
	var chunk_min_z: int = chunk_pos.z * CHUNK_SIZE
	var chunk_max_x: int = chunk_min_x + CHUNK_SIZE - 1
	var chunk_max_z: int = chunk_min_z + CHUNK_SIZE - 1

	for placement in _structure_placements:
		if placement.aabb_max_x < chunk_min_x or placement.aabb_min_x > chunk_max_x:
			continue
		if placement.aabb_max_z < chunk_min_z or placement.aabb_min_z > chunk_max_z:
			continue

		var s_pos: Vector3i = placement.position
		var s_blocks: PackedByteArray = placement.blocks
		var s_size_x: int = placement.size_x
		var s_size_y: int = placement.size_y
		var s_size_z: int = placement.size_z

		var ox_min: int = maxi(chunk_min_x, s_pos.x)
		var ox_max: int = mini(chunk_max_x, s_pos.x + s_size_x - 1)
		var oz_min: int = maxi(chunk_min_z, s_pos.z)
		var oz_max: int = mini(chunk_max_z, s_pos.z + s_size_z - 1)
		var oy_min: int = maxi(0, s_pos.y)
		var oy_max: int = mini(CHUNK_HEIGHT - 1, s_pos.y + s_size_y - 1)

		var sx_sz: int = s_size_x * s_size_z

		for wxx in range(ox_min, ox_max + 1):
			var lx: int = wxx - chunk_min_x
			var sx: int = wxx - s_pos.x
			for wzz in range(oz_min, oz_max + 1):
				var lz: int = wzz - chunk_min_z
				var sz: int = wzz - s_pos.z
				var base_idx: int = sz * s_size_x + sx
				for wy in range(oy_min, oy_max + 1):
					var sy: int = wy - s_pos.y
					var struct_idx: int = sy * sx_sz + base_idx
					var block_val: int = s_blocks[struct_idx]
					if block_val == 255:  # KEEP
						continue
					blocks[lx][lz][wy] = block_val
					if block_val != 0:
						if wy < new_y_min:
							new_y_min = wy
						if wy > new_y_max:
							new_y_max = wy

	return Vector2i(new_y_min, new_y_max)

# ============================================================
# TERRAIN
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
