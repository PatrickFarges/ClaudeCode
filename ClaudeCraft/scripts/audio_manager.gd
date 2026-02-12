extends Node
class_name AudioManager

# ============================================================
# AUDIO MANAGER — Sons procéduraux (remplaçables par fichiers)
# ============================================================
# Pour remplacer un son procédural par un vrai fichier :
#   1. Placer le fichier dans res://audio/ (ex: break_stone.ogg)
#   2. Dans la méthode correspondante, remplacer :
#        _play_procedural_xxx() 
#      par :
#        _play_file("res://audio/break_stone.ogg", position)
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
var ambient_volume: float = 0.7  # v7.1 augmenté (était 0.3)

# Pool sizes
const SFX_POOL_SIZE = 8
const SFX_3D_POOL_SIZE = 6

# Biome ambient
var current_biome: int = -1
var current_height: float = 64.0
var last_ambient_height: float = 64.0  # Hauteur lors de la dernière génération
var ambient_player_a: AudioStreamPlayer = null  # Crossfade A
var ambient_player_b: AudioStreamPlayer = null  # Crossfade B
var active_ambient: String = "a"  # Quel player joue actuellement
var crossfade_time: float = 0.0
var is_crossfading: bool = false
const CROSSFADE_DURATION = 2.0  # Secondes pour le fondu
var biome_check_timer: float = 0.0
const BIOME_CHECK_INTERVAL = 0.5  # v7.1 vérifie 2x par seconde
const HEIGHT_CHANGE_THRESHOLD = 15.0  # Régénérer le son si on change de +15 blocs

# Noise pour détecter le biome (mêmes seeds que chunk_generator!)
var temp_noise: FastNoiseLite
var humid_noise: FastNoiseLite

# Constantes biome
const BIOME_DESERT = 0
const BIOME_FOREST = 1
const BIOME_MOUNTAIN = 2
const BIOME_PLAINS = 3

func _ready():
	add_to_group("audio_manager")
	_create_audio_pools()
	# Lancer l'ambiance après un court délai
	call_deferred("_start_ambient")

# ============================================================
# POOL D'AUDIO PLAYERS
# ============================================================

func _create_audio_pools():
	# Players 2D pour UI et sons généraux
	for i in range(SFX_POOL_SIZE):
		var p = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		sfx_players.append(p)
	
	# Players 3D pour sons positionnels
	for i in range(SFX_3D_POOL_SIZE):
		var p = AudioStreamPlayer3D.new()
		p.bus = "Master"
		p.max_distance = 20.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		sfx_3d_players.append(p)
	
	# Deux players ambiants pour crossfade
	ambient_player_a = AudioStreamPlayer.new()
	ambient_player_a.bus = "Master"
	add_child(ambient_player_a)
	
	ambient_player_b = AudioStreamPlayer.new()
	ambient_player_b.bus = "Master"
	ambient_player_b.volume_db = linear_to_db(0.001)  # Silencieux au départ
	add_child(ambient_player_b)
	
	# Player dédié pas
	footstep_player = AudioStreamPlayer.new()
	footstep_player.bus = "Master"
	add_child(footstep_player)
	
	# Noise pour détection de biome (MÊMES SEEDS que chunk_generator.gd!)
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
	return sfx_players[0]  # Fallback: réutiliser le premier

func _get_free_sfx_3d() -> AudioStreamPlayer3D:
	for p in sfx_3d_players:
		if not p.playing:
			return p
	return sfx_3d_players[0]

# ============================================================
# API PUBLIQUE — Appeler ces méthodes depuis le jeu
# ============================================================

func play_break_sound(block_type: int, world_pos: Vector3):
	"""Son de casse de bloc — positionnel 3D"""
	var stream = _generate_break_sound(block_type)
	var player = _get_free_sfx_3d()
	player.stream = stream
	player.global_position = world_pos + Vector3(0.5, 0.5, 0.5)
	player.volume_db = linear_to_db(sfx_volume * master_volume)
	player.pitch_scale = randf_range(0.9, 1.1)
	player.play()

