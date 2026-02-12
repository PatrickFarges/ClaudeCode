extends Control

@onready var version_label: Label = $VersionLabel
@onready var fps_label: Label = $FPSLabel
@onready var biome_label: Label

const VERSION = "v7.1"

var audio_manager = null

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
	
	await get_tree().process_frame
	audio_manager = get_tree().get_first_node_in_group("audio_manager")

func _process(_delta):
	fps_label.text = Locale.tr_ui("fps") % Engine.get_frames_per_second()
	
	if audio_manager:
		var biome_names = {
			0: "🏜️ " + Locale.tr_ui("biome_desert"),
			1: "🌲 " + Locale.tr_ui("biome_forest"),
			2: "⛰️ " + Locale.tr_ui("biome_mountain"),
			3: "🌾 " + Locale.tr_ui("biome_plains"),
		}
		var biome_id = audio_manager.current_biome
		biome_label.text = biome_names.get(biome_id, "???")
		
		# Afficher l'altitude en montagne
		if biome_id == 2:
			biome_label.text += " (Y:%d)" % int(audio_manager.current_height)
