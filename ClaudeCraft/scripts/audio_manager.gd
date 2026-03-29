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
var music_volume: float = 0.35

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
# BANQUES DE SONS — Vrais sons Minecraft (MP3)
# ============================================================

const MC = "res://assets/Audio/Minecraft/"

# Break / dig sounds
var snd_break_stone: Array = []
var snd_break_wood: Array = []
var snd_break_dirt: Array = []   # grass-type dig
var snd_break_sand: Array = []
var snd_break_gravel: Array = []
var snd_break_leaves: Array = [] # cloth
var snd_break_snow: Array = []
var snd_break_glass: Array = []
var snd_break_metal: Array = []  # anvil / chain
var snd_break_default: Array = []

# Place sounds (same material families)
var snd_place_stone: Array = []
var snd_place_wood: Array = []
var snd_place_dirt: Array = []
var snd_place_sand: Array = []
var snd_place_gravel: Array = []
var snd_place_snow: Array = []
var snd_place_metal: Array = []
var snd_place_default: Array = []

# Mining hit sounds (= dig sounds, played at lower volume during mining)
var snd_mine_stone: Array = []
var snd_mine_wood: Array = []
var snd_mine_dirt: Array = []
var snd_mine_sand: Array = []
var snd_mine_gravel: Array = []
var snd_mine_metal: Array = []
var snd_mine_default: Array = []

# Footstep sounds
var snd_step_stone: Array = []
var snd_step_wood: Array = []
var snd_step_grass: Array = []
var snd_step_sand: Array = []
var snd_step_gravel: Array = []
var snd_step_snow: Array = []
var snd_step_dirt: Array = []    # = gravel (earthy)
var snd_step_metal: Array = []   # chain/lantern
var snd_step_ladder: Array = []

# Special block sounds
var snd_door_wood_open: Array = []
var snd_door_wood_close: Array = []
var snd_door_iron_open: Array = []
var snd_door_iron_close: Array = []
var snd_chest_open: Array = []
var snd_chest_close: Array = []
var snd_lantern_break: Array = []
var snd_lantern_place: Array = []

# Eating sounds
var snd_eat: Array = []

# UI sounds
var snd_ui_click: AudioStream = null
var snd_craft_success: AudioStream = null

# Combat / misc
var snd_bow_shoot: AudioStream = null
var snd_arrow_hit: Array = []
var snd_explode: Array = []
var snd_levelup: AudioStream = null

# Forest ambient par heure du jour
var forest_ambient_by_hour: Array = []  # Array de [heure_debut, heure_fin, Array[AudioStream]]
var forest_current_hour_range: int = -1  # Index dans forest_ambient_by_hour
var day_night_cycle_node: Node = null

# Cave ambient mood system (MC-like)
var snd_cave_ambient: Array = []
var cave_mood: float = 0.0           # 0.0 à 1.0 (= 0% à 100%)
var cave_mood_timer: float = 0.0
const CAVE_MOOD_CHECK_INTERVAL = 0.5  # Vérifie toutes les 0.5s
const CAVE_MOOD_TICKS_PER_CHECK = 10  # Simule 10 ticks MC par check
const CAVE_MOOD_INCREMENT = 1.0 / 6000.0  # MC : 1/6000 par tick en obscurité totale
const CAVE_MOOD_LIGHT_DECREMENT = 1.0 / 1000.0  # Diminution par source lumineuse proche
var cave_ambient_player: AudioStreamPlayer = null

# ── Debug : log des derniers sons ambiants ──
var _ambient_log: Array = []  # Array de String, max 20 entrées

func _log_ambient(category: String, description: String):
	var timestamp = Time.get_ticks_msec() / 1000.0
	var entry = "[%.1fs] %s: %s" % [timestamp, category, description]
	_ambient_log.append(entry)
	if _ambient_log.size() > 20:
		_ambient_log.pop_front()
	print(entry)

# ============================================================
# MUSIQUE D'AMBIANCE MC — Tracks aléatoires avec pauses
# ============================================================
const MUSIC_PATH = "res://assets/Audio/Minecraft/music/"

# Pools de musique par contexte
var music_day: Array = []       # Tracks overworld (jour)
var music_night: Array = []     # Subset calme (nuit)
var music_water: Array = []     # Tracks sous-marines

