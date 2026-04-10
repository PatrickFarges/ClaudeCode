extends Control

@onready var version_label: Label = $VersionLabel
@onready var fps_label: Label = $FPSLabel
var biome_label: Label
var time_label: Label
var speed_label: Label
var render_label: Label
var target_label: Label
var weather_label: Label

const VERSION = "v21.6.0"

var audio_manager = null
var player = null
var day_night_cycle = null
var cloud_manager = null
var weather_manager = null
var _pending_preset: int = -1  # preset à appliquer après warmup
var _warmup_frames: int = 0    # compteur de frames avant application
var _hud_timer: float = 0.0    # throttle non-FPS HUD updates

# === Render presets ===
var _render_preset: int = 0
var _env: Environment = null
const RENDER_NAMES = ["Vanilla", "Global Illumination", "Cloclo Style", "ENB Sombre", "ReShade Epique"]
const RENDER_COLORS = [
	Color(0.7, 0.7, 0.7, 0.7),    # Vanilla — gris
	Color(0.4, 0.9, 0.5, 0.7),    # GI — vert
	Color(0.9, 0.6, 1.0, 0.7),    # Cloclo Style — violet
	Color(1.0, 0.7, 0.3, 0.7),    # ENB Sombre — or
	Color(0.3, 0.8, 1.0, 0.7),    # ReShade Epique — cyan
]

const SPEED_COLORS = [
	Color(0.5, 0.7, 1.0, 0.7),   # Lent — bleu
	Color(0.7, 0.85, 1.0, 0.7),   # Normal — blanc-bleu
	Color(1.0, 0.85, 0.4, 0.7),   # Rapide — jaune
	Color(1.0, 0.5, 0.3, 0.7),    # Très rapide — orange
]

func _ready():
	version_label.text = "ClaudeCraft " + VERSION
	position = Vector2(10, 10)

	# Label biome
	biome_label = Label.new()
	biome_label.position = Vector2(0, 50)
	biome_label.size = Vector2(300, 23)
	biome_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.7))
	biome_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	biome_label.add_theme_constant_override("shadow_offset_x", 1)
	biome_label.add_theme_constant_override("shadow_offset_y", 1)
	biome_label.add_theme_font_size_override("font_size", 14)
	add_child(biome_label)

	# Label heure
	time_label = Label.new()
	time_label.position = Vector2(0, 73)
	time_label.size = Vector2(300, 23)
	time_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 0.7))
	time_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	time_label.add_theme_constant_override("shadow_offset_x", 1)
	time_label.add_theme_constant_override("shadow_offset_y", 1)
	time_label.add_theme_font_size_override("font_size", 14)
	add_child(time_label)

	# Label vitesse (sous l'heure)
	speed_label = Label.new()
	speed_label.position = Vector2(0, 96)
	speed_label.size = Vector2(350, 23)
	speed_label.add_theme_color_override("font_color", SPEED_COLORS[1])
	speed_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	speed_label.add_theme_constant_override("shadow_offset_x", 1)
	speed_label.add_theme_constant_override("shadow_offset_y", 1)
	speed_label.add_theme_font_size_override("font_size", 13)
	speed_label.text = "Normal (Ctrl+Molette)"
	add_child(speed_label)

	# Label render preset (sous la vitesse)
	render_label = Label.new()
	render_label.position = Vector2(0, 119)
	render_label.size = Vector2(350, 23)
	render_label.add_theme_color_override("font_color", RENDER_COLORS[0])
	render_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	render_label.add_theme_constant_override("shadow_offset_x", 1)
	render_label.add_theme_constant_override("shadow_offset_y", 1)
	render_label.add_theme_font_size_override("font_size", 13)
	render_label.text = "Rendu : Vanilla (F2)"
	add_child(render_label)

	# Label météo (sous le render)
	weather_label = Label.new()
	weather_label.position = Vector2(0, 142)
	weather_label.size = Vector2(350, 23)
	weather_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.95, 0.7))
	weather_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	weather_label.add_theme_constant_override("shadow_offset_x", 1)
	weather_label.add_theme_constant_override("shadow_offset_y", 1)
	weather_label.add_theme_font_size_override("font_size", 13)
	add_child(weather_label)

	# Label bloc ciblé (décalé plus bas)
	target_label = Label.new()
	target_label.position = Vector2(0, 165)
	target_label.size = Vector2(300, 23)
	target_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.7))
	target_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	target_label.add_theme_constant_override("shadow_offset_x", 1)
	target_label.add_theme_constant_override("shadow_offset_y", 1)
	target_label.add_theme_font_size_override("font_size", 14)
	add_child(target_label)

	await get_tree().process_frame
	audio_manager = get_tree().get_first_node_in_group("audio_manager")
	player = get_tree().get_first_node_in_group("player")
	day_night_cycle = get_tree().get_first_node_in_group("day_night_cycle")
	cloud_manager = get_tree().get_first_node_in_group("cloud_manager")
	weather_manager = get_tree().get_first_node_in_group("weather_manager")

	# Récupérer l'Environment pour les presets de rendu
	for child in get_tree().current_scene.get_children():
		if child is WorldEnvironment:
			_env = child.environment
			break

	# Charger le preset sauvegardé — appliqué UNIQUEMENT après warmup
	# (SSAO/SDFGI doivent s'initialiser avec de la géométrie dans le depth buffer)
	var saved_preset = 2  # Cloclo Style par défaut
	var cfg = ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK and cfg.has_section_key("game", "render_preset"):
		saved_preset = int(cfg.get_value("game", "render_preset"))
		if saved_preset < 0 or saved_preset >= RENDER_NAMES.size():
			saved_preset = 2
	_render_preset = saved_preset
	render_label.text = "Rendu : %s (F2)" % RENDER_NAMES[_render_preset]
	render_label.add_theme_color_override("font_color", RENDER_COLORS[_render_preset])
	_pending_preset = saved_preset

