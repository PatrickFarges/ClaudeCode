extends Node3D
## Gestionnaire météo — pluie procédurale avec transitions douces
## Intègre nuages, brouillard, lumière, particules et son

const APP_VERSION = "v20.3.1"

# ---- États météo ----
enum Weather { CLEAR, CLOUDY, RAIN, STORM }

const WEATHER_NAMES = {
	Weather.CLEAR: "Clair",
	Weather.CLOUDY: "Nuageux",
	Weather.RAIN: "Pluie",
	Weather.STORM: "Orage",
}

# ---- Config ----
const TRANSITION_DURATION = 8.0       # Secondes pour la transition entre états
const MIN_WEATHER_DURATION = 180.0    # Durée min en secondes jeu (3 min)
const MAX_WEATHER_DURATION = 600.0    # Durée max en secondes jeu (10 min)
const RAIN_PARTICLE_COUNT = 3000
const STORM_PARTICLE_COUNT = 6000
const RAIN_AREA = Vector3(80.0, 50.0, 80.0)  # Zone de spawn des gouttes
const RAIN_SPEED_MIN = 18.0
const RAIN_SPEED_MAX = 25.0
const STORM_SPEED_MIN = 25.0
const STORM_SPEED_MAX = 35.0

# Paramètres nuages par état météo [coverage, opacity, softness, speed]
const CLOUD_PRESETS = {
	Weather.CLEAR:  [0.45, 0.75, 0.25, 0.008],
	Weather.CLOUDY: [0.58, 0.85, 0.20, 0.012],
	Weather.RAIN:   [0.70, 0.90, 0.15, 0.015],
	Weather.STORM:  [0.82, 0.95, 0.10, 0.025],
}

# Facteurs assombrissement (multiplié sur la lumière du soleil)
const LIGHT_FACTORS = {
	Weather.CLEAR:  1.0,
	Weather.CLOUDY: 0.85,
	Weather.RAIN:   0.65,
	Weather.STORM:  0.45,
}

# Couleurs ciel couvert (lerp target pour background_color)
const SKY_OVERCAST_RAIN = Color(0.45, 0.48, 0.55)
const SKY_OVERCAST_STORM = Color(0.25, 0.27, 0.32)

# Fog density override
const FOG_DENSITY = {
	Weather.CLEAR:  0.006,
	Weather.CLOUDY: 0.008,
	Weather.RAIN:   0.015,
	Weather.STORM:  0.025,
}

# ---- État ----
var current_weather: Weather = Weather.CLEAR
var target_weather: Weather = Weather.CLEAR
var transition_progress: float = 1.0  # 1.0 = transition terminée
var weather_timer: float = 0.0
var next_weather_change: float = 0.0

# Facteurs interpolés
var current_light_factor: float = 1.0
var current_fog_density: float = 0.006
var current_cloud_preset: Array = [0.45, 0.75, 0.25, 0.008]
var current_rain_intensity: float = 0.0  # 0 = pas de pluie, 1 = max

# Références
var day_night_cycle = null
var cloud_manager = null
var audio_manager = null
var player = null
var env: Environment = null

# Particules pluie
var rain_particles: GPUParticles3D = null
var rain_process_material: ParticleProcessMaterial = null

# Audio pluie
var rain_audio: AudioStreamPlayer = null
var rain_volume_target: float = -80.0
const RAIN_VOLUME_MAX = -8.0   # dB
const RAIN_VOLUME_FADE_SPEED = 15.0  # dB/sec

# Éclairs (orage)
var lightning_timer: float = 0.0
var lightning_flash_time: float = 0.0
var is_flashing: bool = false

func _ready():
	add_to_group("weather_manager")

	await get_tree().process_frame
	day_night_cycle = get_tree().get_first_node_in_group("day_night_cycle")
	cloud_manager = get_tree().get_first_node_in_group("cloud_manager")
	audio_manager = get_tree().get_first_node_in_group("audio_manager")
	player = get_tree().get_first_node_in_group("player")

	var world_env = get_tree().get_first_node_in_group("world_environment")
	if world_env:
		env = world_env.environment

	_setup_rain_particles()
	_setup_rain_audio()
	_schedule_next_weather()

