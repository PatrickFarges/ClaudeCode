extends CanvasLayer

# Écran d'inventaire complet — ouvert avec I
# 6 onglets : TOUT, Basique, Métal, Stations, Armes, Armures

var player: CharacterBody3D = null
var is_open: bool = false
var current_tab: int = 0
var is_sorted: bool = false

var background: ColorRect
var panel: PanelContainer
var scroll: ScrollContainer
var grid: GridContainer
var placeholder_label: Label
var title_label: Label
var hint_label: Label
var slot_label: Label
var sort_button: Button
var tab_buttons: Array = []
var block_buttons: Array = []

# Tous les types de blocs solides (tout sauf AIR et WATER)
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
	BlockRegistry.BlockType.PLANKS,
	BlockRegistry.BlockType.CRAFTING_TABLE,
	BlockRegistry.BlockType.BRICK,
	BlockRegistry.BlockType.SANDSTONE,
	BlockRegistry.BlockType.COAL_ORE,
	BlockRegistry.BlockType.IRON_ORE,
	BlockRegistry.BlockType.GOLD_ORE,
	BlockRegistry.BlockType.IRON_INGOT,
	BlockRegistry.BlockType.GOLD_INGOT,
	BlockRegistry.BlockType.FURNACE,
	BlockRegistry.BlockType.STONE_TABLE,
	BlockRegistry.BlockType.IRON_TABLE,
	BlockRegistry.BlockType.GOLD_TABLE,
]

const TAB_BASIC = [
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
]

const TAB_METAL = [
	BlockRegistry.BlockType.COAL_ORE,
	BlockRegistry.BlockType.IRON_ORE,
	BlockRegistry.BlockType.GOLD_ORE,
	BlockRegistry.BlockType.IRON_INGOT,
	BlockRegistry.BlockType.GOLD_INGOT,
]

const TAB_STATIONS = [
	BlockRegistry.BlockType.PLANKS,
	BlockRegistry.BlockType.BRICK,
	BlockRegistry.BlockType.SANDSTONE,
	BlockRegistry.BlockType.CRAFTING_TABLE,
	BlockRegistry.BlockType.FURNACE,
	BlockRegistry.BlockType.STONE_TABLE,
	BlockRegistry.BlockType.IRON_TABLE,
	BlockRegistry.BlockType.GOLD_TABLE,
]

# Valeurs de tri (plus haut = plus rare, affiché en premier)
var SORT_VALUES: Dictionary = {}

const TAB_KEYS = ["inv_tab_all", "inv_tab_basic", "inv_tab_metal", "inv_tab_stations", "inv_tab_weapons", "inv_tab_armor"]

func _ready():
	layer = 10
	visible = false
	add_to_group("inventory_ui")

	_init_sort_values()

	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	_build_ui()

func _init_sort_values():
	SORT_VALUES[BlockRegistry.BlockType.GOLD_TABLE] = 100
	SORT_VALUES[BlockRegistry.BlockType.GOLD_INGOT] = 95
	SORT_VALUES[BlockRegistry.BlockType.GOLD_ORE] = 90
	SORT_VALUES[BlockRegistry.BlockType.IRON_TABLE] = 85
	SORT_VALUES[BlockRegistry.BlockType.IRON_INGOT] = 80
	SORT_VALUES[BlockRegistry.BlockType.IRON_ORE] = 75
	SORT_VALUES[BlockRegistry.BlockType.STONE_TABLE] = 70
	SORT_VALUES[BlockRegistry.BlockType.FURNACE] = 65
	SORT_VALUES[BlockRegistry.BlockType.CRAFTING_TABLE] = 60
	SORT_VALUES[BlockRegistry.BlockType.COAL_ORE] = 55
	SORT_VALUES[BlockRegistry.BlockType.BRICK] = 50
	SORT_VALUES[BlockRegistry.BlockType.SANDSTONE] = 45
	SORT_VALUES[BlockRegistry.BlockType.PLANKS] = 40
	SORT_VALUES[BlockRegistry.BlockType.STONE] = 35
	SORT_VALUES[BlockRegistry.BlockType.GRAVEL] = 30
	SORT_VALUES[BlockRegistry.BlockType.WOOD] = 25
	SORT_VALUES[BlockRegistry.BlockType.SAND] = 20
	SORT_VALUES[BlockRegistry.BlockType.SNOW] = 15
	SORT_VALUES[BlockRegistry.BlockType.CACTUS] = 12
	SORT_VALUES[BlockRegistry.BlockType.DARK_GRASS] = 10
	SORT_VALUES[BlockRegistry.BlockType.LEAVES] = 8
	SORT_VALUES[BlockRegistry.BlockType.GRASS] = 5
	SORT_VALUES[BlockRegistry.BlockType.DIRT] = 3

