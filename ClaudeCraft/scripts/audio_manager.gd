extends Node
class_name AudioManager

# ============================================================
# AUDIO MANAGER — Sons fichiers + ambiance procédurale
# ============================================================

const SAMPLE_RATE = 22050
const MIX_RATE = 22050

# Players audio réutilisables
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_3d_players: Array[AudioStreamPlayer3D] = []
var footstep_player: AudioStreamPlayer = null

# Paramètres
var master_volume: float = 1.0
var sfx_volume: float = 0.8
var ambient_volume: float = 0.7

# Pool sizes
const SFX_POOL_SIZE = 8
const SFX_3D_POOL_SIZE = 6

# Biome ambient
var current_biome: int = -1
var current_height: float = 64.0
var last_ambient_height: float = 64.0
var ambient_player_a: AudioStreamPlayer = null
var ambient_player_b: AudioStreamPlayer = null
var active_ambient: String = "a"
var crossfade_time: float = 0.0
var is_crossfading: bool = false
const CROSSFADE_DURATION = 2.0
var biome_check_timer: float = 0.0
const BIOME_CHECK_INTERVAL = 0.5
const HEIGHT_CHANGE_THRESHOLD = 15.0

# Noise pour détecter le biome (mêmes seeds que chunk_generator!)
var temp_noise: FastNoiseLite
var humid_noise: FastNoiseLite

# Constantes biome
const BIOME_DESERT = 0
const BIOME_FOREST = 1
const BIOME_MOUNTAIN = 2
const BIOME_PLAINS = 3

# ============================================================
# BANQUES DE SONS — Chargées au démarrage
# ============================================================

# Break sounds (casse de bloc)
var snd_break_stone: Array = []
var snd_break_wood: Array = []
var snd_break_dirt: Array = []
var snd_break_sand: Array = []
var snd_break_leaves: Array = []
var snd_break_snow: Array = []
var snd_break_default: Array = []

# Place sounds (placement de bloc)
var snd_place_stone: Array = []
var snd_place_wood: Array = []
var snd_place_sand: Array = []
var snd_place_snow: Array = []
var snd_place_default: Array = []

# Mining hit sounds (frappe de minage)
var snd_mine_stone: Array = []
var snd_mine_wood: Array = []
var snd_mine_dirt: Array = []
var snd_mine_sand: Array = []
var snd_mine_default: Array = []

# Footstep sounds (pas)
var snd_step_stone: Array = []
var snd_step_wood: Array = []
var snd_step_grass: Array = []
var snd_step_sand: Array = []
var snd_step_snow: Array = []
var snd_step_dirt: Array = []

# Metal sounds (ingots, furnace)
var snd_break_metal: Array = []
var snd_place_metal: Array = []
var snd_mine_metal: Array = []
var snd_step_metal: Array = []

# Eating sounds
var snd_eat: AudioStream = null

# UI sounds
var snd_ui_click: AudioStream = null
var snd_craft_success: AudioStream = null

# Forest ambient par heure du jour
var forest_ambient_by_hour: Array = []  # Array de [heure_debut, heure_fin, Array[AudioStream]]
var forest_current_hour_range: int = -1  # Index dans forest_ambient_by_hour
var day_night_cycle_node: Node = null

func _ready():
	add_to_group("audio_manager")
	_load_sound_banks()
	_create_audio_pools()
	call_deferred("_start_ambient")

