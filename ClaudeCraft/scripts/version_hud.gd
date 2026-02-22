extends Control

@onready var version_label: Label = $VersionLabel
@onready var fps_label: Label = $FPSLabel
var biome_label: Label
var time_label: Label
var target_label: Label

const VERSION = "v8.1.0"

var audio_manager = null
var player = null
var day_night_cycle = null

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

	# Label bloc ciblé
	target_label = Label.new()
	target_label.position = Vector2(0, 96)
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

	# Heure
	if day_night_cycle:
		time_label.text = "🕐 " + day_night_cycle.get_time_string()
	else:
		time_label.text = ""

	# Bloc ciblé
	if player and player.look_block_type != BlockRegistry.BlockType.AIR:
		target_label.text = "🎯 " + BlockRegistry.get_block_name(player.look_block_type)
	else:
		target_label.text = ""