# État du système musique
var music_player_a: AudioStreamPlayer = null
var music_player_b: AudioStreamPlayer = null  # Pour crossfade
var music_active: String = "a"
var music_is_crossfading: bool = false
var music_crossfade_time: float = 0.0
const MUSIC_CROSSFADE_DURATION = 3.0

var music_pause_timer: float = 5.0  # Délai initial avant première musique
var music_is_paused: bool = true
var music_current_pool: String = "day"
var music_last_track: AudioStream = null  # Éviter de répéter le même morceau

func _ready():
	add_to_group("audio_manager")
	_load_sound_banks()
	_create_audio_pools()
	call_deferred("_start_ambient")

func _safe_load(path: String) -> AudioStream:
	var res = load(path)
	if res == null:
		push_warning("AudioManager: fichier introuvable — " + path)
	return res

func _safe_load_bank(paths: Array) -> Array:
	var bank: Array = []
	for path in paths:
		var res = _safe_load(path)
		if res:
			bank.append(res)
	return bank

func _load_sound_banks():
	# ── Helper pour charger N fichiers numérotés ──
	var _mc = func(folder: String, prefix: String, start: int, count: int) -> Array:
		var paths: Array = []
		for i in range(start, start + count):
			paths.append(MC + folder + "/" + prefix + str(i) + ".mp3")
		return _safe_load_bank(paths)

	# === Break / dig sounds (casse de bloc) ===
	snd_break_stone  = _mc.call("dig", "stone", 1, 4)
	snd_break_wood   = _mc.call("dig", "wood", 1, 4)
	snd_break_dirt   = _mc.call("dig", "grass", 1, 4)
	snd_break_sand   = _mc.call("dig", "sand", 1, 4)
	snd_break_gravel = _mc.call("dig", "gravel", 1, 4)
	snd_break_leaves = _mc.call("dig", "cloth", 1, 4)
	snd_break_snow   = _mc.call("dig", "snow", 1, 4)
	snd_break_glass  = _mc.call("random", "glass", 1, 3)
	snd_break_metal  = _safe_load_bank([
		MC + "random/anvil_break.mp3", MC + "random/anvil_land.mp3",
	])
	snd_break_default = snd_break_stone  # fallback = stone

	# === Place sounds (même famille, son de dig réutilisé comme MC) ===
	snd_place_stone  = snd_break_stone
	snd_place_wood   = snd_break_wood
	snd_place_dirt   = snd_break_dirt
	snd_place_sand   = snd_break_sand
	snd_place_gravel = snd_break_gravel
	snd_place_snow   = snd_break_snow
	snd_place_metal  = _safe_load_bank([MC + "random/anvil_land.mp3"])
	snd_place_default = snd_break_stone

	# === Mining hit sounds (= dig sounds, joués pendant le minage) ===
	snd_mine_stone  = snd_break_stone
	snd_mine_wood   = snd_break_wood
	snd_mine_dirt   = snd_break_dirt
	snd_mine_sand   = snd_break_sand
	snd_mine_gravel = snd_break_gravel
	snd_mine_metal  = snd_break_metal
	snd_mine_default = snd_break_stone

	# === Footstep sounds (pas sur surfaces) ===
	snd_step_stone  = _mc.call("step", "stone", 1, 6)
	snd_step_wood   = _mc.call("step", "wood", 1, 6)
	snd_step_grass  = _mc.call("step", "grass", 1, 6)
	snd_step_sand   = _mc.call("step", "sand", 1, 5)
	snd_step_gravel = _mc.call("step", "gravel", 1, 4)
	snd_step_snow   = _mc.call("step", "snow", 1, 4)
	snd_step_dirt   = snd_step_gravel  # terre = gravel dans MC
	snd_step_metal  = _mc.call("step", "stone", 1, 6)  # pierre pour métal
	snd_step_ladder = _mc.call("step", "ladder", 1, 5)

	# === Special block sounds ===
	snd_door_wood_open  = _mc.call("block/wooden_door", "open", 1, 2)
	snd_door_wood_close = _mc.call("block/wooden_door", "close", 1, 3)
	snd_door_iron_open  = _mc.call("block/iron_door", "open", 1, 4)
	snd_door_iron_close = _mc.call("block/iron_door", "close", 1, 4)
	snd_chest_open  = _safe_load_bank([MC + "block/chest/open.mp3"])
	snd_chest_close = _mc.call("block/chest", "close", 1, 3)
	snd_lantern_break = _mc.call("block/lantern", "break", 1, 6)
	snd_lantern_place = _mc.call("block/lantern", "place", 1, 6)

	# === Eating sounds (3 variantes MC) ===
	snd_eat = _mc.call("random", "eat", 1, 3)

	# === Combat / misc ===
	snd_bow_shoot = _safe_load(MC + "random/bow.mp3")
	snd_arrow_hit = _mc.call("random", "bowhit", 1, 4)
	snd_explode   = _mc.call("random", "explode", 1, 4)
	snd_levelup   = _safe_load(MC + "random/levelup.mp3")

	# === UI sounds ===
	snd_ui_click = _safe_load(MC + "random/click.mp3")
	snd_craft_success = _safe_load(MC + "random/levelup.mp3")

	# === Cave ambient (23 sons MC) ===
	snd_cave_ambient = _mc.call("ambient/cave", "cave", 1, 23)

	# === Musique MC ===
	_load_music_pools()

	# === Forest ambient par heure ===
	forest_ambient_by_hour = [
		[5.0, 10.0, _safe_load_bank(["res://Audio/Forest/5-10 matiné.mp3"])],
		[10.0, 12.0, _safe_load_bank(["res://Audio/Forest/10-12 Aurore.mp3", "res://Audio/Forest/10-12 ambiance légère.mp3"])],
		[12.0, 15.0, _safe_load_bank(["res://Audio/Forest/12-15 Midi1.mp3", "res://Audio/Forest/12-15 .mp3"])],
		[15.0, 16.0, _safe_load_bank(["res://Audio/Forest/15-16 Wind and birds.mp3"])],
		[16.0, 18.0, _safe_load_bank(["res://Audio/Forest/16-18 Après-midi1.mp3", "res://Audio/Forest/16-18 Après-midi and Birds.mp3"])],
		[18.0, 21.0, _safe_load_bank(["res://Audio/Forest/18-21 crépuscule.mp3", "res://Audio/Forest/18-21 Wind forest.mp3"])],
		[21.0, 29.0, _safe_load_bank(["res://Audio/Forest/21-5 night.mp3"])],
	]

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

	cave_ambient_player = AudioStreamPlayer.new()
	cave_ambient_player.bus = "Master"
	add_child(cave_ambient_player)

	music_player_a = AudioStreamPlayer.new()
	music_player_a.bus = "Master"
	music_player_a.finished.connect(_on_music_finished)
	add_child(music_player_a)

	music_player_b = AudioStreamPlayer.new()
	music_player_b.bus = "Master"
	music_player_b.volume_db = linear_to_db(0.001)
	music_player_b.finished.connect(_on_music_finished)
	add_child(music_player_b)

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
	var stream = _pick_random(snd_eat)
	if not stream:
		return
	var p = _get_free_sfx()
	p.stream = stream
	p.volume_db = linear_to_db(sfx_volume * master_volume * 0.6)
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()