func _load_sound_banks():
	# === Break sounds ===
	snd_break_stone = [
		load("res://Audio/stone-1.mp3"),
		load("res://Audio/stone-4.mp3"),
		load("res://Audio/stone-6.mp3"),
	]
	snd_break_wood = [
		load("res://Audio/wood-1.mp3"),
		load("res://Audio/wood-2.mp3"),
		load("res://Audio/wood-3.mp3"),
		load("res://Audio/wood-4.mp3"),
	]
	snd_break_dirt = [
		load("res://Audio/grass-2.mp3"),
		load("res://Audio/grass-4.mp3"),
		load("res://Audio/gravel-4.mp3"),
	]
	snd_break_sand = [
		load("res://Audio/u_scysdwddsp-sand-effect-254993.mp3"),
	]
	snd_break_leaves = [
		load("res://Audio/cloth1.ogg"),
		load("res://Audio/cloth2.ogg"),
		load("res://Audio/cloth3.ogg"),
		load("res://Audio/cloth4.ogg"),
	]
	snd_break_snow = [
		load("res://Audio/footstep_snow_000.ogg"),
		load("res://Audio/footstep_snow_001.ogg"),
		load("res://Audio/footstep_snow_002.ogg"),
	]
	snd_break_default = [
		load("res://Audio/impactGeneric_light_000.ogg"),
		load("res://Audio/impactGeneric_light_001.ogg"),
		load("res://Audio/impactGeneric_light_002.ogg"),
		load("res://Audio/impactGeneric_light_003.ogg"),
		load("res://Audio/impactGeneric_light_004.ogg"),
	]

	# === Place sounds ===
	snd_place_stone = [
		load("res://Audio/stone-1.mp3"),
	]
	snd_place_wood = [
		load("res://Audio/wood-1.mp3"),
		load("res://Audio/wood-2.mp3"),
	]
	snd_place_sand = [
		load("res://Audio/u_scysdwddsp-sand-effect-254993.mp3"),
	]
	snd_place_snow = [
		load("res://Audio/footstep_snow_000.ogg"),
	]
	snd_place_default = [
		load("res://Audio/impactGeneric_light_000.ogg"),
		load("res://Audio/impactGeneric_light_001.ogg"),
		load("res://Audio/impactGeneric_light_002.ogg"),
	]

	# === Mining hit sounds ===
	snd_mine_stone = [
		load("res://Audio/impactMining_000.ogg"),
		load("res://Audio/impactMining_001.ogg"),
		load("res://Audio/impactMining_002.ogg"),
		load("res://Audio/impactMining_003.ogg"),
		load("res://Audio/impactMining_004.ogg"),
	]
	snd_mine_wood = [
		load("res://Audio/impactPlank_medium_000.ogg"),
		load("res://Audio/impactPlank_medium_001.ogg"),
		load("res://Audio/impactPlank_medium_002.ogg"),
		load("res://Audio/impactPlank_medium_003.ogg"),
		load("res://Audio/impactPlank_medium_004.ogg"),
	]
	snd_mine_dirt = [
		load("res://Audio/impactSoft_medium_000.ogg"),
		load("res://Audio/impactSoft_medium_001.ogg"),
		load("res://Audio/impactSoft_medium_002.ogg"),
		load("res://Audio/impactSoft_medium_003.ogg"),
		load("res://Audio/impactSoft_medium_004.ogg"),
	]
	snd_mine_sand = [
		load("res://Audio/impactSoft_heavy_000.ogg"),
		load("res://Audio/impactSoft_heavy_001.ogg"),
		load("res://Audio/impactSoft_heavy_002.ogg"),
		load("res://Audio/impactSoft_heavy_003.ogg"),
		load("res://Audio/impactSoft_heavy_004.ogg"),
	]
	snd_mine_default = [
		load("res://Audio/impactGeneric_light_000.ogg"),
		load("res://Audio/impactGeneric_light_001.ogg"),
		load("res://Audio/impactGeneric_light_002.ogg"),
		load("res://Audio/impactGeneric_light_003.ogg"),
		load("res://Audio/impactGeneric_light_004.ogg"),
	]

	# === Footstep sounds ===
	snd_step_stone = [
		load("res://Audio/footstep_concrete_000.ogg"),
		load("res://Audio/footstep_concrete_001.ogg"),
		load("res://Audio/footstep_concrete_002.ogg"),
		load("res://Audio/footstep_concrete_003.ogg"),
		load("res://Audio/footstep_concrete_004.ogg"),
	]
	snd_step_wood = [
		load("res://Audio/footstep_wood_000.ogg"),
		load("res://Audio/footstep_wood_001.ogg"),
		load("res://Audio/footstep_wood_002.ogg"),
		load("res://Audio/footstep_wood_003.ogg"),
		load("res://Audio/footstep_wood_004.ogg"),
	]
	snd_step_grass = [
		load("res://Audio/footstep_grass_000.ogg"),
		load("res://Audio/footstep_grass_001.ogg"),
		load("res://Audio/footstep_grass_002.ogg"),
		load("res://Audio/footstep_grass_003.ogg"),
		load("res://Audio/footstep_grass_004.ogg"),
	]
	snd_step_sand = [
		load("res://Audio/footstep_carpet_000.ogg"),
		load("res://Audio/footstep_carpet_001.ogg"),
		load("res://Audio/footstep_carpet_002.ogg"),
		load("res://Audio/footstep_carpet_003.ogg"),
		load("res://Audio/footstep_carpet_004.ogg"),
	]
	snd_step_snow = [
		load("res://Audio/footstep_snow_000.ogg"),
		load("res://Audio/footstep_snow_001.ogg"),
		load("res://Audio/footstep_snow_002.ogg"),
		load("res://Audio/footstep_snow_003.ogg"),
		load("res://Audio/footstep_snow_004.ogg"),
	]
	snd_step_dirt = [
		load("res://Audio/footstep00.ogg"),
		load("res://Audio/footstep01.ogg"),
		load("res://Audio/footstep02.ogg"),
		load("res://Audio/footstep03.ogg"),
		load("res://Audio/footstep04.ogg"),
		load("res://Audio/footstep05.ogg"),
		load("res://Audio/footstep06.ogg"),
		load("res://Audio/footstep07.ogg"),
		load("res://Audio/footstep08.ogg"),
		load("res://Audio/footstep09.ogg"),
	]

	# === Metal sounds ===
	snd_break_metal = [
		load("res://Audio/impactMetal_heavy_000.ogg"),
		load("res://Audio/impactMetal_heavy_001.ogg"),
		load("res://Audio/impactMetal_heavy_002.ogg"),
		load("res://Audio/impactMetal_heavy_003.ogg"),
		load("res://Audio/impactMetal_heavy_004.ogg"),
	]
	snd_place_metal = [
		load("res://Audio/impactMetal_light_000.ogg"),
		load("res://Audio/impactMetal_light_001.ogg"),
		load("res://Audio/impactMetal_light_002.ogg"),
	]
	snd_mine_metal = [
		load("res://Audio/impactMetal_medium_000.ogg"),
		load("res://Audio/impactMetal_medium_001.ogg"),
		load("res://Audio/impactMetal_medium_002.ogg"),
		load("res://Audio/impactMetal_medium_003.ogg"),
		load("res://Audio/impactMetal_medium_004.ogg"),
	]
	snd_step_metal = [
		load("res://Audio/impactMetal_light_000.ogg"),
		load("res://Audio/impactMetal_light_001.ogg"),
		load("res://Audio/impactMetal_light_002.ogg"),
		load("res://Audio/impactMetal_light_003.ogg"),
		load("res://Audio/impactMetal_light_004.ogg"),
	]

	# === Eating sound ===
	snd_eat = load("res://Audio/eating-effect-254996.mp3")

	# === Forest ambient by hour ===
	forest_ambient_by_hour = [
		[5.0, 10.0, [load("res://Audio/Forest/5-10 matiné.mp3")]],
		[10.0, 12.0, [load("res://Audio/Forest/10-12 Aurore.mp3"), load("res://Audio/Forest/10-12 ambiance légère.mp3")]],
		[12.0, 15.0, [load("res://Audio/Forest/12-15 Midi1.mp3"), load("res://Audio/Forest/12-15 .mp3")]],
		[15.0, 16.0, [load("res://Audio/Forest/15-16 Wind and birds.mp3")]],
		[16.0, 18.0, [load("res://Audio/Forest/16-18 Après-midi1.mp3"), load("res://Audio/Forest/16-18 Après-midi and Birds.mp3")]],
		[18.0, 21.0, [load("res://Audio/Forest/18-21 crépuscule.mp3"), load("res://Audio/Forest/18-21 Wind forest.mp3")]],
		[21.0, 29.0, [load("res://Audio/Forest/21-5 night.mp3")]],  # 29 = 24+5, gère le wraparound
	]

	# === UI sounds ===
	snd_ui_click = load("res://Audio/metalClick.ogg")
	snd_craft_success = load("res://Audio/pling.mp3")

