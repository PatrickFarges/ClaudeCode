extends CanvasLayer

# Écran d'inventaire complet — ouvert avec E

var player: CharacterBody3D = null
var is_open: bool = false

var background: ColorRect
var panel: PanelContainer
var grid: GridContainer
var title_label: Label
var hint_label: Label
var slot_label: Label
var block_buttons: Array = []

# Tous les types de blocs solides
const ALL_BLOCK_TYPES = [
	BlockRegistry.BlockType.DIRT,
	BlockRegistry.BlockType.GRASS,
	BlockRegistry.BlockType.DARK_GRASS,
	BlockRegistry.BlockType.STONE,
	BlockRegistry.BlockType.SAND,
	BlockRegistry.BlockType.GRAVEL,
	BlockRegistry.BlockType.WOOD,
	BlockRegistry.BlockType.LEAVES,
	BlockRegistry.BlockType.SNOW,
	BlockRegistry.BlockType.CACTUS,
	# Blocs craftables
	BlockRegistry.BlockType.PLANKS,
	BlockRegistry.BlockType.CRAFTING_TABLE,
	BlockRegistry.BlockType.BRICK,
	BlockRegistry.BlockType.SANDSTONE,
]

func _ready():
	layer = 10
	visible = false
	add_to_group("inventory_ui")
	
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	
	_build_ui()

func _build_ui():
	background = ColorRect.new()
	background.color = Color(0, 0, 0, 0.6)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(580, 0)
	center.add_child(main_vbox)
	
	panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.5, 0.5, 0.6, 0.8)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	main_vbox.add_child(panel)
	
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(content_vbox)
	
	title_label = Label.new()
	title_label.text = Locale.tr_ui("inv_title")
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(1, 1, 0.85, 1))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_vbox.add_child(title_label)
	
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 8)
	content_vbox.add_child(separator)
	
	slot_label = Label.new()
	slot_label.text = "Slot actif : 1"
	slot_label.add_theme_font_size_override("font_size", 14)
	slot_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 1))
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_vbox.add_child(slot_label)
	
	grid = GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	content_vbox.add_child(grid)
	
	for block_type in ALL_BLOCK_TYPES:
		var btn_data = _create_block_button(block_type)
		grid.add_child(btn_data["button"])
		block_buttons.append(btn_data)
	
	var hint_separator = HSeparator.new()
	hint_separator.add_theme_constant_override("separation", 8)
	content_vbox.add_child(hint_separator)
	
	hint_label = Label.new()
	hint_label.text = Locale.tr_ui("inv_hint")
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_vbox.add_child(hint_label)

func _create_block_button(block_type: BlockRegistry.BlockType) -> Dictionary:
	var button = Button.new()
	button.custom_minimum_size = Vector2(72, 72)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.2, 0.2, 0.22, 1.0)
	normal_style.border_width_left = 1
	normal_style.border_width_top = 1
	normal_style.border_width_right = 1
	normal_style.border_width_bottom = 1
	normal_style.border_color = Color(0.4, 0.4, 0.45, 1.0)
	normal_style.corner_radius_top_left = 4
	normal_style.corner_radius_top_right = 4
	normal_style.corner_radius_bottom_left = 4
	normal_style.corner_radius_bottom_right = 4
	button.add_theme_stylebox_override("normal", normal_style)
	
	var hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(0.3, 0.3, 0.35, 1.0)
	hover_style.border_color = Color(1, 1, 0.5, 0.8)
	hover_style.border_width_left = 2
	hover_style.border_width_top = 2
	hover_style.border_width_right = 2
	hover_style.border_width_bottom = 2
	button.add_theme_stylebox_override("hover", hover_style)
	
	var pressed_style = normal_style.duplicate()
	pressed_style.bg_color = Color(0.15, 0.15, 0.18, 1.0)
	button.add_theme_stylebox_override("pressed", pressed_style)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 1)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(vbox)
	
	var color_container = CenterContainer.new()
	color_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(color_container)
	
	var color_rect = ColorRect.new()
	color_rect.custom_minimum_size = Vector2(30, 30)
	color_rect.color = BlockRegistry.get_block_color(block_type)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_container.add_child(color_rect)
	
	var name_label = Label.new()
	name_label.text = BlockRegistry.get_block_name(block_type)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)
	
	var count_label = Label.new()
	count_label.text = "x0"
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7, 1))
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(count_label)
	
	button.pressed.connect(_on_block_button_pressed.bind(block_type))
	
	return {
		"button": button,
		"color_rect": color_rect,
		"count_label": count_label,
		"name_label": name_label,
		"block_type": block_type,
		"normal_style": normal_style
	}

func _on_block_button_pressed(block_type: BlockRegistry.BlockType):
	if not player:
		return
	player.assign_hotbar_slot(player.selected_slot, block_type)

func open_inventory():
	is_open = true
	visible = true
	_update_display()

func close_inventory():
	is_open = false
	visible = false

func _process(_delta):
	if is_open and player:
		_update_display()

func _update_display():
	if not player:
		return
	
	slot_label.text = Locale.tr_ui("inv_active_slot") % [
		player.selected_slot + 1,
		BlockRegistry.get_block_name(player.selected_block_type)
	]
	
	for btn_data in block_buttons:
		var count = player.get_inventory_count(btn_data["block_type"])
		btn_data["count_label"].text = "x%d" % count
		
		if count == 0:
			btn_data["color_rect"].color = BlockRegistry.get_block_color(btn_data["block_type"]) * 0.35
			btn_data["count_label"].add_theme_color_override("font_color", Color(0.5, 0.4, 0.4, 1))
			btn_data["name_label"].add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		else:
			btn_data["color_rect"].color = BlockRegistry.get_block_color(btn_data["block_type"])
			btn_data["count_label"].add_theme_color_override("font_color", Color(0.7, 0.9, 0.7, 1))
			btn_data["name_label"].add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
		
		var is_active = player.hotbar_slots[player.selected_slot] == btn_data["block_type"]
		if is_active:
			btn_data["normal_style"].border_color = Color(1, 1, 0.5, 0.9)
			btn_data["normal_style"].border_width_left = 2
			btn_data["normal_style"].border_width_top = 2
			btn_data["normal_style"].border_width_right = 2
			btn_data["normal_style"].border_width_bottom = 2
		else:
			btn_data["normal_style"].border_color = Color(0.4, 0.4, 0.45, 1.0)
			btn_data["normal_style"].border_width_left = 1
			btn_data["normal_style"].border_width_top = 1
			btn_data["normal_style"].border_width_right = 1
			btn_data["normal_style"].border_width_bottom = 1