func play_door_sound(block_type: int, opening: bool, world_pos: Vector3):
	var bank: Array
	if block_type == BlockRegistry.BlockType.IRON_DOOR:
		bank = snd_door_iron_open if opening else snd_door_iron_close
	else:
		bank = snd_door_wood_open if opening else snd_door_wood_close
	var stream = _pick_random(bank)
	if not stream:
		return
	var p = _get_free_sfx_3d()
	p.stream = stream
	p.global_position = world_pos + Vector3(0.5, 0.5, 0.5)
	p.volume_db = linear_to_db(sfx_volume * master_volume * 0.8)
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()

func play_chest_sound(opening: bool, world_pos: Vector3):
	var bank = snd_chest_open if opening else snd_chest_close
	var stream = _pick_random(bank)
	if not stream:
		return
	var p = _get_free_sfx_3d()
	p.stream = stream
	p.global_position = world_pos + Vector3(0.5, 0.5, 0.5)
	p.volume_db = linear_to_db(sfx_volume * master_volume * 0.7)
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()

# ============================================================
# SÉLECTION DE SON PAR TYPE DE BLOC
# ============================================================

func _get_break_sound(block_type: int) -> AudioStream:
	var BR = BlockRegistry.BlockType
	match block_type:
		# Stone family
		BR.STONE, BR.COBBLESTONE, BR.MOSSY_COBBLESTONE, BR.BRICK, BR.SANDSTONE, \
		BR.COAL_ORE, BR.IRON_ORE, BR.GOLD_ORE, BR.DIAMOND_ORE, BR.COPPER_ORE, \
		BR.FURNACE, BR.ANDESITE, BR.GRANITE, BR.DIORITE, BR.DEEPSLATE, \
		BR.SMOOTH_STONE, BR.STONE_BRICKS, BR.COBBLESTONE_STAIRS, \
		BR.STONE_BRICK_STAIRS, BR.COBBLESTONE_SLAB, BR.STONE_SLAB:
			return _pick_random(snd_break_stone)
		# Metal family
		BR.IRON_INGOT, BR.GOLD_INGOT, BR.COPPER_INGOT, BR.DIAMOND_BLOCK, \
		BR.COPPER_BLOCK, BR.COAL_BLOCK, BR.IRON_DOOR, BR.IRON_BARS:
			return _pick_random(snd_break_metal)
		# Wood family
		BR.WOOD, BR.PLANKS, BR.CRAFTING_TABLE, BR.STONE_TABLE, BR.IRON_TABLE, \
		BR.GOLD_TABLE, BR.SPRUCE_LOG, BR.BIRCH_LOG, BR.JUNGLE_LOG, BR.ACACIA_LOG, \
		BR.DARK_OAK_LOG, BR.CHERRY_LOG, BR.SPRUCE_PLANKS, BR.BIRCH_PLANKS, \
		BR.JUNGLE_PLANKS, BR.ACACIA_PLANKS, BR.DARK_OAK_PLANKS, BR.CHERRY_PLANKS, \
		BR.BOOKSHELF, BR.BARREL, BR.CHEST, BR.OAK_STAIRS, BR.OAK_SLAB, \
		BR.OAK_DOOR, BR.OAK_FENCE, BR.LADDER, BR.OAK_TRAPDOOR:
			return _pick_random(snd_break_wood)
		# Dirt / grass
		BR.DIRT, BR.GRASS, BR.DARK_GRASS, BR.CLAY, BR.PODZOL, BR.MOSS_BLOCK, \
		BR.FARMLAND:
			return _pick_random(snd_break_dirt)
		# Sand
		BR.SAND:
			return _pick_random(snd_break_sand)
		# Gravel
		BR.GRAVEL:
			return _pick_random(snd_break_gravel)
		# Leaves / cloth
		BR.LEAVES, BR.CACTUS, BR.SPRUCE_LEAVES, BR.BIRCH_LEAVES, \
		BR.JUNGLE_LEAVES, BR.ACACIA_LEAVES, BR.DARK_OAK_LEAVES, \
		BR.CHERRY_LEAVES, BR.HAY_BLOCK:
			return _pick_random(snd_break_leaves)
		# Snow / ice
		BR.SNOW, BR.ICE, BR.PACKED_ICE:
			return _pick_random(snd_break_snow)
		# Glass
		BR.GLASS, BR.GLASS_PANE:
			return _pick_random(snd_break_glass)
		# Lantern (custom MC sound)
		BR.LANTERN:
			return _pick_random(snd_lantern_break)
		_:
			return _pick_random(snd_break_default)