func _pick_random(bank: Array) -> AudioStream:
	if bank.is_empty():
		return null
	return bank[randi() % bank.size()]

# ============================================================
# POOL D'AUDIO PLAYERS
# ============================================================

func _create_audio_pools():
	for i in range(SFX_POOL_SIZE):
		var p = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		sfx_players.append(p)

	for i in range(SFX_3D_POOL_SIZE):
		var p = AudioStreamPlayer3D.new()
		p.bus = "Master"
		p.max_distance = 20.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		sfx_3d_players.append(p)

	ambient_player_a = AudioStreamPlayer.new()
	ambient_player_a.bus = "Master"
	add_child(ambient_player_a)

	ambient_player_b = AudioStreamPlayer.new()
	ambient_player_b.bus = "Master"
	ambient_player_b.volume_db = linear_to_db(0.001)
	add_child(ambient_player_b)

	footstep_player = AudioStreamPlayer.new()
	footstep_player.bus = "Master"
	add_child(footstep_player)

	temp_noise = FastNoiseLite.new()
	temp_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	temp_noise.seed = 9012
	temp_noise.frequency = 0.008

	humid_noise = FastNoiseLite.new()
	humid_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	humid_noise.seed = 3456
	humid_noise.frequency = 0.01

func _get_free_sfx() -> AudioStreamPlayer:
	for p in sfx_players:
		if not p.playing:
			return p
	return sfx_players[0]

