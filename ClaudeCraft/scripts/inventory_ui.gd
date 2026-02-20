extends CanvasLayer

const GC = preload("res://scripts/game_config.gd")
# Ecran d'inventaire complet — ouvert avec I
# 7 onglets : TOUT, Terrain, Bois, Pierre, Minerais, Deco, Stations

var player: CharacterBody3D = null
var is_open: bool = false
var current_tab: int = 0
var is_sorted: bool = false
var _icon_cache: Dictionary = {}

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
	BlockRegistry.BlockType.COBBLESTONE,
	BlockRegistry.BlockType.MOSSY_COBBLESTONE,
	BlockRegistry.BlockType.ANDESITE,
	BlockRegistry.BlockType.GRANITE,
	BlockRegistry.BlockType.DIORITE,
	BlockRegistry.BlockType.DEEPSLATE,
	BlockRegistry.BlockType.SMOOTH_STONE,
	BlockRegistry.BlockType.SPRUCE_LOG,
	BlockRegistry.BlockType.BIRCH_LOG,
	BlockRegistry.BlockType.JUNGLE_LOG,
	BlockRegistry.BlockType.ACACIA_LOG,
	BlockRegistry.BlockType.DARK_OAK_LOG,
	BlockRegistry.BlockType.SPRUCE_PLANKS,
	BlockRegistry.BlockType.BIRCH_PLANKS,
	BlockRegistry.BlockType.JUNGLE_PLANKS,
	BlockRegistry.BlockType.ACACIA_PLANKS,
	BlockRegistry.BlockType.DARK_OAK_PLANKS,
	BlockRegistry.BlockType.CHERRY_LOG,
	BlockRegistry.BlockType.CHERRY_PLANKS,
	BlockRegistry.BlockType.SPRUCE_LEAVES,
	BlockRegistry.BlockType.BIRCH_LEAVES,
	BlockRegistry.BlockType.JUNGLE_LEAVES,
	BlockRegistry.BlockType.ACACIA_LEAVES,
	BlockRegistry.BlockType.DARK_OAK_LEAVES,
	BlockRegistry.BlockType.CHERRY_LEAVES,
	BlockRegistry.BlockType.DIAMOND_ORE,
	BlockRegistry.BlockType.COPPER_ORE,
	BlockRegistry.BlockType.DIAMOND_BLOCK,
	BlockRegistry.BlockType.COPPER_BLOCK,
	BlockRegistry.BlockType.COPPER_INGOT,
	BlockRegistry.BlockType.COAL_BLOCK,
	BlockRegistry.BlockType.CLAY,
	BlockRegistry.BlockType.PODZOL,
	BlockRegistry.BlockType.ICE,
	BlockRegistry.BlockType.PACKED_ICE,
	BlockRegistry.BlockType.MOSS_BLOCK,
	BlockRegistry.BlockType.GLASS,
	BlockRegistry.BlockType.BOOKSHELF,
	BlockRegistry.BlockType.HAY_BLOCK,
	BlockRegistry.BlockType.BARREL,
]

const TAB_TERRAIN = [
	BlockRegistry.BlockType.DIRT,
	BlockRegistry.BlockType.GRASS,
	BlockRegistry.BlockType.DARK_GRASS,
	BlockRegistry.BlockType.STONE,
	BlockRegistry.BlockType.SAND,
	BlockRegistry.BlockType.GRAVEL,
	BlockRegistry.BlockType.SNOW,
	BlockRegistry.BlockType.CACTUS,
	BlockRegistry.BlockType.CLAY,
	BlockRegistry.BlockType.PODZOL,
	BlockRegistry.BlockType.MOSS_BLOCK,
	BlockRegistry.BlockType.ICE,
	BlockRegistry.BlockType.PACKED_ICE,
]

const TAB_WOOD = [
	BlockRegistry.BlockType.WOOD,
	BlockRegistry.BlockType.PLANKS,
	BlockRegistry.BlockType.SPRUCE_LOG,
	BlockRegistry.BlockType.SPRUCE_PLANKS,
	BlockRegistry.BlockType.BIRCH_LOG,
	BlockRegistry.BlockType.BIRCH_PLANKS,
	BlockRegistry.BlockType.JUNGLE_LOG,
	BlockRegistry.BlockType.JUNGLE_PLANKS,
	BlockRegistry.BlockType.ACACIA_LOG,
	BlockRegistry.BlockType.ACACIA_PLANKS,
	BlockRegistry.BlockType.DARK_OAK_LOG,
	BlockRegistry.BlockType.DARK_OAK_PLANKS,
	BlockRegistry.BlockType.CHERRY_LOG,
	BlockRegistry.BlockType.CHERRY_PLANKS,
]

