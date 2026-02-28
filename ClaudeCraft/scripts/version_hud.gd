extends Control

@onready var version_label: Label = $VersionLabel
@onready var fps_label: Label = $FPSLabel
var biome_label: Label
var time_label: Label
var speed_label: Label
var target_label: Label

const VERSION = "v14.0.0"

var audio_manager = null
var player = null
var day_night_cycle = null

# Glissière de vitesse
var speed_slider: HSlider
var speed_container: HBoxContainer

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

	# Contrôle de vitesse du temps (sous l'heure)
	speed_container = HBoxContainer.new()
	speed_container.position = Vector2(0, 96)
	speed_container.size = Vector2(250, 24)
	add_child(speed_container)

	var speed_icon = Label.new()
	speed_icon.text = "⏩ "
	speed_icon.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.7))
	speed_icon.add_theme_font_size_override("font_size", 13)
	speed_container.add_child(speed_icon)

	speed_slider = HSlider.new()
	speed_slider.min_value = 0
	speed_slider.max_value = 3
	speed_slider.step = 1
	speed_slider.value = 1  # Normal par défaut
	speed_slider.custom_minimum_size = Vector2(100, 20)
	speed_slider.value_changed.connect(_on_speed_changed)
	speed_container.add_child(speed_slider)

	speed_label = Label.new()
	speed_label.text = " Normal"
	speed_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.7))
	speed_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	speed_label.add_theme_constant_override("shadow_offset_x", 1)
	speed_label.add_theme_constant_override("shadow_offset_y", 1)
	speed_label.add_theme_font_size_override("font_size", 13)
	speed_container.add_child(speed_label)

	# Label bloc ciblé (décalé vers le bas pour la glissière)
	target_label = Label.new()
	target_label.position = Vector2(0, 122)
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

func _on_speed_changed(value: float):
	if day_night_cycle:
		day_night_cycle.set_speed(int(value))
		speed_label.text = " " + day_night_cycle.get_speed_name()
		# Couleur selon la vitesse
		var colors = [
			Color(0.5, 0.7, 1.0, 0.7),   # Lent — bleu
			Color(0.7, 0.85, 1.0, 0.7),   # Normal — blanc-bleu
			Color(1.0, 0.85, 0.4, 0.7),   # Rapide — jaune
			Color(1.0, 0.5, 0.3, 0.7),    # Très rapide — orange
		]
		speed_label.add_theme_color_override("font_color", colors[int(value)])

func _unhandled_input(event):
	# Raccourcis clavier [ et ] pour changer la vitesse du temps
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BRACKETLEFT:  # [
			speed_slider.value = maxi(0, int(speed_slider.value) - 1)
		elif event.keycode == KEY_BRACKETRIGHT:  # ]
			speed_slider.value = mini(3, int(speed_slider.value) + 1)

func _process(_delta):
	fps_label.text = Locale.tr_ui("fps") % Engine.get_frames_per_second()

	# Biome
	if audio_manager:
		var biome_names = {
			0: "🏜️ " + Locale.tr_ui("biome_desert"),
			1: "🌲 " + Locale.tr_ui("biome_forest"),
			2: "⛰️ " + Locale.tr_ui("biome_mountain"),
			3: "🌾 " + Locale.tr_ui("biome_plains"),
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
		time_label.text = "🕐 " + day_night_cycle.get_time_string() + speed_txt
	else:
		time_label.text = ""

	# Bloc ciblé
	if player and player.look_block_type != BlockRegistry.BlockType.AIR:
		target_label.text = "🎯 " + BlockRegistry.get_block_name(player.look_block_type)
	else:
		target_label.text = ""