func _get_free_sfx_3d() -> AudioStreamPlayer3D:
	for p in sfx_3d_players:
		if not p.playing:
			return p
	return sfx_3d_players[0]

# ============================================================
# API PUBLIQUE
# ============================================================

func play_break_sound(block_type: int, world_pos: Vector3):
	var stream = _get_break_sound(block_type)
	if not stream:
		return
	var p = _get_free_sfx_3d()
	p.stream = stream
	p.global_position = world_pos + Vector3(0.5, 0.5, 0.5)
	p.volume_db = linear_to_db(sfx_volume * master_volume)
	p.pitch_scale = randf_range(0.9, 1.1)
	p.play()

func play_place_sound(block_type: int, world_pos: Vector3):
	var stream = _get_place_sound(block_type)
	if not stream:
		return
	var p = _get_free_sfx_3d()
	p.stream = stream
	p.global_position = world_pos + Vector3(0.5, 0.5, 0.5)
	p.volume_db = linear_to_db(sfx_volume * master_volume * 0.7)
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()

func play_mining_hit(block_type: int, world_pos: Vector3):
	var stream = _get_mining_sound(block_type)
	if not stream:
		return
	var p = _get_free_sfx_3d()
	p.stream = stream
	p.global_position = world_pos + Vector3(0.5, 0.5, 0.5)
	p.volume_db = linear_to_db(sfx_volume * master_volume * 0.5)
	p.pitch_scale = randf_range(0.85, 1.15)
	p.play()

func play_footstep(surface_type: int):
	if footstep_player.playing:
		return
	var stream = _get_footstep_sound(surface_type)
	if not stream:
		return
	footstep_player.stream = stream
	footstep_player.volume_db = linear_to_db(sfx_volume * master_volume * 0.35)
	footstep_player.pitch_scale = randf_range(0.8, 1.2)
	footstep_player.play()

func play_ui_click():
	if not snd_ui_click:
		return
	var p = _get_free_sfx()
	p.stream = snd_ui_click
	p.volume_db = linear_to_db(sfx_volume * master_volume * 0.4)
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()

func play_craft_success():
	if not snd_craft_success:
		return
	var p = _get_free_sfx()
	p.stream = snd_craft_success
	p.volume_db = linear_to_db(sfx_volume * master_volume * 0.6)
	p.play()

func play_eat_sound():
	if not snd_eat:
		return
	var p = _get_free_sfx()
	p.stream = snd_eat
	p.volume_db = linear_to_db(sfx_volume * master_volume * 0.6)
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()

# ============================================================
# SÉLECTION DE SON PAR TYPE DE BLOC
# ============================================================

func _get_break_sound(block_type: int) -> AudioStream:
	match block_type:
		BlockRegistry.BlockType.STONE, BlockRegistry.BlockType.GRAVEL, \
		BlockRegistry.BlockType.BRICK, BlockRegistry.BlockType.SANDSTONE, \
		BlockRegistry.BlockType.COAL_ORE, BlockRegistry.BlockType.IRON_ORE, \
		BlockRegistry.BlockType.GOLD_ORE, BlockRegistry.BlockType.FURNACE:
			return _pick_random(snd_break_stone)
		BlockRegistry.BlockType.IRON_INGOT, BlockRegistry.BlockType.GOLD_INGOT:
			return _pick_random(snd_break_metal)
		BlockRegistry.BlockType.WOOD, BlockRegistry.BlockType.PLANKS, \
		BlockRegistry.BlockType.CRAFTING_TABLE, BlockRegistry.BlockType.STONE_TABLE, \
		BlockRegistry.BlockType.IRON_TABLE, BlockRegistry.BlockType.GOLD_TABLE:
			return _pick_random(snd_break_wood)
		BlockRegistry.BlockType.DIRT, BlockRegistry.BlockType.GRASS, \
		BlockRegistry.BlockType.DARK_GRASS:
			return _pick_random(snd_break_dirt)
		BlockRegistry.BlockType.SAND:
			return _pick_random(snd_break_sand)
		BlockRegistry.BlockType.LEAVES, BlockRegistry.BlockType.CACTUS:
			return _pick_random(snd_break_leaves)
		BlockRegistry.BlockType.SNOW:
			return _pick_random(snd_break_snow)
		_:
			return _pick_random(snd_break_default)