func _get_place_sound(block_type: int) -> AudioStream:
	var BR = BlockRegistry.BlockType
	match block_type:
		BR.STONE, BR.COBBLESTONE, BR.MOSSY_COBBLESTONE, BR.BRICK, BR.SANDSTONE, \
		BR.COAL_ORE, BR.IRON_ORE, BR.GOLD_ORE, BR.DIAMOND_ORE, BR.COPPER_ORE, \
		BR.FURNACE, BR.ANDESITE, BR.GRANITE, BR.DIORITE, BR.DEEPSLATE, \
		BR.SMOOTH_STONE, BR.STONE_BRICKS, BR.COBBLESTONE_STAIRS, \
		BR.STONE_BRICK_STAIRS, BR.COBBLESTONE_SLAB, BR.STONE_SLAB:
			return _pick_random(snd_place_stone)
		BR.IRON_INGOT, BR.GOLD_INGOT, BR.COPPER_INGOT, BR.DIAMOND_BLOCK, \
		BR.COPPER_BLOCK, BR.COAL_BLOCK, BR.IRON_DOOR, BR.IRON_BARS:
			return _pick_random(snd_place_metal)
		BR.WOOD, BR.PLANKS, BR.CRAFTING_TABLE, BR.STONE_TABLE, BR.IRON_TABLE, \
		BR.GOLD_TABLE, BR.SPRUCE_LOG, BR.BIRCH_LOG, BR.JUNGLE_LOG, BR.ACACIA_LOG, \
		BR.DARK_OAK_LOG, BR.CHERRY_LOG, BR.SPRUCE_PLANKS, BR.BIRCH_PLANKS, \
		BR.JUNGLE_PLANKS, BR.ACACIA_PLANKS, BR.DARK_OAK_PLANKS, BR.CHERRY_PLANKS, \
		BR.BOOKSHELF, BR.BARREL, BR.CHEST, BR.OAK_STAIRS, BR.OAK_SLAB, \
		BR.OAK_DOOR, BR.OAK_FENCE, BR.LADDER, BR.OAK_TRAPDOOR:
			return _pick_random(snd_place_wood)
		BR.DIRT, BR.GRASS, BR.DARK_GRASS, BR.CLAY, BR.PODZOL, BR.MOSS_BLOCK, \
		BR.FARMLAND:
			return _pick_random(snd_place_dirt)
		BR.SAND:
			return _pick_random(snd_place_sand)
		BR.GRAVEL:
			return _pick_random(snd_place_gravel)
		BR.SNOW, BR.ICE, BR.PACKED_ICE:
			return _pick_random(snd_place_snow)
		BR.LANTERN:
			return _pick_random(snd_lantern_place)
		_:
			return _pick_random(snd_place_default)