const TAB_STONE = [
	BlockRegistry.BlockType.STONE,
	BlockRegistry.BlockType.COBBLESTONE,
	BlockRegistry.BlockType.MOSSY_COBBLESTONE,
	BlockRegistry.BlockType.ANDESITE,
	BlockRegistry.BlockType.GRANITE,
	BlockRegistry.BlockType.DIORITE,
	BlockRegistry.BlockType.DEEPSLATE,
	BlockRegistry.BlockType.SMOOTH_STONE,
	BlockRegistry.BlockType.BRICK,
	BlockRegistry.BlockType.SANDSTONE,
]

const TAB_ORES = [
	BlockRegistry.BlockType.COAL_ORE,
	BlockRegistry.BlockType.IRON_ORE,
	BlockRegistry.BlockType.GOLD_ORE,
	BlockRegistry.BlockType.COPPER_ORE,
	BlockRegistry.BlockType.DIAMOND_ORE,
	BlockRegistry.BlockType.IRON_INGOT,
	BlockRegistry.BlockType.GOLD_INGOT,
	BlockRegistry.BlockType.COPPER_INGOT,
	BlockRegistry.BlockType.DIAMOND_BLOCK,
	BlockRegistry.BlockType.COAL_BLOCK,
	BlockRegistry.BlockType.COPPER_BLOCK,
]

const TAB_DECO = [
	BlockRegistry.BlockType.GLASS,
	BlockRegistry.BlockType.BOOKSHELF,
	BlockRegistry.BlockType.HAY_BLOCK,
	BlockRegistry.BlockType.BARREL,
	BlockRegistry.BlockType.LEAVES,
	BlockRegistry.BlockType.SPRUCE_LEAVES,
	BlockRegistry.BlockType.BIRCH_LEAVES,
	BlockRegistry.BlockType.JUNGLE_LEAVES,
	BlockRegistry.BlockType.ACACIA_LEAVES,
	BlockRegistry.BlockType.DARK_OAK_LEAVES,
	BlockRegistry.BlockType.CHERRY_LEAVES,
]

const TAB_STATIONS = [
	BlockRegistry.BlockType.CRAFTING_TABLE,
	BlockRegistry.BlockType.FURNACE,
	BlockRegistry.BlockType.STONE_TABLE,
	BlockRegistry.BlockType.IRON_TABLE,
	BlockRegistry.BlockType.GOLD_TABLE,
	BlockRegistry.BlockType.BARREL,
]

# Valeurs de tri (plus haut = plus rare, affiche en premier)
var SORT_VALUES: Dictionary = {}

const TAB_KEYS = ["inv_tab_all", "inv_tab_terrain", "inv_tab_wood", "inv_tab_stone", "inv_tab_ores", "inv_tab_deco", "inv_tab_stations"]

func _ready():
	layer = 10
	visible = false
	add_to_group("inventory_ui")

	_init_sort_values()

	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	_build_ui()