func _get_place_sound(block_type: int) -> AudioStream:
	match block_type:
		BlockRegistry.BlockType.STONE, BlockRegistry.BlockType.BRICK, \
		BlockRegistry.BlockType.SANDSTONE, BlockRegistry.BlockType.GRAVEL, \
		BlockRegistry.BlockType.COAL_ORE, BlockRegistry.BlockType.IRON_ORE, \
		BlockRegistry.BlockType.GOLD_ORE, BlockRegistry.BlockType.FURNACE:
			return _pick_random(snd_place_stone)
		BlockRegistry.BlockType.IRON_INGOT, BlockRegistry.BlockType.GOLD_INGOT:
			return _pick_random(snd_place_metal)
		BlockRegistry.BlockType.WOOD, BlockRegistry.BlockType.PLANKS, \
		BlockRegistry.BlockType.CRAFTING_TABLE, BlockRegistry.BlockType.STONE_TABLE, \
		BlockRegistry.BlockType.IRON_TABLE, BlockRegistry.BlockType.GOLD_TABLE:
			return _pick_random(snd_place_wood)
		BlockRegistry.BlockType.SAND:
			return _pick_random(snd_place_sand)
		BlockRegistry.BlockType.SNOW:
			return _pick_random(snd_place_snow)
		_:
			return _pick_random(snd_place_default)

func _get_mining_sound(block_type: int) -> AudioStream:
	match block_type:
		BlockRegistry.BlockType.STONE, BlockRegistry.BlockType.GRAVEL, \
		BlockRegistry.BlockType.BRICK, BlockRegistry.BlockType.SANDSTONE, \
		BlockRegistry.BlockType.COAL_ORE, BlockRegistry.BlockType.IRON_ORE, \
		BlockRegistry.BlockType.GOLD_ORE, BlockRegistry.BlockType.FURNACE:
			return _pick_random(snd_mine_stone)
		BlockRegistry.BlockType.IRON_INGOT, BlockRegistry.BlockType.GOLD_INGOT:
			return _pick_random(snd_mine_metal)
		BlockRegistry.BlockType.WOOD, BlockRegistry.BlockType.PLANKS, \
		BlockRegistry.BlockType.CRAFTING_TABLE, BlockRegistry.BlockType.STONE_TABLE, \
		BlockRegistry.BlockType.IRON_TABLE, BlockRegistry.BlockType.GOLD_TABLE:
			return _pick_random(snd_mine_wood)
		BlockRegistry.BlockType.DIRT, BlockRegistry.BlockType.GRASS, \
		BlockRegistry.BlockType.DARK_GRASS, BlockRegistry.BlockType.LEAVES, \
		BlockRegistry.BlockType.CACTUS:
			return _pick_random(snd_mine_dirt)
		BlockRegistry.BlockType.SAND, BlockRegistry.BlockType.SNOW:
			return _pick_random(snd_mine_sand)
		_:
			return _pick_random(snd_mine_default)

func _get_footstep_sound(surface_type: int) -> AudioStream:
	match surface_type:
		BlockRegistry.BlockType.STONE, BlockRegistry.BlockType.BRICK, \
		BlockRegistry.BlockType.GRAVEL, BlockRegistry.BlockType.SANDSTONE, \
		BlockRegistry.BlockType.COAL_ORE, BlockRegistry.BlockType.IRON_ORE, \
		BlockRegistry.BlockType.GOLD_ORE, BlockRegistry.BlockType.FURNACE:
			return _pick_random(snd_step_stone)
		BlockRegistry.BlockType.IRON_INGOT, BlockRegistry.BlockType.GOLD_INGOT:
			return _pick_random(snd_step_metal)
		BlockRegistry.BlockType.WOOD, BlockRegistry.BlockType.PLANKS, \
		BlockRegistry.BlockType.CRAFTING_TABLE, BlockRegistry.BlockType.STONE_TABLE, \
		BlockRegistry.BlockType.IRON_TABLE, BlockRegistry.BlockType.GOLD_TABLE:
			return _pick_random(snd_step_wood)
		BlockRegistry.BlockType.GRASS, BlockRegistry.BlockType.DARK_GRASS:
			return _pick_random(snd_step_grass)
		BlockRegistry.BlockType.SAND:
			return _pick_random(snd_step_sand)
		BlockRegistry.BlockType.SNOW:
			return _pick_random(snd_step_snow)
		_:
			return _pick_random(snd_step_dirt)