func _setup_rain_particles():
	rain_particles = GPUParticles3D.new()
	rain_particles.emitting = false
	rain_particles.amount = RAIN_PARTICLE_COUNT
	rain_particles.lifetime = 2.0
	rain_particles.visibility_aabb = AABB(Vector3(-RAIN_AREA.x/2, -RAIN_AREA.y, -RAIN_AREA.z/2),
										   RAIN_AREA * 1.5)
	rain_particles.draw_order = GPUParticles3D.DRAW_ORDER_INDEX

	# Process material
	rain_process_material = ParticleProcessMaterial.new()
	rain_process_material.direction = Vector3(0, -1, 0)
	rain_process_material.spread = 3.0
	rain_process_material.initial_velocity_min = RAIN_SPEED_MIN
	rain_process_material.initial_velocity_max = RAIN_SPEED_MAX
	rain_process_material.gravity = Vector3(0, -12.0, 0)
	rain_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rain_process_material.emission_box_extents = Vector3(RAIN_AREA.x / 2.0, 2.0, RAIN_AREA.z / 2.0)
	rain_process_material.damping_min = 0.0
	rain_process_material.damping_max = 0.0
	rain_process_material.scale_min = 0.8
	rain_process_material.scale_max = 1.2
	rain_particles.process_material = rain_process_material

	# Mesh goutte — fine barre verticale semi-transparente
	var drop_mesh = BoxMesh.new()
	drop_mesh.size = Vector3(0.03, 0.5, 0.03)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.78, 0.9, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	drop_mesh.material = mat

	rain_particles.draw_pass_1 = drop_mesh
	rain_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(rain_particles)

func _setup_rain_audio():
	rain_audio = AudioStreamPlayer.new()
	var stream = load("res://Audio/rain-4.ogg")
	if not stream:
		stream = load("res://Audio/rain-4.mp3")
	if stream:
		# Activer le loop sur le stream (doublon avec .import, mais sécurité)
		if "loop" in stream:
			stream.loop = true
		rain_audio.stream = stream
		rain_audio.volume_db = -80.0
		rain_audio.bus = "Master"
		# Loop manuel en secours si le stream ne boucle pas nativement
		rain_audio.finished.connect(_on_rain_audio_finished)
		add_child(rain_audio)

func _on_rain_audio_finished():
	# Si la pluie est encore active, relancer immédiatement (loop manuel)
	if current_rain_intensity > 0.01 and rain_audio:
		rain_audio.play()

func _process(delta):
	_update_weather_timer(delta)
	_update_transition(delta)
	_update_rain_particles()
	_update_rain_audio(delta)
	_update_environment()
	_update_lightning(delta)

func _update_weather_timer(delta):
	weather_timer += delta
	if weather_timer >= next_weather_change and transition_progress >= 1.0:
		_change_weather()

func _change_weather():
	var possible: Array = []
	match current_weather:
		Weather.CLEAR:
			possible = [Weather.CLOUDY, Weather.CLOUDY, Weather.CLEAR]
		Weather.CLOUDY:
			possible = [Weather.RAIN, Weather.CLEAR, Weather.CLOUDY]
		Weather.RAIN:
			possible = [Weather.STORM, Weather.CLOUDY, Weather.RAIN]
		Weather.STORM:
			possible = [Weather.RAIN, Weather.RAIN, Weather.CLOUDY]

	target_weather = possible[randi() % possible.size()]
	if target_weather != current_weather:
		transition_progress = 0.0
	_schedule_next_weather()

func _schedule_next_weather():
	weather_timer = 0.0
	next_weather_change = randf_range(MIN_WEATHER_DURATION, MAX_WEATHER_DURATION)

func _update_transition(delta):
	if transition_progress >= 1.0:
		return

	transition_progress = minf(transition_progress + delta / TRANSITION_DURATION, 1.0)
	var t = smoothstep(0.0, 1.0, transition_progress)

	# Interpoler light factor
	current_light_factor = lerpf(LIGHT_FACTORS[current_weather], LIGHT_FACTORS[target_weather], t)

	# Interpoler fog
	current_fog_density = lerpf(FOG_DENSITY[current_weather], FOG_DENSITY[target_weather], t)

	# Interpoler cloud preset
	var from_p = CLOUD_PRESETS[current_weather]
	var to_p = CLOUD_PRESETS[target_weather]
	current_cloud_preset = [
		lerpf(from_p[0], to_p[0], t),
		lerpf(from_p[1], to_p[1], t),
		lerpf(from_p[2], to_p[2], t),
		lerpf(from_p[3], to_p[3], t),
	]

	# Interpoler intensité pluie
	var from_rain = 1.0 if current_weather == Weather.RAIN else (1.5 if current_weather == Weather.STORM else 0.0)
	var to_rain = 1.0 if target_weather == Weather.RAIN else (1.5 if target_weather == Weather.STORM else 0.0)
	current_rain_intensity = lerpf(from_rain, to_rain, t)

	# Appliquer preset nuages
	if cloud_manager:
		cloud_manager.set_cloud_preset(current_cloud_preset[0], current_cloud_preset[1],
										current_cloud_preset[2], current_cloud_preset[3])

	# Transition terminée
	if transition_progress >= 1.0:
		current_weather = target_weather