func _input(event):
	# Ctrl gauche + molette souris = changer la vitesse du temps
	if event is InputEventMouseButton and event.pressed and event.ctrl_pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_speed(1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_speed(-1)
			get_viewport().set_input_as_handled()

	# F2 = cycler les presets de rendu
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			_cycle_render_preset()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F4:
			_cycle_weather()
			get_viewport().set_input_as_handled()

func _change_speed(direction: int):
	if not day_night_cycle:
		return
	var new_index = clampi(day_night_cycle.speed_index + direction, 0, 3)
	day_night_cycle.set_speed(new_index)
	_update_speed_label()

func _update_speed_label():
	if not day_night_cycle:
		return
	var idx = day_night_cycle.speed_index
	var sname = day_night_cycle.get_speed_name()
	var bars = ["▰▱▱▱", "▰▰▱▱", "▰▰▰▱", "▰▰▰▰"]
	speed_label.text = "%s %s" % [bars[idx], sname]
	speed_label.add_theme_color_override("font_color", SPEED_COLORS[idx])

# === Render presets ===

func _cycle_render_preset():
	if not _env:
		#print("RenderPresets: pas d'Environment trouvé!")
		return
	_render_preset = (_render_preset + 1) % RENDER_NAMES.size()
	match _render_preset:
		0:
			_apply_vanilla()
		1:
			_apply_gi()
		2:
			_apply_cinematic()
		3:
			_apply_enb_sombre()
		4:
			_apply_reshade_epique()
	render_label.text = "Rendu : %s (F2)" % RENDER_NAMES[_render_preset]
	render_label.add_theme_color_override("font_color", RENDER_COLORS[_render_preset])
	#print("Render preset: %s" % RENDER_NAMES[_render_preset])

func _reset_env():
	# Reset TOUTES les propriétés post-process à un état neutre
	# (évite que les valeurs de main.tscn ou d'un preset précédent persistent)
	_env.sdfgi_enabled = false
	_env.ssil_enabled = false
	_env.glow_enabled = false
	_env.volumetric_fog_enabled = false
	_env.adjustment_enabled = false
	_env.ssao_enabled = false
	_env.fog_enabled = false
	_env.fog_sky_affect = 0.0
	_env.tonemap_mode = 0
	_env.tonemap_white = 1.0
	_env.tonemap_exposure = 1.0
	_env.ambient_light_source = 0
	_env.ambient_light_energy = 0.0

func _apply_vanilla():
	_reset_env()
	_env.glow_enabled = false
	_env.volumetric_fog_enabled = false
	_env.adjustment_enabled = false

	_env.tonemap_mode = 0  # Linear — comme Bedrock Edition
	_env.tonemap_white = 1.0
	_env.tonemap_exposure = 1.0

	_env.ssao_enabled = true
	_env.ssao_radius = 1.5
	_env.ssao_intensity = 0.8
	_env.ssao_power = 1.2
	_env.ssao_detail = 0.5
	_env.ssao_sharpness = 0.5

	_env.fog_enabled = true
	_env.fog_density = 0.006
	_env.fog_aerial_perspective = 0.3
	_env.fog_light_color = Color(0.7, 0.85, 0.95, 1)
	_env.fog_light_energy = 0.5
	_env.fog_sun_scatter = 0.1  # Réduit la tache blanche vers le soleil

	_env.ambient_light_source = 2
	_env.ambient_light_color = Color(1, 1, 1, 1)
	_env.ambient_light_energy = 0.12

	# Nuages : nets, style Minecraft
	if cloud_manager:
		cloud_manager.set_cloud_preset(0.45, 0.75, 0.25, 0.008)

func _apply_gi():
	_apply_vanilla()

	_env.sdfgi_enabled = true
	_env.sdfgi_use_occlusion = true
	_env.sdfgi_cascades = 4
	_env.sdfgi_min_cell_size = 0.5
	_env.sdfgi_energy = 1.0
	_env.sdfgi_normal_bias = 1.1
	_env.sdfgi_probe_bias = 1.1
	_env.sdfgi_bounce_feedback = 0.5

	_env.ambient_light_energy = 0.08

	# Nuages : mêmes que Vanilla
	if cloud_manager:
		cloud_manager.set_cloud_preset(0.45, 0.75, 0.25, 0.008)

func _apply_cinematic():
	_reset_env()
	# SDFGI
	_env.sdfgi_enabled = true
	_env.sdfgi_use_occlusion = true
	_env.sdfgi_cascades = 4
	_env.sdfgi_min_cell_size = 0.5
	_env.sdfgi_energy = 1.4
	_env.sdfgi_normal_bias = 1.1
	_env.sdfgi_probe_bias = 1.1
	_env.sdfgi_bounce_feedback = 0.7

	# SSIL
	_env.ssil_enabled = true
	_env.ssil_radius = 5.0
	_env.ssil_intensity = 0.8
	_env.ssil_normal_rejection = 1.0

	# Tonemap Filmic — preserve mieux les couleurs que ACES
	_env.tonemap_mode = 2
	_env.tonemap_white = 5.0
	_env.tonemap_exposure = 1.2

	# SSAO adouci
	_env.ssao_enabled = true
	_env.ssao_radius = 1.5
	_env.ssao_intensity = 0.8
	_env.ssao_power = 1.2
	_env.ssao_detail = 0.5
	_env.ssao_sharpness = 0.5

	# Glow
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_strength = 0.8
	_env.glow_bloom = 0.08
	_env.glow_blend_mode = 2
	_env.glow_hdr_threshold = 1.0

	# Volumetric Fog — quasi invisible, juste pour les god rays subtils
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.001
	_env.volumetric_fog_albedo = Color(0.85, 0.9, 0.95, 1)
	_env.volumetric_fog_emission = Color(0.0, 0.0, 0.0, 1)
	_env.volumetric_fog_anisotropy = 0.8
	_env.volumetric_fog_gi_inject = 1.0

	# Fog distance — subtil, profondeur seulement a l'horizon
	_env.fog_enabled = true
	_env.fog_density = 0.002
	_env.fog_aerial_perspective = 0.35
	_env.fog_light_color = Color(0.75, 0.88, 0.97, 1)
	_env.fog_light_energy = 0.7

	# Ambient releve pour des couleurs plus vivantes
	_env.ambient_light_source = 2
	_env.ambient_light_color = Color(1, 1, 1, 1)
	_env.ambient_light_energy = 0.1

	# Color grading — vibrance pour des couleurs vivantes
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.5
	_env.adjustment_contrast = 1.08
	_env.adjustment_brightness = 1.0

	# Nuages : doux, rêveurs
	if cloud_manager:
		cloud_manager.set_cloud_preset(0.40, 0.70, 0.35, 0.01)

func _apply_enb_sombre():
	_reset_env()
	# Inspiré ENB Series Skyrim — lumière dorée chaude, couleurs riches, ambiance golden hour
	# SDFGI avec bounce élevé pour illumination indirecte chaude
	_env.sdfgi_enabled = true
	_env.sdfgi_use_occlusion = true
	_env.sdfgi_cascades = 4
	_env.sdfgi_min_cell_size = 0.5
	_env.sdfgi_energy = 1.1
	_env.sdfgi_normal_bias = 1.1
	_env.sdfgi_probe_bias = 1.1
	_env.sdfgi_bounce_feedback = 0.6

	# SSIL — lumière indirecte pour remplir les ombres
	_env.ssil_enabled = true
	_env.ssil_radius = 5.0
	_env.ssil_intensity = 0.7
	_env.ssil_normal_rejection = 1.0

	# Tonemap Filmic — comme ReShade mais avec tonalité chaude
	_env.tonemap_mode = 2
	_env.tonemap_white = 5.0
	_env.tonemap_exposure = 1.05

	# SSAO doux
	_env.ssao_enabled = true
	_env.ssao_radius = 1.5
	_env.ssao_intensity = 0.8
	_env.ssao_power = 1.2
	_env.ssao_detail = 0.5
	_env.ssao_sharpness = 0.5

	# Glow chaud — lueur dorée sur les highlights
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_strength = 0.8
	_env.glow_bloom = 0.06
	_env.glow_blend_mode = 2
	_env.glow_hdr_threshold = 0.9

	# Volumetric fog doré
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.002
	_env.volumetric_fog_albedo = Color(0.9, 0.82, 0.7, 1)
	_env.volumetric_fog_emission = Color(0.0, 0.0, 0.0, 1)
	_env.volumetric_fog_anisotropy = 0.8
	_env.volumetric_fog_gi_inject = 1.0

	# Fog distance — brume chaude ambrée
	_env.fog_enabled = true
	_env.fog_density = 0.003
	_env.fog_aerial_perspective = 0.5
	_env.fog_light_color = Color(0.85, 0.75, 0.6, 1)
	_env.fog_light_energy = 0.7

	# Ambient chaud — tons dorés dans les ombres
	_env.ambient_light_source = 2
	_env.ambient_light_color = Color(1.0, 0.92, 0.8, 1)
	_env.ambient_light_energy = 0.08

	# Color grading — saturation forte, contraste, warmth
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.5
	_env.adjustment_contrast = 1.1
	_env.adjustment_brightness = 0.98

	# Nuages : couverture élevée, brume dorée
	if cloud_manager:
		cloud_manager.set_cloud_preset(0.50, 0.60, 0.30, 0.012)

func _apply_reshade_epique():
	_reset_env()
	# Inspiré ReShade presets — cinématique dramatique, couleurs profondes, ambiance épique
	# SDFGI avec énergie modérée
	_env.sdfgi_enabled = true
	_env.sdfgi_use_occlusion = true
	_env.sdfgi_cascades = 4
	_env.sdfgi_min_cell_size = 0.5
	_env.sdfgi_energy = 1.0
	_env.sdfgi_normal_bias = 1.1
	_env.sdfgi_probe_bias = 1.1
	_env.sdfgi_bounce_feedback = 0.5

	# SSIL
	_env.ssil_enabled = true
	_env.ssil_radius = 5.0
	_env.ssil_intensity = 0.6
	_env.ssil_normal_rejection = 1.0

	# Tonemap Filmic — rendu film, noirs doux mais profonds
	_env.tonemap_mode = 2
	_env.tonemap_white = 4.0
	_env.tonemap_exposure = 1.0

	# SSAO modéré — profondeur sans noircir
	_env.ssao_enabled = true
	_env.ssao_radius = 1.5
	_env.ssao_intensity = 0.8
	_env.ssao_power = 1.2
	_env.ssao_detail = 0.5
	_env.ssao_sharpness = 0.5

	# Glow — chaleur dorée dans les highlights
	_env.glow_enabled = true
	_env.glow_intensity = 0.5
	_env.glow_strength = 0.7
	_env.glow_bloom = 0.05
	_env.glow_blend_mode = 2
	_env.glow_hdr_threshold = 0.9

	# Volumetric fog — brume atmosphérique type forêt enchantée
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.003
	_env.volumetric_fog_albedo = Color(0.7, 0.75, 0.8, 1)
	_env.volumetric_fog_emission = Color(0.0, 0.0, 0.0, 1)
	_env.volumetric_fog_anisotropy = 0.85
	_env.volumetric_fog_gi_inject = 1.2

	# Fog distance — brume lointaine bleutée
	_env.fog_enabled = true
	_env.fog_density = 0.006
	_env.fog_aerial_perspective = 0.7
	_env.fog_light_color = Color(0.55, 0.65, 0.8, 1)
	_env.fog_light_energy = 0.6

	# Ambient — ombres lisibles mais profondes
	_env.ambient_light_source = 2
	_env.ambient_light_color = Color(0.8, 0.85, 1.0, 1)
	_env.ambient_light_energy = 0.06

	# Color grading — verts profonds, contraste modéré, ombres froides highlights chaudes
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.45
	_env.adjustment_contrast = 1.15
	_env.adjustment_brightness = 0.92

	# Nuages : dramatiques, plus de couverture
	if cloud_manager:
		cloud_manager.set_cloud_preset(0.55, 0.65, 0.35, 0.015)

func _cycle_weather():
	if not weather_manager:
		return
	var next_w = (weather_manager.current_weather + 1) % 4
	weather_manager.set_weather(next_w)

func _process(delta):
	# Appliquer le preset sauvegardé après warmup (le renderer a besoin de
	# quelques frames avec de la géométrie pour que SSAO/SDFGI fonctionnent)
	if _pending_preset >= 0 and _env:
		_warmup_frames += 1
		if _warmup_frames >= 30:
			_render_preset = _pending_preset
			_pending_preset = -1
			_warmup_frames = 0
			match _render_preset:
				0: _apply_vanilla()
				1: _apply_gi()
				2: _apply_cinematic()
				3: _apply_enb_sombre()
				4: _apply_reshade_epique()
			render_label.text = "Rendu : %s (F2)" % RENDER_NAMES[_render_preset]
			render_label.add_theme_color_override("font_color", RENDER_COLORS[_render_preset])

	# FPS — every frame
	fps_label.text = Locale.tr_ui("fps") % Engine.get_frames_per_second()

	# Throttle non-FPS updates to ~5 times/sec
	_hud_timer += delta
	if _hud_timer < 0.2:
		return
	_hud_timer = 0.0

	# Biome
	if audio_manager:
		var biome_names = {
			0: Locale.tr_ui("biome_desert"),
			1: Locale.tr_ui("biome_forest"),
			2: Locale.tr_ui("biome_mountain"),
			3: Locale.tr_ui("biome_plains"),
		}
		var biome_id = audio_manager.current_biome
		biome_label.text = biome_names.get(biome_id, "???")
		if biome_id == 2:
			biome_label.text += " (Y:%d)" % int(audio_manager.current_height)

	# Heure + vitesse
	if day_night_cycle:
		var speed_txt = ""
		if day_night_cycle.speed_index != 1:
			speed_txt = " [x%s]" % str(day_night_cycle.get_speed_multiplier())
		time_label.text = day_night_cycle.get_time_string() + speed_txt
	else:
		time_label.text = ""

	# Météo
	if weather_manager:
		var wname = weather_manager.get_weather_name()
		var weather_icons = {
			"Clair": "☀",
			"Nuageux": "☁",
			"Pluie": "🌧",
			"Orage": "⛈",
		}
		# Chercher l'icône dans le nom (peut être "Clair -> Pluie")
		var icon = "☀"
		for key in weather_icons:
			if wname.ends_with(key):
				icon = weather_icons[key]
				break
		weather_label.text = "%s Météo : %s" % [icon, wname]
	else:
		weather_label.text = ""

	# Bloc ciblé
	if player and player.look_block_type != BlockRegistry.BlockType.AIR:
		target_label.text = BlockRegistry.get_block_name(player.look_block_type)
	else:
		target_label.text = ""