# ============================================================
# AMBIANCE PAR BIOME (procédurale — pas de fichiers d'ambiance en boucle)
# ============================================================

func _start_ambient():
	current_biome = BIOME_PLAINS
	var stream = _generate_biome_ambient(BIOME_PLAINS, 64.0)
	ambient_player_a.stream = stream
	ambient_player_a.volume_db = linear_to_db(ambient_volume * master_volume)
	ambient_player_a.play()
	ambient_player_a.finished.connect(_on_ambient_a_finished)
	ambient_player_b.finished.connect(_on_ambient_b_finished)

func _process(delta):
	_update_biome_ambient(delta)
	_handle_crossfade(delta)

func _update_biome_ambient(delta: float):
	biome_check_timer += delta
	if biome_check_timer < BIOME_CHECK_INTERVAL:
		return
	biome_check_timer = 0.0

	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var pos = player.global_position
	current_height = pos.y
	var biome = _detect_biome(pos.x, pos.z)

	if biome != current_biome:
		current_biome = biome
		last_ambient_height = pos.y
		forest_current_hour_range = -1
		_crossfade_to_biome(biome, pos.y)
	elif biome == BIOME_MOUNTAIN and abs(pos.y - last_ambient_height) > HEIGHT_CHANGE_THRESHOLD:
		last_ambient_height = pos.y
		_crossfade_to_biome(biome, pos.y)
	elif biome == BIOME_FOREST:
		# Vérifier si la plage horaire a changé
		var old_range = forest_current_hour_range
		_get_forest_ambient_for_current_hour()  # Met à jour forest_current_hour_range
		if old_range != forest_current_hour_range and old_range >= 0:
			_crossfade_to_biome(biome, pos.y)

func _detect_biome(world_x: float, world_z: float) -> int:
	var t = (temp_noise.get_noise_2d(world_x, world_z) + 1.0) / 2.0
	var h = (humid_noise.get_noise_2d(world_x, world_z) + 1.0) / 2.0

	if t > 0.65 and h < 0.35:
		return BIOME_DESERT
	elif t > 0.45 and h > 0.55:
		return BIOME_FOREST
	elif t < 0.35:
		return BIOME_MOUNTAIN
	else:
		return BIOME_PLAINS

func _crossfade_to_biome(biome: int, height: float):
	var new_stream = _generate_biome_ambient(biome, height)

	if active_ambient == "a":
		ambient_player_b.stream = new_stream
		ambient_player_b.volume_db = linear_to_db(0.001)
		ambient_player_b.play()
		active_ambient = "b"
	else:
		ambient_player_a.stream = new_stream
		ambient_player_a.volume_db = linear_to_db(0.001)
		ambient_player_a.play()
		active_ambient = "a"

	is_crossfading = true
	crossfade_time = 0.0

func _handle_crossfade(delta: float):
	if not is_crossfading:
		return

	crossfade_time += delta
	var progress = min(crossfade_time / CROSSFADE_DURATION, 1.0)
	var vol_target = ambient_volume * master_volume

	if active_ambient == "b":
		ambient_player_b.volume_db = linear_to_db(max(progress * vol_target, 0.001))
		ambient_player_a.volume_db = linear_to_db(max((1.0 - progress) * vol_target, 0.001))
	else:
		ambient_player_a.volume_db = linear_to_db(max(progress * vol_target, 0.001))
		ambient_player_b.volume_db = linear_to_db(max((1.0 - progress) * vol_target, 0.001))

	if progress >= 1.0:
		is_crossfading = false
		if active_ambient == "b":
			ambient_player_a.stop()
		else:
			ambient_player_b.stop()

func _on_ambient_a_finished():
	if active_ambient == "a" or is_crossfading:
		var stream = _generate_biome_ambient(current_biome, current_height)
		if stream:
			ambient_player_a.stream = stream
			ambient_player_a.play()

func _on_ambient_b_finished():
	if active_ambient == "b" or is_crossfading:
		var stream = _generate_biome_ambient(current_biome, current_height)
		if stream:
			ambient_player_b.stream = stream
			ambient_player_b.play()