func _get_mining_sound(block_type: int) -> AudioStream:
	var BR = BlockRegistry.BlockType
	match block_type:
		BR.STONE, BR.COBBLESTONE, BR.MOSSY_COBBLESTONE, BR.BRICK, BR.SANDSTONE, \
		BR.COAL_ORE, BR.IRON_ORE, BR.GOLD_ORE, BR.DIAMOND_ORE, BR.COPPER_ORE, \
		BR.FURNACE, BR.ANDESITE, BR.GRANITE, BR.DIORITE, BR.DEEPSLATE, \
		BR.SMOOTH_STONE, BR.STONE_BRICKS, BR.COBBLESTONE_STAIRS, \
		BR.STONE_BRICK_STAIRS, BR.COBBLESTONE_SLAB, BR.STONE_SLAB:
			return _pick_random(snd_mine_stone)
		BR.IRON_INGOT, BR.GOLD_INGOT, BR.COPPER_INGOT, BR.DIAMOND_BLOCK, \
		BR.COPPER_BLOCK, BR.COAL_BLOCK, BR.IRON_DOOR, BR.IRON_BARS:
			return _pick_random(snd_mine_metal)
		BR.WOOD, BR.PLANKS, BR.CRAFTING_TABLE, BR.STONE_TABLE, BR.IRON_TABLE, \
		BR.GOLD_TABLE, BR.SPRUCE_LOG, BR.BIRCH_LOG, BR.JUNGLE_LOG, BR.ACACIA_LOG, \
		BR.DARK_OAK_LOG, BR.CHERRY_LOG, BR.SPRUCE_PLANKS, BR.BIRCH_PLANKS, \
		BR.JUNGLE_PLANKS, BR.ACACIA_PLANKS, BR.DARK_OAK_PLANKS, BR.CHERRY_PLANKS, \
		BR.BOOKSHELF, BR.BARREL, BR.CHEST, BR.OAK_STAIRS, BR.OAK_SLAB, \
		BR.OAK_DOOR, BR.OAK_FENCE, BR.LADDER, BR.OAK_TRAPDOOR:
			return _pick_random(snd_mine_wood)
		BR.DIRT, BR.GRASS, BR.DARK_GRASS, BR.CLAY, BR.PODZOL, BR.MOSS_BLOCK, \
		BR.FARMLAND, BR.LEAVES, BR.CACTUS, BR.SPRUCE_LEAVES, BR.BIRCH_LEAVES, \
		BR.JUNGLE_LEAVES, BR.ACACIA_LEAVES, BR.DARK_OAK_LEAVES, \
		BR.CHERRY_LEAVES, BR.HAY_BLOCK:
			return _pick_random(snd_mine_dirt)
		BR.SAND:
			return _pick_random(snd_mine_sand)
		BR.GRAVEL:
			return _pick_random(snd_mine_gravel)
		BR.SNOW, BR.ICE, BR.PACKED_ICE:
			return _pick_random(snd_mine_sand)
		BR.GLASS, BR.GLASS_PANE:
			return _pick_random(snd_mine_stone)
		_:
			return _pick_random(snd_mine_default)