func _update_rain_particles():
	if not player or not rain_particles:
		return

	# Positionner au-dessus du joueur
	rain_particles.global_position = Vector3(
		player.global_position.x,
		player.global_position.y + RAIN_AREA.y * 0.8,
		player.global_position.z
	)

	if current_rain_intensity > 0.01:
		if not rain_particles.emitting:
			rain_particles.emitting = true

		# Storm = plus de particules, plus rapides
		if current_rain_intensity > 1.2:
			rain_particles.amount = STORM_PARTICLE_COUNT
			rain_process_material.initial_velocity_min = STORM_SPEED_MIN
			rain_process_material.initial_velocity_max = STORM_SPEED_MAX
			rain_process_material.spread = 8.0
		else:
			rain_particles.amount = maxi(100, int(RAIN_PARTICLE_COUNT * current_rain_intensity))
			rain_process_material.initial_velocity_min = RAIN_SPEED_MIN
			rain_process_material.initial_velocity_max = RAIN_SPEED_MAX
			rain_process_material.spread = 3.0
	else:
		if rain_particles.emitting:
			rain_particles.emitting = false

func _update_rain_audio(delta):
	if not rain_audio or not rain_audio.stream:
		return

	if current_rain_intensity > 0.01:
		var ambient_vol = 0.7
		var master_vol = 1.0
		if audio_manager:
			if "ambient_volume" in audio_manager:
				ambient_vol = audio_manager.ambient_volume
			if "master_volume" in audio_manager:
				master_vol = audio_manager.master_volume

		var intensity_factor = clampf(current_rain_intensity, 0.0, 1.5) / 1.5
		rain_volume_target = linear_to_db(intensity_factor * ambient_vol * master_vol) + RAIN_VOLUME_MAX
		rain_volume_target = clampf(rain_volume_target, -80.0, RAIN_VOLUME_MAX)

		if not rain_audio.playing:
			rain_audio.play()
	else:
		rain_volume_target = -80.0

	# Fade progressif
	rain_audio.volume_db = move_toward(rain_audio.volume_db, rain_volume_target, RAIN_VOLUME_FADE_SPEED * delta)

	# Arrêter si inaudible
	if rain_audio.volume_db <= -79.0 and rain_audio.playing and current_rain_intensity <= 0.01:
		rain_audio.stop()

func _update_environment():
	if not env or not day_night_cycle:
		return

	var sun_height: float = -cos(day_night_cycle.current_time * TAU)

	# Fog density (combiné jour/nuit + météo)
	var base_fog: float
	if sun_height < -0.1:
		base_fog = 0.003
	elif sun_height < 0.1:
		base_fog = lerpf(0.003, current_fog_density, (sun_height + 0.1) / 0.2)
	else:
		base_fog = current_fog_density
	env.fog_density = base_fog

	# ---- Assombrissement du ciel (background_color) pendant la pluie/orage ----
	# day_night_cycle a déjà défini background_color ce frame, on le modifie après
	if current_rain_intensity > 0.01 and sun_height > -0.15:
		var rain_t = clampf(current_rain_intensity, 0.0, 1.0)
		var storm_t = clampf((current_rain_intensity - 1.0) / 0.5, 0.0, 1.0)  # 0 pour pluie, 1 pour orage max

		# Couleur ciel cible : lerp entre rain overcast et storm overcast
		var overcast_color = SKY_OVERCAST_RAIN.lerp(SKY_OVERCAST_STORM, storm_t)

		# Blend fort vers le gris couvert — rain_t contrôle l'intensité du blend
		env.background_color = env.background_color.lerp(overcast_color, rain_t * 0.85)

	# ---- Fog grisâtre quand il pleut ----
	if sun_height > -0.1 and current_rain_intensity > 0.1:
		var rain_t = clampf(current_rain_intensity, 0.0, 1.0)
		var storm_t = clampf((current_rain_intensity - 1.0) / 0.5, 0.0, 1.0)
		var rain_fog_color = SKY_OVERCAST_RAIN.lerp(SKY_OVERCAST_STORM, storm_t)
		env.fog_light_color = env.fog_light_color.lerp(rain_fog_color, rain_t * 0.8)

	# ---- Réduire fog_light_energy pendant la pluie ----
	if current_rain_intensity > 0.01 and sun_height > -0.1:
		var rain_t = clampf(current_rain_intensity, 0.0, 1.0)
		env.fog_light_energy *= lerpf(1.0, 0.3, rain_t)

	# ---- Réduire ambient_light_energy pendant la pluie (en plus du sun light_factor) ----
	if current_rain_intensity > 0.01 and sun_height > -0.1:
		var rain_t = clampf(current_rain_intensity, 0.0, 1.0)
		var storm_t = clampf((current_rain_intensity - 1.0) / 0.5, 0.0, 1.0)
		# Pluie: réduire ambient de 30%, orage: réduire de 55%
		var ambient_factor = lerpf(1.0, lerpf(0.7, 0.45, storm_t), rain_t)
		env.ambient_light_energy *= ambient_factor
		# Teinter légèrement l'ambient en gris
		env.ambient_light_color = env.ambient_light_color.lerp(Color(0.6, 0.62, 0.68), rain_t * 0.5)