func _init_sort_values():
	SORT_VALUES[BlockRegistry.BlockType.GOLD_TABLE] = 200
	SORT_VALUES[BlockRegistry.BlockType.GOLD_INGOT] = 195
	SORT_VALUES[BlockRegistry.BlockType.GOLD_ORE] = 190
	SORT_VALUES[BlockRegistry.BlockType.IRON_TABLE] = 185
	SORT_VALUES[BlockRegistry.BlockType.IRON_INGOT] = 180
	SORT_VALUES[BlockRegistry.BlockType.IRON_ORE] = 175
	SORT_VALUES[BlockRegistry.BlockType.DIAMOND_BLOCK] = 170
	SORT_VALUES[BlockRegistry.BlockType.DIAMOND_ORE] = 165
	SORT_VALUES[BlockRegistry.BlockType.STONE_TABLE] = 160
	SORT_VALUES[BlockRegistry.BlockType.FURNACE] = 155
	SORT_VALUES[BlockRegistry.BlockType.CRAFTING_TABLE] = 150
	SORT_VALUES[BlockRegistry.BlockType.BARREL] = 145
	SORT_VALUES[BlockRegistry.BlockType.COPPER_BLOCK] = 140
	SORT_VALUES[BlockRegistry.BlockType.COPPER_INGOT] = 135
	SORT_VALUES[BlockRegistry.BlockType.COPPER_ORE] = 130
	SORT_VALUES[BlockRegistry.BlockType.COAL_BLOCK] = 125
	SORT_VALUES[BlockRegistry.BlockType.COAL_ORE] = 120
	SORT_VALUES[BlockRegistry.BlockType.BOOKSHELF] = 115
	SORT_VALUES[BlockRegistry.BlockType.GLASS] = 110
	SORT_VALUES[BlockRegistry.BlockType.HAY_BLOCK] = 105
	SORT_VALUES[BlockRegistry.BlockType.DEEPSLATE] = 100
	SORT_VALUES[BlockRegistry.BlockType.SMOOTH_STONE] = 95
	SORT_VALUES[BlockRegistry.BlockType.BRICK] = 90
	SORT_VALUES[BlockRegistry.BlockType.SANDSTONE] = 85
	SORT_VALUES[BlockRegistry.BlockType.MOSSY_COBBLESTONE] = 80
	SORT_VALUES[BlockRegistry.BlockType.COBBLESTONE] = 75
	SORT_VALUES[BlockRegistry.BlockType.ANDESITE] = 70
	SORT_VALUES[BlockRegistry.BlockType.GRANITE] = 68
	SORT_VALUES[BlockRegistry.BlockType.DIORITE] = 66
	SORT_VALUES[BlockRegistry.BlockType.PACKED_ICE] = 64
	SORT_VALUES[BlockRegistry.BlockType.ICE] = 62
	SORT_VALUES[BlockRegistry.BlockType.PLANKS] = 60
	SORT_VALUES[BlockRegistry.BlockType.SPRUCE_PLANKS] = 59
	SORT_VALUES[BlockRegistry.BlockType.BIRCH_PLANKS] = 58
	SORT_VALUES[BlockRegistry.BlockType.JUNGLE_PLANKS] = 57
	SORT_VALUES[BlockRegistry.BlockType.ACACIA_PLANKS] = 56
	SORT_VALUES[BlockRegistry.BlockType.DARK_OAK_PLANKS] = 55
	SORT_VALUES[BlockRegistry.BlockType.CHERRY_PLANKS] = 54
	SORT_VALUES[BlockRegistry.BlockType.STONE] = 50
	SORT_VALUES[BlockRegistry.BlockType.GRAVEL] = 45
	SORT_VALUES[BlockRegistry.BlockType.WOOD] = 40
	SORT_VALUES[BlockRegistry.BlockType.SPRUCE_LOG] = 39
	SORT_VALUES[BlockRegistry.BlockType.BIRCH_LOG] = 38
	SORT_VALUES[BlockRegistry.BlockType.JUNGLE_LOG] = 37
	SORT_VALUES[BlockRegistry.BlockType.ACACIA_LOG] = 36
	SORT_VALUES[BlockRegistry.BlockType.DARK_OAK_LOG] = 35
	SORT_VALUES[BlockRegistry.BlockType.CHERRY_LOG] = 34
	SORT_VALUES[BlockRegistry.BlockType.SAND] = 30
	SORT_VALUES[BlockRegistry.BlockType.CLAY] = 28
	SORT_VALUES[BlockRegistry.BlockType.PODZOL] = 26
	SORT_VALUES[BlockRegistry.BlockType.MOSS_BLOCK] = 24
	SORT_VALUES[BlockRegistry.BlockType.SNOW] = 20
	SORT_VALUES[BlockRegistry.BlockType.CACTUS] = 18
	SORT_VALUES[BlockRegistry.BlockType.DARK_GRASS] = 15
	SORT_VALUES[BlockRegistry.BlockType.CHERRY_LEAVES] = 13
	SORT_VALUES[BlockRegistry.BlockType.LEAVES] = 12
	SORT_VALUES[BlockRegistry.BlockType.SPRUCE_LEAVES] = 11
	SORT_VALUES[BlockRegistry.BlockType.BIRCH_LEAVES] = 10
	SORT_VALUES[BlockRegistry.BlockType.JUNGLE_LEAVES] = 9
	SORT_VALUES[BlockRegistry.BlockType.ACACIA_LEAVES] = 8
	SORT_VALUES[BlockRegistry.BlockType.DARK_OAK_LEAVES] = 7
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
	panel.custom_minimum_size = Vector2(780, 0)
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
	# SEPARATEUR
	# ============================================================
	var sep2 = HSeparator.new()
	sep2.add_theme_constant_override("separation", 6)
	content_vbox.add_child(sep2)

	# ============================================================
	# ZONE DE CONTENU SCROLLABLE
	# ============================================================
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(scroll)

	grid = GridContainer.new()
	grid.columns = 8
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

	# Determiner les blocs a afficher selon l'onglet
	var blocks: Array = []
	match current_tab:
		0: blocks = ALL_BLOCK_TYPES.duplicate()
		1: blocks = TAB_TERRAIN.duplicate()
		2: blocks = TAB_WOOD.duplicate()
		3: blocks = TAB_STONE.duplicate()
		4: blocks = TAB_ORES.duplicate()
		5: blocks = TAB_DECO.duplicate()
		6: blocks = TAB_STATIONS.duplicate()

	# Onglets vides : afficher le placeholder
	if blocks.is_empty():
		grid.visible = false
		placeholder_label.visible = true
		return

	grid.visible = true
	placeholder_label.visible = false

	# Tri par rarete si active
	if is_sorted:
		blocks.sort_custom(func(a, b):
			var val_a = SORT_VALUES.get(a, 0)
			var val_b = SORT_VALUES.get(b, 0)
			return val_a > val_b
		)

	# Creer les boutons
	for block_type in blocks:
		var btn_data = _create_block_button(block_type)
		grid.add_child(btn_data["button"])
		block_buttons.append(btn_data)

	# Mettre a jour les compteurs
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

	# Texture du bloc par dessus le ColorRect (fallback couleur si pas de texture)
	var tex_rect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(30, 30)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var block_tex = _load_block_icon(block_type)
	if block_tex:
		tex_rect.texture = block_tex
		tex_rect.visible = true
		color_rect.visible = false
	else:
		tex_rect.visible = false
	color_container.add_child(tex_rect)

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
	button.gui_input.connect(_on_block_gui_input.bind(block_type))

	return {
		"button": button,
		"color_rect": color_rect,
		"tex_rect": tex_rect,
		"count_label": count_label,
		"name_label": name_label,
		"block_type": block_type,
		"normal_style": normal_style
	}

