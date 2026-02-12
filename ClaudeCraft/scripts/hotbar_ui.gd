extends CanvasLayer

@onready var hotbar: HBoxContainer = $MarginContainer/HBoxContainer
var slot_panels: Array = []
var player: CharacterBody3D

const NUM_SLOTS = 9

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	
	_create_hotbar_slots()
	_update_hotbar()

func _create_hotbar_slots():
	for i in range(NUM_SLOTS):
		var panel = Panel.new()
		panel.custom_minimum_size = Vector2(56, 56)
		
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.5, 0.5, 0.5, 1.0)
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_left = 3
		style.corner_radius_bottom_right = 3
		panel.add_theme_stylebox_override("panel", style)
		
		var num_label = Label.new()
		num_label.text = str(i + 1)
		num_label.position = Vector2(3, 1)
		num_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.7))
		num_label.add_theme_font_size_override("font_size", 10)
		panel.add_child(num_label)
		
		var color_rect = ColorRect.new()
		color_rect.size = Vector2(36, 36)
		color_rect.position = Vector2(10, 12)
		panel.add_child(color_rect)
		
		# Label quantité — bien lisible avec outline noir
		var count_label = Label.new()
		count_label.text = "0"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.size = Vector2(48, 20)
		count_label.position = Vector2(4, 36)
		count_label.add_theme_color_override("font_color", Color.WHITE)
		count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
		count_label.add_theme_constant_override("shadow_offset_x", 1)
		count_label.add_theme_constant_override("shadow_offset_y", 1)
		count_label.add_theme_font_size_override("font_size", 14)
		count_label.add_theme_constant_override("outline_size", 3)
		count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
		panel.add_child(count_label)
		
		hotbar.add_child(panel)
		slot_panels.append({
			"panel": panel,
			"color_rect": color_rect,
			"style": style,
			"count_label": count_label
		})

func _process(_delta):
	if player:
		_update_hotbar()

func _update_hotbar():
	if not player:
		return
	
	for i in range(min(slot_panels.size(), player.hotbar_slots.size())):
		var slot = slot_panels[i]
		var block_type = player.hotbar_slots[i]
		var color = BlockRegistry.get_block_color(block_type)
		var count = player.get_inventory_count(block_type)
		
		slot["color_rect"].color = color if count > 0 else color * 0.35
		
		slot["count_label"].text = str(count)
		if count == 0:
			slot["count_label"].add_theme_color_override("font_color", Color(0.4, 0.3, 0.3, 0.6))
			slot["count_label"].add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.3))
		else:
			slot["count_label"].add_theme_color_override("font_color", Color(1, 1, 1, 1))
			slot["count_label"].add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
		
		if i == player.selected_slot:
			slot["style"].border_color = Color(1.0, 1.0, 0.5, 1.0)
			slot["style"].border_width_left = 3
			slot["style"].border_width_top = 3
			slot["style"].border_width_right = 3
			slot["style"].border_width_bottom = 3
		else:
			slot["style"].border_color = Color(0.5, 0.5, 0.5, 1.0)
			slot["style"].border_width_left = 2
			slot["style"].border_width_top = 2
			slot["style"].border_width_right = 2
			slot["style"].border_width_bottom = 2