func _get_footstep_sound(surface_type: int) -> AudioStream:
	var BR = BlockRegistry.BlockType
	match surface_type:
		# Stone
		BR.STONE, BR.COBBLESTONE, BR.MOSSY_COBBLESTONE, BR.BRICK, BR.SANDSTONE, \
		BR.COAL_ORE, BR.IRON_ORE, BR.GOLD_ORE, BR.DIAMOND_ORE, BR.COPPER_ORE, \
		BR.FURNACE, BR.ANDESITE, BR.GRANITE, BR.DIORITE, BR.DEEPSLATE, \
		BR.SMOOTH_STONE, BR.STONE_BRICKS, BR.COBBLESTONE_STAIRS, \
		BR.STONE_BRICK_STAIRS, BR.COBBLESTONE_SLAB, BR.STONE_SLAB:
			return _pick_random(snd_step_stone)
		# Metal
		BR.IRON_INGOT, BR.GOLD_INGOT, BR.COPPER_INGOT, BR.DIAMOND_BLOCK, \
		BR.COPPER_BLOCK, BR.COAL_BLOCK, BR.IRON_DOOR, BR.IRON_BARS, BR.LANTERN:
			return _pick_random(snd_step_metal)
		# Wood
		BR.WOOD, BR.PLANKS, BR.CRAFTING_TABLE, BR.STONE_TABLE, BR.IRON_TABLE, \
		BR.GOLD_TABLE, BR.SPRUCE_LOG, BR.BIRCH_LOG, BR.JUNGLE_LOG, BR.ACACIA_LOG, \
		BR.DARK_OAK_LOG, BR.CHERRY_LOG, BR.SPRUCE_PLANKS, BR.BIRCH_PLANKS, \
		BR.JUNGLE_PLANKS, BR.ACACIA_PLANKS, BR.DARK_OAK_PLANKS, BR.CHERRY_PLANKS, \
		BR.BOOKSHELF, BR.BARREL, BR.CHEST, BR.OAK_STAIRS, BR.OAK_SLAB, \
		BR.OAK_DOOR, BR.OAK_FENCE, BR.OAK_TRAPDOOR:
			return _pick_random(snd_step_wood)
		# Grass
		BR.GRASS, BR.DARK_GRASS, BR.PODZOL, BR.MOSS_BLOCK, BR.FARMLAND:
			return _pick_random(snd_step_grass)
		# Sand
		BR.SAND:
			return _pick_random(snd_step_sand)
		# Gravel
		BR.GRAVEL, BR.DIRT, BR.CLAY:
			return _pick_random(snd_step_gravel)
		# Snow / ice
		BR.SNOW, BR.ICE, BR.PACKED_ICE:
			return _pick_random(snd_step_snow)
		# Ladder
		BR.LADDER:
			return _pick_random(snd_step_ladder)
		# Leaves
		BR.LEAVES, BR.SPRUCE_LEAVES, BR.BIRCH_LEAVES, BR.JUNGLE_LEAVES, \
		BR.ACACIA_LEAVES, BR.DARK_OAK_LEAVES, BR.CHERRY_LEAVES:
			return _pick_random(snd_step_grass)
		# Glass
		BR.GLASS, BR.GLASS_PANE:
			return _pick_random(snd_step_stone)
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
	_update_cave_mood(delta)
	_update_music(delta)
	_handle_music_crossfade(delta)

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
	var biome_names = {BIOME_DESERT: "Désert", BIOME_FOREST: "Forêt", BIOME_MOUNTAIN: "Montagne", BIOME_PLAINS: "Plaines"}
	if biome == BIOME_FOREST:
		var forest_stream = _get_forest_ambient_for_current_hour()
		if forest_stream:
			_log_ambient("BIOME_FOREST", "fichier: %s" % forest_stream.resource_path.get_file())
			return forest_stream
		_log_ambient("BIOME_FOREST", "procédural (pas de fichier pour cette heure)")
		return _generate_ambient_forest()
	match biome:
		BIOME_DESERT:
			_log_ambient("BIOME", "procédural Désert")
			return _generate_ambient_desert()
		BIOME_MOUNTAIN:
			_log_ambient("BIOME", "procédural Montagne (h=%.0f)" % height)
			return _generate_ambient_mountain(height)
		BIOME_PLAINS:
			_log_ambient("BIOME", "procédural Plaines")
			return _generate_ambient_plains()
		_:
			_log_ambient("BIOME", "procédural Plaines (fallback)")
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
# CAVE AMBIENT MOOD SYSTEM
# ============================================================
# Inspiré de Minecraft : le "mood" augmente dans l'obscurité,
# quand il atteint 100% un son de grotte aléatoire est joué.
# Pas de système de lumière par bloc dans ClaudeCraft, donc on
# approxime : sous terre (blocs solides au-dessus) = sombre,
# torches/lanternes proches = lumière qui réduit le mood.