func play_place_sound(block_type: int, world_pos: Vector3):
	"""Son de placement de bloc — positionnel 3D"""
	var stream = _generate_place_sound(block_type)
	var player = _get_free_sfx_3d()
	player.stream = stream
	player.global_position = world_pos + Vector3(0.5, 0.5, 0.5)
	player.volume_db = linear_to_db(sfx_volume * master_volume * 0.7)
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()

func play_mining_hit(block_type: int, world_pos: Vector3):
	"""Son de frappe pendant le minage"""
	var stream = _generate_mining_hit(block_type)
	var player = _get_free_sfx_3d()
	player.stream = stream
	player.global_position = world_pos + Vector3(0.5, 0.5, 0.5)
	player.volume_db = linear_to_db(sfx_volume * master_volume * 0.5)
	player.pitch_scale = randf_range(0.85, 1.15)
	player.play()

func play_footstep(surface_type: int):
	"""Son de pas — 2D (toujours le joueur)"""
	if footstep_player.playing:
		return  # Éviter la superposition
	var stream = _generate_footstep(surface_type)
	footstep_player.stream = stream
	footstep_player.volume_db = linear_to_db(sfx_volume * master_volume * 0.35)
	footstep_player.pitch_scale = randf_range(0.8, 1.2)
	footstep_player.play()

func play_ui_click():
	"""Son de clic UI"""
	var stream = _generate_ui_click()
	var player = _get_free_sfx()
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume * master_volume * 0.4)
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()

func play_craft_success():
	"""Son de craft réussi"""
	var stream = _generate_craft_success()
	var player = _get_free_sfx()
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume * master_volume * 0.6)
	player.play()

# ============================================================
# AMBIANCE PAR BIOME
# ============================================================

func _start_ambient():
	# Démarrer avec le biome par défaut (plaines)
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
	"""Vérifier si le biome ou la hauteur a changé"""
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
	
	# Changement de biome → crossfade
	if biome != current_biome:
		current_biome = biome
		last_ambient_height = pos.y
		_crossfade_to_biome(biome, pos.y)
	# En montagne : régénérer si on a changé de hauteur significativement
	elif biome == BIOME_MOUNTAIN and abs(pos.y - last_ambient_height) > HEIGHT_CHANGE_THRESHOLD:
		last_ambient_height = pos.y
		_crossfade_to_biome(biome, pos.y)

func _detect_biome(world_x: float, world_z: float) -> int:
	"""Détecter le biome à une position (mêmes calculs que chunk_generator)"""
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
	"""Lancer un crossfade vers l'ambiance du nouveau biome"""
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
	"""Gérer le fondu enchaîné entre deux ambiances"""
	if not is_crossfading:
		return
	
	crossfade_time += delta
	var progress = min(crossfade_time / CROSSFADE_DURATION, 1.0)
	
	var vol_target = ambient_volume * master_volume
	
	if active_ambient == "b":
		# B monte, A descend
		ambient_player_b.volume_db = linear_to_db(max(progress * vol_target, 0.001))
		ambient_player_a.volume_db = linear_to_db(max((1.0 - progress) * vol_target, 0.001))
	else:
		# A monte, B descend
		ambient_player_a.volume_db = linear_to_db(max(progress * vol_target, 0.001))
		ambient_player_b.volume_db = linear_to_db(max((1.0 - progress) * vol_target, 0.001))
	
	if progress >= 1.0:
		is_crossfading = false
		# Stopper le player qui a fini de descendre
		if active_ambient == "b":
			ambient_player_a.stop()
		else:
			ambient_player_b.stop()

func _on_ambient_a_finished():
	if active_ambient == "a" or is_crossfading:
		# Régénérer et relancer
		ambient_player_a.stream = _generate_biome_ambient(current_biome, current_height)
		ambient_player_a.play()

func _on_ambient_b_finished():
	if active_ambient == "b" or is_crossfading:
		ambient_player_b.stream = _generate_biome_ambient(current_biome, current_height)
		ambient_player_b.play()

func _generate_biome_ambient(biome: int, height: float) -> AudioStreamWAV:
	"""Générer un son d'ambiance selon le biome"""
	match biome:
		BIOME_FOREST:
			return _generate_ambient_forest()
		BIOME_DESERT:
			return _generate_ambient_desert()
		BIOME_MOUNTAIN:
			return _generate_ambient_mountain(height)
		BIOME_PLAINS:
			return _generate_ambient_plains()
		_:
			return _generate_ambient_plains()