func _generate_biome_ambient(biome: int, height: float) -> AudioStream:
	if biome == BIOME_FOREST:
		var forest_stream = _get_forest_ambient_for_current_hour()
		if forest_stream:
			return forest_stream
		return _generate_ambient_forest()
	match biome:
		BIOME_DESERT:
			return _generate_ambient_desert()
		BIOME_MOUNTAIN:
			return _generate_ambient_mountain(height)
		BIOME_PLAINS:
			return _generate_ambient_plains()
		_:
			return _generate_ambient_plains()

func _get_forest_ambient_for_current_hour() -> AudioStream:
	if not day_night_cycle_node:
		day_night_cycle_node = get_tree().get_first_node_in_group("day_night_cycle")
	if not day_night_cycle_node:
		return null
	var hour: float = day_night_cycle_node.get_hour()
	for i in range(forest_ambient_by_hour.size()):
		var entry = forest_ambient_by_hour[i]
		var h_start: float = entry[0]
		var h_end: float = entry[1]
		# Gestion wraparound nuit (21-5 stocké comme 21-29)
		var check_hour = hour if h_end <= 24.0 else (hour if hour >= h_start else hour + 24.0)
		if check_hour >= h_start and check_hour < h_end:
			forest_current_hour_range = i
			var streams: Array = entry[2]
			return streams[randi() % streams.size()]
	return null

# ============================================================
# GÉNÉRATION PROCÉDURALE DES AMBIANCES
# ============================================================