func _update_cave_mood(delta: float):
	if snd_cave_ambient.is_empty():
		return

	cave_mood_timer += delta
	if cave_mood_timer < CAVE_MOOD_CHECK_INTERVAL:
		return
	cave_mood_timer = 0.0

	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var world_mgr = get_tree().get_first_node_in_group("world_manager")
	if not world_mgr:
		return

	var pos = player.global_position
	var player_y = int(floor(pos.y))

	# 1) Vérifier si le joueur est sous terre : chercher un bloc solide au-dessus
	var sky_blocked = false
	for check_y in range(player_y + 2, min(player_y + 40, 256)):
		var check_pos = Vector3(floor(pos.x), check_y, floor(pos.z))
		var bt = world_mgr.get_block_at_position(check_pos)
		if bt != BlockRegistry.BlockType.AIR and bt != BlockRegistry.BlockType.WATER and bt != BlockRegistry.BlockType.TORCH and bt != BlockRegistry.BlockType.LANTERN and not BlockRegistry.is_cross_mesh(bt):
			sky_blocked = true
			break

	if not sky_blocked:
		# En surface : mood diminue rapidement
		cave_mood = max(0.0, cave_mood - 0.05)
		return

	# 2) Sous terre : compter les sources de lumière proches (rayon 5, pas de 3)
	var light_sources = 0
	for dx in range(-5, 6, 3):
		for dy in range(-3, 4, 3):
			for dz in range(-5, 6, 3):
				var check_pos = Vector3(floor(pos.x) + dx, player_y + dy, floor(pos.z) + dz)
				var bt = world_mgr.get_block_at_position(check_pos)
				if bt == BlockRegistry.BlockType.TORCH or bt == BlockRegistry.BlockType.LANTERN:
					light_sources += 1
					if light_sources >= 3:
						break  # Suffisant pour savoir qu'on est éclairé
			if light_sources >= 3:
				break
		if light_sources >= 3:
			break

	# 3) Calculer le changement de mood (simule CAVE_MOOD_TICKS_PER_CHECK ticks MC)
	var mood_change = 0.0
	if light_sources == 0:
		# Obscurité totale : mood augmente au rythme MC
		mood_change = CAVE_MOOD_INCREMENT * CAVE_MOOD_TICKS_PER_CHECK
	elif light_sources <= 2:
		# Faiblement éclairé : augmente lentement
		mood_change = CAVE_MOOD_INCREMENT * CAVE_MOOD_TICKS_PER_CHECK * 0.3
	else:
		# Bien éclairé : mood diminue
		mood_change = -CAVE_MOOD_LIGHT_DECREMENT * light_sources

	cave_mood = clampf(cave_mood + mood_change, 0.0, 1.0)

	# 4) Mood à 100% → jouer un son de grotte aléatoire
	if cave_mood >= 1.0:
		_play_cave_ambient()
		cave_mood = 0.0

func _play_cave_ambient():
	if cave_ambient_player.playing:
		return
	var stream = _pick_random(snd_cave_ambient)
	if not stream:
		return
	cave_ambient_player.stream = stream
	cave_ambient_player.volume_db = linear_to_db(ambient_volume * master_volume * 0.6)
	cave_ambient_player.pitch_scale = randf_range(0.9, 1.1)
	cave_ambient_player.play()
	_log_ambient("CAVE", "%s (pitch=%.2f)" % [stream.resource_path.get_file(), cave_ambient_player.pitch_scale])

# ============================================================
# MUSIQUE D'AMBIANCE MC
# ============================================================
# Système inspiré de Minecraft : musique aléatoire avec pauses
# de 1-5 minutes entre les morceaux. Pool jour (calme, lumineux)
# vs pool nuit (lent, atmosphérique). Crossfade doux.