func _on_block_button_pressed(block_type: BlockRegistry.BlockType):
	if not player:
		return
	player.assign_hotbar_slot(player.selected_slot, block_type)

func _on_block_gui_input(event: InputEvent, block_type: BlockRegistry.BlockType):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
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
			if btn_data.has("tex_rect"):
				btn_data["tex_rect"].modulate = Color(0.4, 0.4, 0.4, 0.6)
			btn_data["count_label"].add_theme_color_override("font_color", Color(0.5, 0.4, 0.4, 1))
			btn_data["name_label"].add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		else:
			btn_data["color_rect"].color = BlockRegistry.get_block_color(btn_data["block_type"])
			if btn_data.has("tex_rect"):
				btn_data["tex_rect"].modulate = Color(1, 1, 1, 1)
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

func _load_block_icon(block_type: BlockRegistry.BlockType) -> ImageTexture:
	var cache_key = "block_" + str(block_type)
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key]
	var tex_name = BlockRegistry.get_face_texture(block_type, "top")
	if tex_name == "dirt" and block_type != BlockRegistry.BlockType.DIRT:
		tex_name = BlockRegistry.get_face_texture(block_type, "all")
	var abs_path = GC.resolve_block_texture(tex_name)
	if abs_path.is_empty():
		_icon_cache[cache_key] = null
		return null
	var img = Image.new()
	if img.load(abs_path) != OK:
		_icon_cache[cache_key] = null
		return null
	img.convert(Image.FORMAT_RGBA8)
	var tint = BlockRegistry.get_block_tint(block_type, "top")
	if tint != Color(1, 1, 1, 1):
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c = img.get_pixel(x, y)
				img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	var tex = ImageTexture.create_from_image(img)
	_icon_cache[cache_key] = tex
	return tex