# ============================================================
# GÉNÉRATION PROCÉDURALE DES SONS
# ============================================================
# Chaque méthode _generate_xxx retourne un AudioStreamWAV
# Pour remplacer par un fichier : retourner load("res://audio/xxx.ogg")
# ============================================================

func _generate_break_sound(block_type: int) -> AudioStreamWAV:
	"""Générer un son de casse selon le type de bloc"""
	var duration = 0.15
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	
	# Paramètres selon le bloc
	var freq = 200.0  # Fréquence de base
	var noise_mix = 0.5  # Mix bruit/ton
	var decay = 8.0  # Vitesse de décroissance
	
	match block_type:
		BlockRegistry.BlockType.STONE, BlockRegistry.BlockType.GRAVEL, BlockRegistry.BlockType.BRICK, BlockRegistry.BlockType.SANDSTONE:
			freq = 180.0; noise_mix = 0.7; decay = 10.0  # Dur, claquant
		BlockRegistry.BlockType.WOOD, BlockRegistry.BlockType.PLANKS, BlockRegistry.BlockType.CRAFTING_TABLE:
			freq = 250.0; noise_mix = 0.3; decay = 8.0   # Boisé, chaud
		BlockRegistry.BlockType.DIRT, BlockRegistry.BlockType.GRASS, BlockRegistry.BlockType.DARK_GRASS:
			freq = 120.0; noise_mix = 0.6; decay = 12.0  # Sourd, mou
		BlockRegistry.BlockType.SAND:
			freq = 300.0; noise_mix = 0.9; decay = 15.0  # Granuleux
		BlockRegistry.BlockType.LEAVES:
			freq = 400.0; noise_mix = 0.8; decay = 12.0  # Léger, bruissant
		BlockRegistry.BlockType.SNOW:
			freq = 500.0; noise_mix = 0.95; decay = 18.0  # Feutré
		_:
			freq = 200.0; noise_mix = 0.5; decay = 10.0
	
	for i in range(samples):
		var t = float(i) / SAMPLE_RATE
		var envelope = exp(-decay * t)
		
		# Mélange tonalité + bruit
		var tone = sin(TAU * freq * t + sin(TAU * freq * 0.5 * t) * 2.0)
		var noise = randf_range(-1.0, 1.0)
		var sample_val = (tone * (1.0 - noise_mix) + noise * noise_mix) * envelope
		
		var sample_int = clampi(int(sample_val * 16000), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	
	return _make_wav(data)

func _generate_place_sound(block_type: int) -> AudioStreamWAV:
	"""Son de placement — thump court"""
	var duration = 0.1
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	
	var freq = 150.0
	match block_type:
		BlockRegistry.BlockType.STONE, BlockRegistry.BlockType.BRICK, BlockRegistry.BlockType.SANDSTONE:
			freq = 130.0
		BlockRegistry.BlockType.WOOD, BlockRegistry.BlockType.PLANKS:
			freq = 200.0
		BlockRegistry.BlockType.SAND:
			freq = 250.0
		_:
			freq = 160.0
	
	for i in range(samples):
		var t = float(i) / SAMPLE_RATE
		var envelope = exp(-15.0 * t)
		var sample_val = sin(TAU * freq * t) * envelope
		# Petit impact au début
		if t < 0.01:
			sample_val += randf_range(-0.5, 0.5) * (1.0 - t / 0.01)
		
		var sample_int = clampi(int(sample_val * 14000), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	
	return _make_wav(data)

func _generate_mining_hit(block_type: int) -> AudioStreamWAV:
	"""Son de frappe de minage — court tap"""
	var duration = 0.08
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	
	var freq = 300.0
	var noise_amt = 0.4
	match block_type:
		BlockRegistry.BlockType.STONE, BlockRegistry.BlockType.BRICK:
			freq = 400.0; noise_amt = 0.3
		BlockRegistry.BlockType.WOOD, BlockRegistry.BlockType.PLANKS:
			freq = 350.0; noise_amt = 0.2
		BlockRegistry.BlockType.DIRT, BlockRegistry.BlockType.GRASS:
			freq = 200.0; noise_amt = 0.6
		BlockRegistry.BlockType.SAND:
			freq = 250.0; noise_amt = 0.8
		_:
			freq = 300.0; noise_amt = 0.4
	
	for i in range(samples):
		var t = float(i) / SAMPLE_RATE
		var envelope = exp(-25.0 * t)
		var tone = sin(TAU * freq * t)
		var noise = randf_range(-1.0, 1.0)
		var sample_val = (tone * (1.0 - noise_amt) + noise * noise_amt) * envelope
		
		var sample_int = clampi(int(sample_val * 10000), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	
	return _make_wav(data)

func _generate_footstep(surface_type: int) -> AudioStreamWAV:
	"""Son de pas selon la surface"""
	var duration = 0.1
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	
	var freq = 100.0
	var noise_mix = 0.7
	var decay = 20.0
	
	match surface_type:
		BlockRegistry.BlockType.STONE, BlockRegistry.BlockType.BRICK, BlockRegistry.BlockType.GRAVEL:
			freq = 150.0; noise_mix = 0.5; decay = 18.0  # Claquant
		BlockRegistry.BlockType.WOOD, BlockRegistry.BlockType.PLANKS:
			freq = 180.0; noise_mix = 0.3; decay = 15.0  # Boisé
		BlockRegistry.BlockType.SAND:
			freq = 80.0; noise_mix = 0.9; decay = 25.0   # Étouffé
		BlockRegistry.BlockType.SNOW:
			freq = 200.0; noise_mix = 0.95; decay = 30.0  # Crissement
		BlockRegistry.BlockType.GRASS, BlockRegistry.BlockType.DARK_GRASS:
			freq = 100.0; noise_mix = 0.7; decay = 22.0  # Herbeux
		_:
			freq = 120.0; noise_mix = 0.6; decay = 20.0
	
	for i in range(samples):
		var t = float(i) / SAMPLE_RATE
		var envelope = exp(-decay * t)
		var tone = sin(TAU * freq * t)
		var noise = randf_range(-1.0, 1.0)
		var sample_val = (tone * (1.0 - noise_mix) + noise * noise_mix) * envelope
		
		var sample_int = clampi(int(sample_val * 8000), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	
	return _make_wav(data)

func _generate_ui_click() -> AudioStreamWAV:
	"""Petit clic UI"""
	var duration = 0.04
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	
	for i in range(samples):
		var t = float(i) / SAMPLE_RATE
		var envelope = exp(-40.0 * t)
		var sample_val = sin(TAU * 800.0 * t) * envelope
		
		var sample_int = clampi(int(sample_val * 8000), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	
	return _make_wav(data)

func _generate_craft_success() -> AudioStreamWAV:
	"""Son de craft réussi — deux tons montants"""
	var duration = 0.25
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	
	for i in range(samples):
		var t = float(i) / SAMPLE_RATE
		var envelope = exp(-6.0 * t)
		# Deux notes : do → mi (montant = succès)
		var freq = 523.0 if t < 0.12 else 659.0
		var sample_val = sin(TAU * freq * t) * envelope * 0.7
		# Petit harmonique
		sample_val += sin(TAU * freq * 2.0 * t) * envelope * 0.2
		
		var sample_int = clampi(int(sample_val * 12000), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	
	return _make_wav(data)

func _generate_ambient_forest() -> AudioStreamWAV:
	"""Forêt : vent doux dans les feuilles + oiseaux chantants"""
	var duration = 8.0
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	
	var filtered = 0.0
	var filtered2 = 0.0
	
	# Seed aléatoire pour varier à chaque régénération
	var phase_offset = randf() * 100.0
	
	for i in range(samples):
		var t = float(i) / SAMPLE_RATE + phase_offset
		var noise = randf_range(-1.0, 1.0)
		
		# Couche 1 : vent doux dans les arbres
		filtered = filtered * 0.993 + noise * 0.007
		var wind = filtered * (sin(TAU * 0.12 * t) * 0.3 + 0.7)
		
		# Couche 2 : bruissement de feuilles (rafales irrégulières)
		filtered2 = filtered2 * 0.98 + randf_range(-1.0, 1.0) * 0.02
		var rustle_env = max(0.0, sin(TAU * 0.25 * t + sin(TAU * 0.6 * t) * 3.0))
		var rustle = filtered2 * rustle_env * 0.6
		
		# Couche 3 : oiseaux — 3 espèces différentes qui chantent
		var bird = 0.0
		var cycle = fmod(t, 6.0)
		
		# Oiseau 1 : mélodie descendante (type merle)
		if cycle > 0.5 and cycle < 1.0:
			var bt = (cycle - 0.5) / 0.5
			var freq = 2800.0 - bt * 800.0  # Descend de 2800 à 2000 Hz
			bird += sin(TAU * freq * t) * (1.0 - bt) * 0.25
		
		# Oiseau 2 : trille rapide
		if cycle > 2.5 and cycle < 3.0:
			var bt = (cycle - 2.5) / 0.5
			var trill = sin(TAU * 15.0 * t)  # Modulation rapide
			bird += sin(TAU * 3200.0 * t) * max(0.0, trill) * (1.0 - bt) * 0.2
		
		# Oiseau 3 : deux notes (type mésange ti-tu)
		if cycle > 4.0 and cycle < 4.15:
			bird += sin(TAU * 3500.0 * t) * 0.2
		elif cycle > 4.2 and cycle < 4.35:
			bird += sin(TAU * 2900.0 * t) * 0.18
		elif cycle > 4.5 and cycle < 4.65:
			bird += sin(TAU * 3500.0 * t) * 0.15
		
		# Fade in/out
		var fade = min(t - phase_offset, 1.5) / 1.5
		fade = min(fade, 1.0) * min((duration - (t - phase_offset)) / 1.5, 1.0)
		fade = max(fade, 0.0)
		var sample_val = (wind * 0.7 + rustle + bird) * fade
		
		var sample_int = clampi(int(sample_val * 12000), -32768, 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	
	return _make_wav(data)

func _generate_ambient_desert() -> AudioStreamWAV:
	"""Désert : chaleur sèche, vent lointain, silence oppressant"""
	var duration = 8.0
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	
	var filtered = 0.0
	var phase_offset = randf() * 100.0
	
	for i in range(samples):
		var t = float(i) / SAMPLE_RATE + phase_offset
		var noise = randf_range(-1.0, 1.0)
		
		# Couche 1 : vent sec grave et lent
		filtered = filtered * 0.997 + noise * 0.003
		var wind = filtered * (sin(TAU * 0.05 * t) * 0.4 + 0.6)
		
		# Couche 2 : sifflement dans les dunes (occasionnel)
		var whistle = 0.0
		var w_cycle = fmod(t, 8.0)
		if w_cycle > 3.0 and w_cycle < 5.0:
			var w_env = sin((w_cycle - 3.0) / 2.0 * PI)
			var w_freq = 500.0 + sin(TAU * 0.3 * t) * 150.0
			whistle = sin(TAU * w_freq * t) * w_env * 0.1
		
		# Couche 3 : bourdonnement de chaleur (très basse fréquence)
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
	"""Montagne : vent qui s'intensifie avec l'altitude, rafales, air glacial"""
	var duration = 8.0
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	
	# Plus on est haut, plus c'est intense
	# Y:64 = base calme, Y:90 = moyen, Y:120+ = tempête
	var height_factor = clampf((height - 64.0) / 60.0, 0.0, 1.0)
	
	var filtered = 0.0
	var filtered_hi = 0.0
	var phase_offset = randf() * 100.0
	
	for i in range(samples):
		var t = float(i) / SAMPLE_RATE + phase_offset
		var noise = randf_range(-1.0, 1.0)
		
		# Couche 1 : vent de base — intensité selon altitude
		var filter_c = 0.992 - height_factor * 0.008  # Plus aigu en altitude
		filtered = filtered * filter_c + noise * (1.0 - filter_c)
		var wind_mod = sin(TAU * 0.08 * t) * 0.15 + (0.5 + height_factor * 0.5)
		var wind = filtered * wind_mod
		
		# Couche 2 : rafales puissantes (plus fréquentes en altitude)
		var gust = 0.0
		var gust_interval = 4.0 - height_factor * 2.0  # 4s en bas, 2s en haut
		var gust_cycle = fmod(t, gust_interval)
		if gust_cycle > 0.5 and gust_cycle < 2.0:
			var g_env = sin((gust_cycle - 0.5) / 1.5 * PI)
			gust = randf_range(-1.0, 1.0) * g_env * (0.3 + height_factor * 0.5)
		
		# Couche 3 : sifflement d'air glacial (aigu, seulement en altitude)
		var whistle = 0.0
		if height_factor > 0.3:
			filtered_hi = filtered_hi * 0.95 + randf_range(-1.0, 1.0) * 0.05
			var w_mod = sin(TAU * 0.15 * t + sin(TAU * 0.08 * t) * 4.0) * 0.5 + 0.5
			whistle = filtered_hi * w_mod * (height_factor - 0.3) / 0.7 * 0.7
			# Ajouter un sifflement tonal
			var tonal = sin(TAU * (800.0 + sin(TAU * 0.2 * t) * 200.0) * t)
			whistle += tonal * w_mod * (height_factor - 0.3) / 0.7 * 0.08
		
		# Couche 4 : grondement sourd de la montagne
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
	"""Plaines : brise douce, grillons, oiseau lointain occasionnel"""
	var duration = 8.0
	var samples = int(SAMPLE_RATE * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	
	var filtered = 0.0
	var phase_offset = randf() * 100.0
	
	for i in range(samples):
		var t = float(i) / SAMPLE_RATE + phase_offset
		var noise = randf_range(-1.0, 1.0)
		
		# Couche 1 : brise légère
		filtered = filtered * 0.996 + noise * 0.004
		var breeze = filtered * (sin(TAU * 0.08 * t) * 0.3 + 0.55)
		
		# Couche 2 : grillons / insectes (buzz continu modulé)
		var cricket = 0.0
		var c_cycle = fmod(t, 2.5)
		if c_cycle > 0.3 and c_cycle < 1.8:
			var c_env = sin((c_cycle - 0.3) / 1.5 * PI) * 0.5 + 0.5
			cricket = sin(TAU * 4400.0 * t) * sin(TAU * 5.5 * t) * c_env * 0.06
		
		# Couche 3 : deuxième insecte (fréquence différente)
		var insect2 = 0.0
		var i_cycle = fmod(t + 1.3, 3.0)
		if i_cycle > 0.5 and i_cycle < 2.0:
			var i_env = sin((i_cycle - 0.5) / 1.5 * PI)
			insect2 = sin(TAU * 3800.0 * t) * sin(TAU * 7.0 * t) * i_env * 0.04
		
		# Couche 4 : oiseau lointain (occasionnel, doux)
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
	"""Créer un AudioStreamWAV à partir de données PCM 16-bit"""
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream

# ============================================================
# REMPLACEMENT PAR FICHIERS (pour plus tard)
# ============================================================
# Exemple d'utilisation avec un vrai fichier :
#
# func play_break_sound(block_type: int, world_pos: Vector3):
#     var path = "res://audio/break_%s.ogg" % _block_type_string(block_type)
#     var stream = load(path) if ResourceLoader.exists(path) else _generate_break_sound(block_type)
#     var player = _get_free_sfx_3d()
#     player.stream = stream
#     player.global_position = world_pos
#     player.play()
#
# Structure de fichiers attendue :
#   res://audio/
#     break_stone.ogg
#     break_wood.ogg
#     break_dirt.ogg
#     break_sand.ogg
#     break_leaves.ogg
#     break_snow.ogg
#     place_stone.ogg
#     place_wood.ogg
#     place_default.ogg
#     step_stone.ogg
#     step_wood.ogg
#     step_dirt.ogg
#     step_grass.ogg
#     step_sand.ogg
#     step_snow.ogg
#     mining_hit.ogg
#     ui_click.ogg
#     craft_success.ogg
#     ambient_wind.ogg
#     ambient_forest.ogg
#     ambient_desert.ogg
#     ambient_mountain.ogg
#     ambient_plains.ogg
# ============================================================