func _update_lightning(delta):
	if current_weather != Weather.STORM and target_weather != Weather.STORM:
		if is_flashing:
			_end_lightning_flash()
		return

	if is_flashing:
		lightning_flash_time -= delta
		if lightning_flash_time <= 0.0:
			_end_lightning_flash()
		return

	lightning_timer -= delta
	if lightning_timer <= 0.0:
		_start_lightning_flash()
		lightning_timer = randf_range(4.0, 15.0)

func _start_lightning_flash():
	is_flashing = true
	lightning_flash_time = randf_range(0.08, 0.2)

	# Flash blanc bref sur l'ambient
	if env:
		env.ambient_light_energy = 1.5
		env.ambient_light_color = Color(0.95, 0.95, 1.0)

	# Son tonnerre (délai aléatoire après éclair)
	if audio_manager:
		var thunder_delay = randf_range(0.3, 2.0)
		get_tree().create_timer(thunder_delay).timeout.connect(_play_thunder)

func _end_lightning_flash():
	is_flashing = false
	# Le day_night_cycle va restaurer les valeurs normales au prochain frame

func _play_thunder():
	if not audio_manager or not audio_manager.has_method("_get_free_sfx"):
		return
	var thunder_player = audio_manager._get_free_sfx()
	if not thunder_player:
		return
	# Choisir un son de tonnerre aléatoire parmi les 3 disponibles
	var thunder_files = [
		"res://Audio/thunder-1.mp3",
		"res://Audio/thunder-2.mp3",
		"res://Audio/thunder-3.mp3",
	]
	var thunder_stream = load(thunder_files[randi() % thunder_files.size()])
	if thunder_stream:
		thunder_player.stream = thunder_stream
		thunder_player.volume_db = randf_range(-6.0, -2.0)
		thunder_player.play()

# ---- API publique ----

## Forcer un état météo (avec transition douce)
func set_weather(weather: Weather):
	target_weather = weather
	if target_weather != current_weather:
		transition_progress = 0.0
	_schedule_next_weather()

## Forcer immédiatement (sans transition)
func set_weather_immediate(weather: Weather):
	current_weather = weather
	target_weather = weather
	transition_progress = 1.0
	current_light_factor = LIGHT_FACTORS[weather]
	current_fog_density = FOG_DENSITY[weather]
	current_cloud_preset = CLOUD_PRESETS[weather].duplicate()

	var rain_vals = {Weather.CLEAR: 0.0, Weather.CLOUDY: 0.0, Weather.RAIN: 1.0, Weather.STORM: 1.5}
	current_rain_intensity = rain_vals[weather]

	if cloud_manager:
		cloud_manager.set_cloud_preset(current_cloud_preset[0], current_cloud_preset[1],
										current_cloud_preset[2], current_cloud_preset[3])
	_schedule_next_weather()

func get_weather_name() -> String:
	if transition_progress < 1.0:
		return WEATHER_NAMES[current_weather] + " -> " + WEATHER_NAMES[target_weather]
	return WEATHER_NAMES[current_weather]

func get_light_factor() -> float:
	return current_light_factor

func get_rain_intensity() -> float:
	return current_rain_intensity

func is_raining() -> bool:
	return current_rain_intensity > 0.1