func _load_music_pools():
	# Pool JOUR : tracks lumineux, calmes, joyeux — journée ensoleillée
	var day_only = [
		"a_familiar_room", "an_ordinary_day", "ancestry", "bromeliad",
		"clark", "comforting_memories", "crescent_dunes", "danny",
		"dry_hands", "haggstrom", "infinite_amethyst", "key",
		"komorebi", "left_to_bloom", "living_mice", "minecraft",
		"one_more_day", "oxygene", "pokopoko", "puzzlebox",
		"stand_tall", "subwoofer_lullaby", "sweden", "wet_hands",
		"yakusoku"
	]
	# Pool NUIT : tracks sombres, atmosphériques, inquiétants
	var night_only = [
		"deeper", "echo_in_the_wind", "eld_unknown", "endless",
		"featherfall", "floating_dream", "mice_on_venus", "watcher",
		"wending",
		# + quelques calmes qui marchent aussi la nuit
		"clark", "danny", "key", "komorebi", "living_mice",
		"subwoofer_lullaby", "sweden", "wet_hands"
	]

	for track_name in day_only:
		var stream = _safe_load(MUSIC_PATH + "game/" + track_name + ".mp3")
		if stream:
			music_day.append(stream)

	for track_name in night_only:
		var stream = _safe_load(MUSIC_PATH + "game/" + track_name + ".mp3")
		if stream:
			music_night.append(stream)

	# Tracks sous-marines
	for track_name in ["axolotl", "dragon_fish", "shuniji"]:
		var stream = _safe_load(MUSIC_PATH + "game/water/" + track_name + ".mp3")
		if stream:
			music_water.append(stream)

	# Fallback si pas assez de tracks
	if music_night.size() < 3:
		music_night = music_day.duplicate()
	if music_day.size() < 3:
		music_day = music_night.duplicate()

	#print("[MUSIC] Loaded ", music_day.size(), " day tracks, ", music_night.size(), " night tracks, ", music_water.size(), " water tracks")

func _update_music(delta: float):
	# Pendant une pause entre morceaux
	if music_is_paused:
		music_pause_timer -= delta
		if music_pause_timer <= 0:
			_play_next_music()
		return

	# Vérifier si le contexte a changé (jour/nuit)
	_check_music_context()

func _check_music_context():
	if not day_night_cycle_node:
		day_night_cycle_node = get_tree().get_first_node_in_group("day_night_cycle")
	if not day_night_cycle_node:
		return

	var hour = day_night_cycle_node.get_hour()
	var new_pool = "day"
	if hour >= 19.0 or hour < 5.0:
		new_pool = "night"

	# TODO: ajouter détection sous-marine quand le système sera en place

	if new_pool != music_current_pool:
		music_current_pool = new_pool
		# On ne coupe pas le morceau en cours — on changera au prochain

func _get_music_pool() -> Array:
	match music_current_pool:
		"night":
			return music_night
		"water":
			return music_water if not music_water.is_empty() else music_day
		_:
			return music_day

func _play_next_music():
	var pool = _get_music_pool()
	if pool.is_empty():
		music_pause_timer = 30.0  # Réessayer dans 30s
		return

	# Choisir un morceau aléatoire (différent du précédent)
	var stream: AudioStream = null
	if pool.size() == 1:
		stream = pool[0]
	else:
		for _attempt in range(5):
			stream = pool[randi() % pool.size()]
			if stream != music_last_track:
				break

	music_last_track = stream
	music_is_paused = false

	# Jouer avec fade in
	var active_p = music_player_a if music_active == "a" else music_player_b
	active_p.stream = stream
	active_p.volume_db = linear_to_db(0.001)
	active_p.play()
	_log_ambient("MUSIC", "%s (pool: %s)" % [stream.resource_path.get_file(), music_current_pool])

	# Fade in progressif via crossfade
	music_is_crossfading = true
	music_crossfade_time = 0.0

func _on_music_finished():
	# Morceau terminé → pause aléatoire MC (60-300 secondes = 1-5 minutes)
	music_is_paused = true
	music_pause_timer = randf_range(60.0, 300.0)
	_log_ambient("MUSIC", "track terminé — pause %.0fs avant prochain morceau" % music_pause_timer)

func _handle_music_crossfade(delta: float):
	if not music_is_crossfading:
		return

	music_crossfade_time += delta
	var progress = min(music_crossfade_time / MUSIC_CROSSFADE_DURATION, 1.0)
	var vol_target = music_volume * master_volume

	var active_player = music_player_a if music_active == "a" else music_player_b
	active_player.volume_db = linear_to_db(max(progress * vol_target, 0.001))

	if progress >= 1.0:
		music_is_crossfading = false

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
