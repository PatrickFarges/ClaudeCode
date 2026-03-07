extends Control

@onready var version_label: Label = $VersionLabel
@onready var fps_label: Label = $FPSLabel
var biome_label: Label
var time_label: Label
var speed_label: Label
var render_label: Label
var target_label: Label

const VERSION = "v17.0.0"

var audio_manager = null
var player = null
var day_night_cycle = null

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

	# Label bloc ciblé (décalé plus bas)
	target_label = Label.new()
	target_label.position = Vector2(0, 142)
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

	# Récupérer l'Environment pour les presets de rendu
	for child in get_tree().current_scene.get_children():
		if child is WorldEnvironment:
			_env = child.environment
			break

	# Charger le preset de rendu sauvegardé (ou Cloclo Style par défaut)
	# Attendre 2 frames supplémentaires pour que la scène soit 100% initialisée
	# (sinon les valeurs par défaut de l'Environment écrasent notre preset)
	if _env:
		await get_tree().process_frame
		await get_tree().process_frame
		var saved_preset = 2  # Cloclo Style par défaut
		var cfg = ConfigFile.new()
		if cfg.load("user://settings.cfg") == OK and cfg.has_section_key("game", "render_preset"):
			saved_preset = int(cfg.get_value("game", "render_preset"))
			if saved_preset < 0 or saved_preset >= RENDER_NAMES.size():
				saved_preset = 2
		_render_preset = saved_preset
		match _render_preset:
			0: _apply_vanilla()
			1: _apply_gi()
			2: _apply_cinematic()
			3: _apply_enb_sombre()
			4: _apply_reshade_epique()
		render_label.text = "Rendu : %s (F2)" % RENDER_NAMES[_render_preset]
		render_label.add_theme_color_override("font_color", RENDER_COLORS[_render_preset])
		# Charger aussi la vitesse du temps
		var settings_menu = get_tree().current_scene.get_node_or_null("SettingsMenu")
		if settings_menu:
			settings_menu.load_settings()

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
		print("RenderPresets: pas d'Environment trouvé!")
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
	print("Render preset: %s" % RENDER_NAMES[_render_preset])

func _apply_vanilla():
	_env.sdfgi_enabled = false
	_env.ssil_enabled = false
	_env.glow_enabled = false
	_env.volumetric_fog_enabled = false
	_env.adjustment_enabled = false

	_env.tonemap_mode = 2
	_env.tonemap_white = 6.0
	_env.tonemap_exposure = 1.0

	_env.ssao_enabled = true
	_env.ssao_radius = 2.0
	_env.ssao_intensity = 1.5
	_env.ssao_power = 1.5
	_env.ssao_detail = 0.5
	_env.ssao_sharpness = 0.5

	_env.fog_enabled = true
	_env.fog_density = 0.012
	_env.fog_aerial_perspective = 0.6
	_env.fog_light_color = Color(0.7, 0.85, 0.95, 1)
	_env.fog_light_energy = 1.0

	_env.ambient_light_source = 2
	_env.ambient_light_color = Color(1, 1, 1, 1)
	_env.ambient_light_energy = 0.5

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

	_env.ambient_light_energy = 0.25

func _apply_cinematic():
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

	# SSAO adouci (moins de noirceur)
	_env.ssao_enabled = true
	_env.ssao_radius = 2.5
	_env.ssao_intensity = 1.8
	_env.ssao_power = 1.5
	_env.ssao_detail = 0.6
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
	_env.ambient_light_energy = 0.35

	# Color grading — vibrance pour des couleurs vivantes
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.5
	_env.adjustment_contrast = 1.12
	_env.adjustment_brightness = 1.0

func _apply_enb_sombre():
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
	_env.ssao_radius = 2.0
	_env.ssao_intensity = 1.5
	_env.ssao_power = 1.3
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
	_env.ambient_light_energy = 0.32

	# Color grading — saturation forte, contraste, warmth
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.5
	_env.adjustment_contrast = 1.18
	_env.adjustment_brightness = 0.97

func _apply_reshade_epique():
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
	_env.ssao_radius = 2.0
	_env.ssao_intensity = 1.5
	_env.ssao_power = 1.3
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
	_env.ambient_light_energy = 0.28

	# Color grading — verts profonds, contraste élevé, ombres froides highlights chaudes
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.45
	_env.adjustment_contrast = 1.3
	_env.adjustment_brightness = 0.88

func _process(_delta):
	fps_label.text = Locale.tr_ui("fps") % Engine.get_frames_per_second()

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

	# Bloc ciblé
	if player and player.look_block_type != BlockRegistry.BlockType.AIR:
		target_label.text = BlockRegistry.get_block_name(player.look_block_type)
	else:
		target_label.text = ""