func _build_ui():
	# ============================================================
	# FOND SOMBRE
	# ============================================================
	background = ColorRect.new()
	background.color = Color(0, 0, 0, 0.6)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	# ============================================================
	# PANNEAU CENTRAL
	# ============================================================
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 0)
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
	center.add_child(panel)

	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(content_vbox)

	# ============================================================
	# TITRE
	# ============================================================
	title_label = Label.new()
	title_label.text = Locale.tr_ui("inv_title")
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(1, 1, 0.85, 1))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_vbox.add_child(title_label)

	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 6)
	content_vbox.add_child(separator)

	# ============================================================
	# SLOT ACTIF
	# ============================================================
	slot_label = Label.new()
	slot_label.text = "Slot actif : 1"
	slot_label.add_theme_font_size_override("font_size", 14)
	slot_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 1))
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_vbox.add_child(slot_label)

	# ============================================================
	# BARRE D'ONGLETS
	# ============================================================
	var tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	content_vbox.add_child(tab_bar)

	for i in range(TAB_KEYS.size()):
		var tab_btn = Button.new()
		tab_btn.text = Locale.tr_ui(TAB_KEYS[i])
		tab_btn.custom_minimum_size = Vector2(0, 32)
		tab_btn.add_theme_font_size_override("font_size", 13)
		tab_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tab_btn.pressed.connect(_switch_tab.bind(i))
		tab_bar.add_child(tab_btn)
		tab_buttons.append(tab_btn)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_child(spacer)

	# Bouton Trier
	sort_button = Button.new()
	sort_button.text = Locale.tr_ui("inv_sort")
	sort_button.custom_minimum_size = Vector2(0, 32)
	sort_button.add_theme_font_size_override("font_size", 13)
	sort_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sort_button.pressed.connect(_toggle_sort)
	tab_bar.add_child(sort_button)

	_update_tab_styles()
	_update_sort_style()

	# ============================================================
	# SÉPARATEUR
	# ============================================================
	var sep2 = HSeparator.new()
	sep2.add_theme_constant_override("separation", 6)
	content_vbox.add_child(sep2)

	# ============================================================
	# ZONE DE CONTENU SCROLLABLE
	# ============================================================
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(scroll)

	grid = GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	placeholder_label = Label.new()
	placeholder_label.text = Locale.tr_ui("inv_coming_soon")
	placeholder_label.add_theme_font_size_override("font_size", 18)
	placeholder_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 1))
	placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placeholder_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	placeholder_label.visible = false
	scroll.add_child(placeholder_label)

	# ============================================================
	# INSTRUCTIONS
	# ============================================================
	var hint_separator = HSeparator.new()
	hint_separator.add_theme_constant_override("separation", 6)
	content_vbox.add_child(hint_separator)

	hint_label = Label.new()
	hint_label.text = Locale.tr_ui("inv_hint")
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_vbox.add_child(hint_label)

	# Construire la grille initiale (onglet TOUT)
	_rebuild_grid()

func _switch_tab(index: int):
	current_tab = index
	_update_tab_styles()
	_rebuild_grid()

func _toggle_sort():
	is_sorted = not is_sorted
	_update_sort_style()
	_rebuild_grid()

func _update_tab_styles():
	for i in range(tab_buttons.size()):
		var btn: Button = tab_buttons[i]
		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4

		if i == current_tab:
			style.bg_color = Color(0.25, 0.25, 0.2, 1.0)
			style.border_color = Color(1, 1, 0.5, 0.8)
			btn.add_theme_color_override("font_color", Color(1, 1, 0.7, 1))
		else:
			style.bg_color = Color(0.18, 0.18, 0.2, 1.0)
			style.border_color = Color(0.4, 0.4, 0.45, 0.6)
			btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))

		btn.add_theme_stylebox_override("normal", style)

		var hover_style = style.duplicate()
		hover_style.bg_color = style.bg_color.lightened(0.1)
		hover_style.border_color = Color(0.8, 0.8, 0.5, 0.8)
		btn.add_theme_stylebox_override("hover", hover_style)

		var pressed_style = style.duplicate()
		pressed_style.bg_color = style.bg_color.darkened(0.1)
		btn.add_theme_stylebox_override("pressed", pressed_style)

func _update_sort_style():
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4

	if is_sorted:
		style.bg_color = Color(0.35, 0.2, 0.45, 1.0)
		style.border_color = Color(0.7, 0.4, 0.9, 0.8)
		sort_button.text = Locale.tr_ui("inv_sort_active")
		sort_button.add_theme_color_override("font_color", Color(0.9, 0.7, 1.0, 1))
	else:
		style.bg_color = Color(0.22, 0.18, 0.28, 1.0)
		style.border_color = Color(0.5, 0.35, 0.6, 0.6)
		sort_button.text = Locale.tr_ui("inv_sort")
		sort_button.add_theme_color_override("font_color", Color(0.7, 0.6, 0.8, 1))

	sort_button.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = style.bg_color.lightened(0.1)
	sort_button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = style.bg_color.darkened(0.1)
	sort_button.add_theme_stylebox_override("pressed", pressed_style)

func _rebuild_grid():
	# Vider la grille
	for child in grid.get_children():
		child.queue_free()
	block_buttons.clear()

	# Déterminer les blocs à afficher selon l'onglet
	var blocks: Array = []
	match current_tab:
		0: blocks = ALL_BLOCK_TYPES.duplicate()
		1: blocks = TAB_BASIC.duplicate()
		2: blocks = TAB_METAL.duplicate()
		3: blocks = TAB_STATIONS.duplicate()
		4: blocks = []  # Armes — vide
		5: blocks = []  # Armures — vide

	# Onglets vides : afficher le placeholder
	if blocks.is_empty():
		grid.visible = false
		placeholder_label.visible = true
		return

	grid.visible = true
	placeholder_label.visible = false

	# Tri par rareté si activé
	if is_sorted:
		blocks.sort_custom(func(a, b):
			var val_a = SORT_VALUES.get(a, 0)
			var val_b = SORT_VALUES.get(b, 0)
			return val_a > val_b
		)

	# Créer les boutons
	for block_type in blocks:
		var btn_data = _create_block_button(block_type)
		grid.add_child(btn_data["button"])
		block_buttons.append(btn_data)

	# Mettre à jour les compteurs
	_update_display()

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
	_rebuild_grid()

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