func _generate_ambient_forest() -> AudioStreamWAV:
	var duration = 8.0
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)

	var filtered = 0.0
	var filtered2 = 0.0
	var phase_offset = randf() * 100.0

	for i in range(samples):
		var t = float(i) / SAMPLE_RATE + phase_offset
		var noise = randf_range(-1.0, 1.0)

		filtered = filtered * 0.993 + noise * 0.007
		var wind = filtered * (sin(TAU * 0.12 * t) * 0.3 + 0.7)

		filtered2 = filtered2 * 0.98 + randf_range(-1.0, 1.0) * 0.02
		var rustle_env = max(0.0, sin(TAU * 0.25 * t + sin(TAU * 0.6 * t) * 3.0))
		var rustle = filtered2 * rustle_env * 0.6

		var bird = 0.0
		var cycle = fmod(t, 6.0)

		if cycle > 0.5 and cycle < 1.0:
			var bt = (cycle - 0.5) / 0.5
			var freq = 2800.0 - bt * 800.0
			bird += sin(TAU * freq * t) * (1.0 - bt) * 0.25

		if cycle > 2.5 and cycle < 3.0:
			var bt = (cycle - 2.5) / 0.5
			var trill = sin(TAU * 15.0 * t)
			bird += sin(TAU * 3200.0 * t) * max(0.0, trill) * (1.0 - bt) * 0.2

		if cycle > 4.0 and cycle < 4.15:
			bird += sin(TAU * 3500.0 * t) * 0.2
		elif cycle > 4.2 and cycle < 4.35:
			bird += sin(TAU * 2900.0 * t) * 0.18
		elif cycle > 4.5 and cycle < 4.65:
			bird += sin(TAU * 3500.0 * t) * 0.15

		var fade = min(t - phase_offset, 1.5) / 1.5
		fade = min(fade, 1.0) * min((duration - (t - phase_offset)) / 1.5, 1.0)
		fade = max(fade, 0.0)
		var sample_val = (wind * 0.7 + rustle + bird) * fade

		var sample_int = clampi(int(sample_val * 12000), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF

	return _make_wav(data)

func _generate_ambient_desert() -> AudioStreamWAV:
	var duration = 8.0
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)

	var filtered = 0.0
	var phase_offset = randf() * 100.0

	for i in range(samples):
		var t = float(i) / SAMPLE_RATE + phase_offset
		var noise = randf_range(-1.0, 1.0)

		filtered = filtered * 0.997 + noise * 0.003
		var wind = filtered * (sin(TAU * 0.05 * t) * 0.4 + 0.6)

		var whistle = 0.0
		var w_cycle = fmod(t, 8.0)
		if w_cycle > 3.0 and w_cycle < 5.0:
			var w_env = sin((w_cycle - 3.0) / 2.0 * PI)
			var w_freq = 500.0 + sin(TAU * 0.3 * t) * 150.0
			whistle = sin(TAU * w_freq * t) * w_env * 0.1

		var heat = sin(TAU * 45.0 * t + sin(TAU * 0.2 * t) * 3.0) * 0.08

		var real_t = t - phase_offset
		var fade = min(real_t / 2.0, 1.0) * min((duration - real_t) / 2.0, 1.0)
		fade = max(fade, 0.0)
		var sample_val = (wind * 0.8 + whistle + heat) * fade

		var sample_int = clampi(int(sample_val * 10000), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF

	return _make_wav(data)

func _generate_ambient_mountain(height: float) -> AudioStreamWAV:
	var duration = 8.0
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)

	var height_factor = clampf((height - 64.0) / 60.0, 0.0, 1.0)
	var filtered = 0.0
	var filtered_hi = 0.0
	var phase_offset = randf() * 100.0

	for i in range(samples):
		var t = float(i) / SAMPLE_RATE + phase_offset
		var noise = randf_range(-1.0, 1.0)

		var filter_c = 0.992 - height_factor * 0.008
		filtered = filtered * filter_c + noise * (1.0 - filter_c)
		var wind_mod = sin(TAU * 0.08 * t) * 0.15 + (0.5 + height_factor * 0.5)
		var wind = filtered * wind_mod

		var gust = 0.0
		var gust_interval = 4.0 - height_factor * 2.0
		var gust_cycle = fmod(t, gust_interval)
		if gust_cycle > 0.5 and gust_cycle < 2.0:
			var g_env = sin((gust_cycle - 0.5) / 1.5 * PI)
			gust = randf_range(-1.0, 1.0) * g_env * (0.3 + height_factor * 0.5)

		var whistle = 0.0
		if height_factor > 0.3:
			filtered_hi = filtered_hi * 0.95 + randf_range(-1.0, 1.0) * 0.05
			var w_mod = sin(TAU * 0.15 * t + sin(TAU * 0.08 * t) * 4.0) * 0.5 + 0.5
			whistle = filtered_hi * w_mod * (height_factor - 0.3) / 0.7 * 0.7
			var tonal = sin(TAU * (800.0 + sin(TAU * 0.2 * t) * 200.0) * t)
			whistle += tonal * w_mod * (height_factor - 0.3) / 0.7 * 0.08

		var rumble = sin(TAU * 25.0 * t + sin(TAU * 0.15 * t) * 8.0) * 0.12 * (0.5 + height_factor * 0.5)

		var real_t = t - phase_offset
		var fade = min(real_t / 1.0, 1.0) * min((duration - real_t) / 1.5, 1.0)
		fade = max(fade, 0.0)
		var sample_val = (wind + gust + whistle + rumble) * fade

		var sample_int = clampi(int(sample_val * 14000), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF

	return _make_wav(data)

func _generate_ambient_plains() -> AudioStreamWAV:
	var duration = 8.0
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)

	var filtered = 0.0
	var phase_offset = randf() * 100.0

	for i in range(samples):
		var t = float(i) / SAMPLE_RATE + phase_offset
		var noise = randf_range(-1.0, 1.0)

		filtered = filtered * 0.996 + noise * 0.004
		var breeze = filtered * (sin(TAU * 0.08 * t) * 0.3 + 0.55)

		var cricket = 0.0
		var c_cycle = fmod(t, 2.5)
		if c_cycle > 0.3 and c_cycle < 1.8:
			var c_env = sin((c_cycle - 0.3) / 1.5 * PI) * 0.5 + 0.5
			cricket = sin(TAU * 4400.0 * t) * sin(TAU * 5.5 * t) * c_env * 0.06

		var insect2 = 0.0
		var i_cycle = fmod(t + 1.3, 3.0)
		if i_cycle > 0.5 and i_cycle < 2.0:
			var i_env = sin((i_cycle - 0.5) / 1.5 * PI)
			insect2 = sin(TAU * 3800.0 * t) * sin(TAU * 7.0 * t) * i_env * 0.04

		var bird = 0.0
		var b_cycle = fmod(t, 7.0)
		if b_cycle > 4.0 and b_cycle < 4.4:
			var bt = (b_cycle - 4.0) / 0.4
			bird = sin(TAU * (2200.0 + bt * 400.0) * t) * (1.0 - bt) * 0.1

		var real_t = t - phase_offset
		var fade = min(real_t / 2.0, 1.0) * min((duration - real_t) / 2.0, 1.0)
		fade = max(fade, 0.0)
		var sample_val = (breeze * 0.8 + cricket + insect2 + bird) * fade

		var sample_int = clampi(int(sample_val * 11000), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF

	return _make_wav(data)

# ============================================================
# UTILITAIRES
# ============================================================

func _make_wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
