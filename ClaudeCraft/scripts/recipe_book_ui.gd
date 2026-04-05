# recipe_book_ui.gd v2.0.0
# Panneau de recettes MC Bedrock Edition — s'affiche à gauche de l'inventaire ou du craft
# 5 onglets : Construction, Equipement, Objets, Nature, Recherche
# Filtre fabricables, barre de recherche, grille paginée, auto-craft au clic
# v2.0.0 — Refonte visuelle style Bedrock Edition : fond sombre programmatique,
#           grands onglets colorés, loupe séparée, palette dark UI

extends Control

const GC = preload("res://scripts/game_config.gd")
const GUI_DIR = "res://TexturesPack/Faithful32/assets/minecraft/textures/gui/"
const RB_DIR = GUI_DIR + "sprites/recipe_book/"
const GUI_SCALE = 2

# Panel dimensions (en pixels Faithful32, multiplié par GUI_SCALE pour l'affichage)
const PANEL_W = 260   # largeur F32 → 520px display
const PANEL_H = 332   # hauteur F32 = TEX_H inventaire → 664px display (même hauteur)

# Tab layout — 5 tabs protruding ABOVE the panel (Bedrock style)
const TAB_COUNT = 5
const TAB_SZ = 22         # tab button size (pre-scale) — 44px at GUI_SCALE
const TAB_ICON_SZ = 15    # icon size (pre-scale) — 30px at GUI_SCALE
const TAB_MARGIN_LEFT = 4
const TAB_MARGIN_TOP = -20  # négatif = AU-DESSUS du panneau
const TAB_SPACING = 2

# Visual tab order → Category enum mapping
# Visual: Construction(0), Equipment(1), Items(2), Nature(3), Search(4)
const TAB_TO_CATEGORY = [1, 2, 3, 4, 0]  # Category.CONSTRUCTION, EQUIPMENT, ITEMS, NATURE, SEARCH
const CATEGORY_TO_TAB = [4, 0, 1, 2, 3]  # inverse mapping

# Loupe button (separate, top-right corner)
const LOUPE_SZ = 20       # pre-scale — 40px at GUI_SCALE

# Search bar sous le label catégorie
const SEARCH_H = 12       # pre-scale
const SEARCH_MARGIN = 8

const FILTER_W = 26        # pre-scale
const FILTER_H = 13        # pre-scale

const GRID_COLS = 8
const GRID_ROWS = 8
const GRID_MARGIN_LEFT = 6
const GRID_MARGIN_TOP = 42  # label(6+14=20) + search(22+12=34) + padding
const GRID_SPACING = 2

const SLOTS_PER_PAGE = 64  # 8x8
const PAGE_BTN_W = 12      # pre-scale
const PAGE_BTN_H = 17      # pre-scale

# Bedrock dark palette
const COLOR_PANEL_BG = Color(0.376, 0.376, 0.376)       # #606060
const COLOR_BORDER = Color(0.55, 0.55, 0.55)             # medium gray border
const COLOR_TAB_BG = Color(0.282, 0.282, 0.282)          # #484848
const COLOR_TAB_SELECTED = Color(0.38, 0.38, 0.38)       # lighter when selected
const COLOR_TAB_BORDER = Color(0.6, 0.6, 0.6)            # selected tab border
const COLOR_SEARCH_BG = Color(0.19, 0.19, 0.19)          # #303030
const COLOR_SEARCH_BORDER = Color(0.45, 0.45, 0.45)
const COLOR_TEXT = Color(1.0, 1.0, 1.0)                   # white text
const COLOR_TEXT_DIM = Color(0.75, 0.75, 0.75)            # light gray text

# Categories
enum Category { SEARCH, CONSTRUCTION, EQUIPMENT, ITEMS, NATURE }

# Category icons — block types pour chaque onglet (var car les enum BlockType ne sont pas des const littéraux)
static var CATEGORY_ICONS: Array = []

static func _get_category_icons() -> Array:
	if CATEGORY_ICONS.is_empty():
		CATEGORY_ICONS = [
			-1,  # SEARCH
			BlockRegistry.BlockType.BRICK,          # CONSTRUCTION
			BlockRegistry.BlockType.IRON_SWORD,     # EQUIPMENT
			BlockRegistry.BlockType.TORCH,          # ITEMS
			BlockRegistry.BlockType.LEAVES,         # NATURE
		]
	return CATEGORY_ICONS

# Category labels
const CATEGORY_LABELS = ["Recherche", "Construction", "Equipement", "Objets", "Nature"]

# Classification des outputs par catégorie
const CONSTRUCTION_TYPES = [
	"BRICK", "SANDSTONE", "STONE_BRICKS", "GLASS", "GLASS_PANE",
	"OAK_STAIRS", "COBBLESTONE_STAIRS", "STONE_BRICK_STAIRS",
	"OAK_SLAB", "COBBLESTONE_SLAB", "STONE_SLAB",
	"OAK_DOOR", "IRON_DOOR", "OAK_FENCE", "IRON_BARS",
	"LADDER", "OAK_TRAPDOOR", "LANTERN", "SMOOTH_STONE",
	"ANDESITE", "GRANITE", "DIORITE", "DEEPSLATE",
	"COBBLESTONE", "MOSSY_COBBLESTONE", "PACKED_ICE",
	"COPPER_BLOCK", "COAL_BLOCK",
]
const EQUIPMENT_TYPES = [
	"IRON_SWORD", "GOLD_SWORD", "SHIELD",
]
const NATURE_TYPES = [
	"PLANKS", "SPRUCE_PLANKS", "BIRCH_PLANKS", "JUNGLE_PLANKS",
	"ACACIA_PLANKS", "DARK_OAK_PLANKS", "CHERRY_PLANKS",
	"DIRT", "SAND", "HAY_BLOCK", "MOSS_BLOCK", "PODZOL",
	"BREAD", "WHEAT_ITEM",
]

# State
var _current_category: int = Category.SEARCH
var _filter_craftable: bool = false
var _search_text: String = ""
var _page: int = 0
var _filtered_recipes: Array = []
var _all_recipes: Array = []
var _icon_cache: Dictionary = {}

# Crafting context
var player: CharacterBody3D = null
var current_tier: int = 0
var has_furnace: bool = false

# UI nodes
var _panel_bg: Panel = null
var _loupe_btn: Button = null
var _tab_buttons: Array = []      # [{btn, icon}]
var _category_label: Label = null
var _filter_btn: Button = null
var _filter_icon: TextureRect = null
var _filter_enabled_tex: ImageTexture = null
var _filter_disabled_tex: ImageTexture = null
var _search_input: LineEdit = null
var _recipe_slots: Array = []     # [{btn, icon, count_lbl, slot_bg}]
var _slot_craftable_tex: ImageTexture = null
var _slot_uncraftable_tex: ImageTexture = null
var _page_back_btn: Button = null
var _page_fwd_btn: Button = null
var _page_label: Label = null
var _tooltip_panel: PanelContainer = null
var _tooltip_name: Label = null
var _tooltip_ingredients: Label = null
var _tooltip_station: Label = null

# Parent UI callback
var _parent_ui = null
var _parent_refresh_func: Callable = Callable()

signal recipe_crafted(recipe: Dictionary)


# Persistent state — remembered across open/close
static var _was_open: bool = false

func _ready():
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Ne bloque pas l'input quand invisible
	clip_contents = false  # Allow tabs to protrude above the panel
	set_process_input(true)

func _input(event: InputEvent):
	# Quand le champ recherche a le focus, consommer TOUTES les touches
	# pour empêcher les raccourcis jeu (C=craft, I=inventaire, E=inventaire, etc.)
	if _search_input and _search_input.has_focus():
		if event is InputEventKey:
			get_viewport().set_input_as_handled()


func setup(p_player: CharacterBody3D, p_tier: int, p_furnace: bool, parent_ui = null, refresh_func: Callable = Callable()):
	player = p_player
	current_tier = p_tier
	has_furnace = p_furnace
	_parent_ui = parent_ui
	if refresh_func.is_valid():
		_parent_refresh_func = refresh_func
	_all_recipes = []
	for recipe in CraftRegistry.get_all_recipes():
		if recipe.has("_tool_tier") or recipe.get("output_count", 0) <= 0:
			continue
		_all_recipes.append(recipe)
	if _panel_bg == null:
		_build_ui()
	_apply_filter()


func update_context(p_tier: int, p_furnace: bool):
	current_tier = p_tier
	has_furnace = p_furnace
	_apply_filter()


func toggle():
	visible = not visible
	# Bloquer l'input seulement quand visible
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	if visible:
		_page = 0
		_apply_filter()


func _build_ui():
	var pw = PANEL_W * GUI_SCALE
	var ph = PANEL_H * GUI_SCALE

	# --- Panel background (dark Bedrock style, programmatic StyleBoxFlat) ---
	_panel_bg = Panel.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.border_color = COLOR_BORDER
	panel_style.border_width_top = 4
	panel_style.border_width_left = 4
	panel_style.border_width_bottom = 4
	panel_style.border_width_right = 4
	panel_style.set_corner_radius_all(0)
	_panel_bg.add_theme_stylebox_override("panel", panel_style)
	_panel_bg.position = Vector2.ZERO
	_panel_bg.size = Vector2(pw, ph)
	_panel_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel_bg)

	size = Vector2(pw, ph)

	# --- Load sprite textures ---
	_filter_enabled_tex = _load_sprite("filter_enabled.png")
	_filter_disabled_tex = _load_sprite("filter_disabled.png")
	_slot_craftable_tex = _load_sprite("slot_craftable.png")
	_slot_uncraftable_tex = _load_sprite("slot_uncraftable.png")

	# --- Tabs (large dark buttons inside the panel, Bedrock style) ---
	_build_tabs()

	# --- Loupe button (separate, top-right corner, overlapping border) ---
	_build_loupe_button(pw)

	# --- Category label (below tabs, white text, right-aligned) ---
	var label_y = (TAB_MARGIN_TOP + TAB_SZ + 3) * GUI_SCALE
	_category_label = Label.new()
	_category_label.text = CATEGORY_LABELS[0]
	_category_label.position = Vector2(SEARCH_MARGIN * GUI_SCALE, label_y)
	_category_label.size = Vector2((PANEL_W - SEARCH_MARGIN * 2) * GUI_SCALE, 14 * GUI_SCALE)
	_category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_category_label.add_theme_font_size_override("font_size", 14)
	_category_label.add_theme_color_override("font_color", COLOR_TEXT)
	_category_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_category_label)

	# --- Filter toggle (to the right of search bar area, using MC sprites) ---
	var filter_y = (TAB_MARGIN_TOP + TAB_SZ + 3 + 16) * GUI_SCALE
	var filter_x = pw - (FILTER_W + SEARCH_MARGIN) * GUI_SCALE
	_filter_icon = TextureRect.new()
	_filter_icon.texture = _filter_disabled_tex
	_filter_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_filter_icon.position = Vector2(filter_x, filter_y)
	_filter_icon.size = Vector2(FILTER_W * GUI_SCALE, FILTER_H * GUI_SCALE)
	_filter_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_filter_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_filter_icon)
	_filter_btn = Button.new()
	_filter_btn.flat = true
	_filter_btn.position = Vector2(filter_x, filter_y)
	_filter_btn.size = Vector2(FILTER_W * GUI_SCALE, FILTER_H * GUI_SCALE)
	_filter_btn.pressed.connect(_on_filter_toggle)
	add_child(_filter_btn)

	# --- Search input (dark Bedrock style, below category label) ---
	var search_y = (TAB_MARGIN_TOP + TAB_SZ + 3 + 16) * GUI_SCALE
	var search_w = (PANEL_W - SEARCH_MARGIN * 3 - FILTER_W) * GUI_SCALE
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Rechercher..."
	_search_input.position = Vector2(SEARCH_MARGIN * GUI_SCALE, search_y)
	_search_input.size = Vector2(search_w, SEARCH_H * GUI_SCALE)
	_search_input.add_theme_font_size_override("font_size", 12)
	_search_input.add_theme_color_override("font_color", COLOR_TEXT)
	_search_input.add_theme_color_override("font_placeholder_color", Color(0.5, 0.5, 0.5))
	var search_style = StyleBoxFlat.new()
	search_style.bg_color = COLOR_SEARCH_BG
	search_style.border_color = COLOR_SEARCH_BORDER
	search_style.set_border_width_all(1)
	search_style.set_corner_radius_all(0)
	search_style.set_content_margin_all(4)
	_search_input.add_theme_stylebox_override("normal", search_style)
	var search_focus = search_style.duplicate()
	search_focus.border_color = Color(0.7, 0.7, 0.65, 1.0)
	_search_input.add_theme_stylebox_override("focus", search_focus)
	_search_input.text_changed.connect(_on_search_changed)
	add_child(_search_input)

	# --- Recipe grid ---
	_build_recipe_grid()

	# --- Page navigation ---
	_build_page_nav(pw, ph)

	# --- Tooltip ---
	_build_tooltip()


func _build_tabs():
	# 5 large dark tab buttons inside the panel (Bedrock style)
	# Visual order: Construction, Equipment, Items, Nature, Search
	var tab_px = TAB_SZ * GUI_SCALE
	var icon_px = TAB_ICON_SZ * GUI_SCALE
	var tab_y = TAB_MARGIN_TOP * GUI_SCALE
	var tab_start_x = TAB_MARGIN_LEFT * GUI_SCALE
	var tab_gap = TAB_SPACING * GUI_SCALE
	var icons_list = _get_category_icons()

	# Visual tab order: Construction(cat 1), Equipment(cat 2), Items(cat 3), Nature(cat 4), Search(cat 0)
	var visual_order = [
		Category.CONSTRUCTION,
		Category.EQUIPMENT,
		Category.ITEMS,
		Category.NATURE,
		Category.SEARCH,
	]

	# Styles
	var style_selected = StyleBoxFlat.new()
	style_selected.bg_color = COLOR_TAB_SELECTED
	style_selected.border_color = COLOR_TAB_BORDER
	style_selected.set_border_width_all(2)
	style_selected.set_corner_radius_all(0)

	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = COLOR_TAB_BG
	style_normal.set_corner_radius_all(0)

	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.34, 0.34, 0.34)
	style_hover.set_corner_radius_all(0)

	# _tab_buttons is indexed by category (0=SEARCH, 1=CONSTRUCTION, etc.)
	# We need to build them in visual order but store them by category index
	_tab_buttons.resize(TAB_COUNT)

	for vi in range(TAB_COUNT):
		var cat_idx = visual_order[vi]
		var tx = tab_start_x + vi * (tab_px + tab_gap)

		# Tab icon (large, colorful)
		var icon = TextureRect.new()
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var pad = (tab_px - icon_px) / 2.0
		icon.position = Vector2(tx + pad, tab_y + pad)
		icon.size = Vector2(icon_px, icon_px)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bt = icons_list[cat_idx]
		if bt == -1:
			# Search tab — loupe from atlas
			var loupe_img = Image.load_from_file(GUI_DIR + "recipe_book.png")
			if loupe_img:
				loupe_img.convert(Image.FORMAT_RGBA8)
				var loupe_region = loupe_img.get_region(Rect2i(6, 6, 16, 16))
				icon.texture = ImageTexture.create_from_image(loupe_region)
		elif bt == BlockRegistry.BlockType.IRON_SWORD:
			icon.texture = _load_tool_icon_static(bt)
		else:
			icon.texture = _load_block_icon(bt)
		add_child(icon)

		# Tab button
		var btn = Button.new()
		btn.flat = true
		btn.position = Vector2(tx, tab_y)
		btn.size = Vector2(tab_px, tab_px)
		var is_default = (cat_idx == Category.SEARCH)  # default category
		btn.add_theme_stylebox_override("normal", style_selected.duplicate() if is_default else style_normal.duplicate())
		btn.add_theme_stylebox_override("hover", style_hover.duplicate())
		btn.pressed.connect(_on_tab_pressed.bind(cat_idx))
		add_child(btn)

		# Store by category index so _refresh_grid can use _tab_buttons[i] with i=category
		_tab_buttons[cat_idx] = {"btn": btn, "icon": icon}


func _build_loupe_button(pw: float):
	# Separate loupe button at top-right corner, partially overlapping the border
	var loupe_px = LOUPE_SZ * GUI_SCALE
	_loupe_btn = Button.new()
	_loupe_btn.flat = true
	_loupe_btn.position = Vector2(pw - loupe_px - 2 * GUI_SCALE, 2 * GUI_SCALE)
	_loupe_btn.size = Vector2(loupe_px, loupe_px)
	var loupe_style = StyleBoxFlat.new()
	loupe_style.bg_color = COLOR_TAB_BG
	loupe_style.border_color = COLOR_BORDER
	loupe_style.set_border_width_all(2)
	loupe_style.set_corner_radius_all(0)
	_loupe_btn.add_theme_stylebox_override("normal", loupe_style)
	var loupe_hover = loupe_style.duplicate()
	loupe_hover.bg_color = COLOR_TAB_SELECTED
	_loupe_btn.add_theme_stylebox_override("hover", loupe_hover)
	# Loupe icon
	var loupe_img = Image.load_from_file(GUI_DIR + "recipe_book.png")
	if loupe_img:
		loupe_img.convert(Image.FORMAT_RGBA8)
		var loupe_region = loupe_img.get_region(Rect2i(6, 6, 16, 16))
		_loupe_btn.icon = ImageTexture.create_from_image(loupe_region)
	_loupe_btn.pressed.connect(_on_tab_pressed.bind(Category.SEARCH))
	add_child(_loupe_btn)


func _build_recipe_grid():
	var grid_slot = 26 * GUI_SCALE
	var icon_sz = 20 * GUI_SCALE
	var pad = (grid_slot - icon_sz) / 2.0

	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var sx = (GRID_MARGIN_LEFT + col * (26 + GRID_SPACING)) * GUI_SCALE
			var sy = (GRID_MARGIN_TOP + row * (26 + GRID_SPACING)) * GUI_SCALE

			# Slot background (dark beveled MC sprites)
			var slot_bg = TextureRect.new()
			slot_bg.texture = _slot_uncraftable_tex
			slot_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			slot_bg.position = Vector2(sx, sy)
			slot_bg.size = Vector2(grid_slot, grid_slot)
			slot_bg.stretch_mode = TextureRect.STRETCH_SCALE
			slot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(slot_bg)

			# Item icon
			var icon = TextureRect.new()
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.position = Vector2(sx + pad, sy + pad)
			icon.size = Vector2(icon_sz, icon_sz)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(icon)

			# Count label (white with dark shadow)
			var cnt = Label.new()
			cnt.position = Vector2(sx + grid_slot - 20 * GUI_SCALE, sy + grid_slot - 12 * GUI_SCALE)
			cnt.size = Vector2(18 * GUI_SCALE, 12 * GUI_SCALE)
			cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cnt.add_theme_font_size_override("font_size", 12)
			cnt.add_theme_color_override("font_color", COLOR_TEXT)
			cnt.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 1))
			cnt.add_theme_constant_override("shadow_offset_x", 1)
			cnt.add_theme_constant_override("shadow_offset_y", 1)
			cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(cnt)

			# Clickable button
			var btn = Button.new()
			btn.flat = true
			btn.position = Vector2(sx, sy)
			btn.size = Vector2(grid_slot, grid_slot)
			var hs = StyleBoxFlat.new()
			hs.bg_color = Color(1, 1, 1, 0.15)
			btn.add_theme_stylebox_override("hover", hs)
			btn.pressed.connect(_on_recipe_clicked.bind(row * GRID_COLS + col))
			btn.mouse_entered.connect(_on_recipe_hover.bind(row * GRID_COLS + col))
			btn.mouse_exited.connect(_on_recipe_exit)
			add_child(btn)

			_recipe_slots.append({"btn": btn, "icon": icon, "count_lbl": cnt, "slot_bg": slot_bg})


func _build_page_nav(pw: float, ph: float):
	var nav_y = ph - 24 * GUI_SCALE
	var center_x = pw / 2.0

	# Page back
	var back_tex = _load_sprite("page_backward.png")
	_page_back_btn = Button.new()
	_page_back_btn.flat = true
	_page_back_btn.position = Vector2(center_x - 50 * GUI_SCALE, nav_y)
	_page_back_btn.size = Vector2(PAGE_BTN_W * GUI_SCALE, PAGE_BTN_H * GUI_SCALE)
	_page_back_btn.pressed.connect(_on_page_back)
	if back_tex:
		_page_back_btn.icon = back_tex
	add_child(_page_back_btn)

	# Page label (light gray on dark)
	_page_label = Label.new()
	_page_label.text = "1/1"
	_page_label.position = Vector2(center_x - 16 * GUI_SCALE, nav_y + 2 * GUI_SCALE)
	_page_label.size = Vector2(32 * GUI_SCALE, 14 * GUI_SCALE)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.add_theme_font_size_override("font_size", 13)
	_page_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page_label)

	# Page forward
	var fwd_tex = _load_sprite("page_forward.png")
	_page_fwd_btn = Button.new()
	_page_fwd_btn.flat = true
	_page_fwd_btn.position = Vector2(center_x + 20 * GUI_SCALE, nav_y)
	_page_fwd_btn.size = Vector2(PAGE_BTN_W * GUI_SCALE, PAGE_BTN_H * GUI_SCALE)
	_page_fwd_btn.pressed.connect(_on_page_forward)
	if fwd_tex:
		_page_fwd_btn.icon = fwd_tex
	add_child(_page_fwd_btn)


func _build_tooltip():
	_tooltip_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.16, 0.16, 0.95)
	style.border_color = Color(0.45, 0.45, 0.45, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(8)
	_tooltip_panel.add_theme_stylebox_override("panel", style)
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 100

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tooltip_name = Label.new()
	_tooltip_name.add_theme_font_size_override("font_size", 14)
	_tooltip_name.add_theme_color_override("font_color", Color(1, 1, 0.85))
	_tooltip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tooltip_name)

	_tooltip_ingredients = Label.new()
	_tooltip_ingredients.add_theme_font_size_override("font_size", 12)
	_tooltip_ingredients.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_tooltip_ingredients.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tooltip_ingredients)

	_tooltip_station = Label.new()
	_tooltip_station.add_theme_font_size_override("font_size", 11)
	_tooltip_station.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_tooltip_station.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tooltip_station)

	_tooltip_panel.add_child(vbox)
	add_child(_tooltip_panel)


# ============================================================
# FILTERING
# ============================================================
func _get_recipe_category(recipe: Dictionary) -> int:
	var out_type = recipe["output_type"]
	var bt_keys = BlockRegistry.BlockType.keys()
	var out_name = bt_keys[out_type] if out_type < bt_keys.size() else ""

	# Equipment
	if out_name in EQUIPMENT_TYPES:
		return Category.EQUIPMENT

	# Construction
	if out_name in CONSTRUCTION_TYPES:
		return Category.CONSTRUCTION

	# Nature
	if out_name in NATURE_TYPES:
		return Category.NATURE

	# Station-based heuristic: furnace smelting = items, tables = items
	var station = recipe["station"]
	if station == "furnace":
		# Smelting outputs: iron ingot, gold ingot, etc. → items
		return Category.ITEMS

	# Default: items
	return Category.ITEMS


func _apply_filter():
	_filtered_recipes.clear()
	var inv = player.get_all_inventory() if player else {}

	for recipe in _all_recipes:
		# Category filter
		if _current_category != Category.SEARCH:
			if _get_recipe_category(recipe) != _current_category:
				continue

		# Craftable filter: skip recipes the player can't craft right now
		if _filter_craftable:
			if not _can_craft_recipe(recipe):
				continue

		# Search filter
		if not _search_text.is_empty():
			var name_lower = recipe["name"].to_lower()
			if name_lower.find(_search_text.to_lower()) == -1:
				continue

		_filtered_recipes.append(recipe)

	# Sort: craftable first, then by name
	_filtered_recipes.sort_custom(func(a, b):
		var a_craft = _can_craft_recipe(a)
		var b_craft = _can_craft_recipe(b)
		if a_craft != b_craft:
			return a_craft  # craftable first
		return a["name"] < b["name"]
	)

	_page = 0
	_refresh_grid()


func _can_craft_recipe(recipe: Dictionary) -> bool:
	if not CraftRegistry.is_recipe_available(recipe, current_tier, has_furnace):
		return false
	var inv = player.get_all_inventory() if player else {}
	return CraftRegistry.can_craft(recipe, inv)


# ============================================================
# REFRESH
# ============================================================
func _refresh_grid():
	var start = _page * SLOTS_PER_PAGE
	var total = _filtered_recipes.size()
	var total_pages = maxi(1, ceili(float(total) / SLOTS_PER_PAGE))

	for i in range(SLOTS_PER_PAGE):
		var recipe_idx = start + i
		var slot = _recipe_slots[i]
		if recipe_idx < total:
			var recipe = _filtered_recipes[recipe_idx]
			slot["icon"].texture = _load_block_icon(recipe["output_type"])
			var count = recipe["output_count"]
			slot["count_lbl"].text = str(count) if count > 1 else ""
			slot["btn"].visible = true
			slot["icon"].visible = true
			slot["slot_bg"].visible = true

			# Craftable or not?
			if _can_craft_recipe(recipe):
				slot["slot_bg"].texture = _slot_craftable_tex
			else:
				slot["slot_bg"].texture = _slot_uncraftable_tex
		else:
			slot["icon"].texture = null
			slot["icon"].visible = false
			slot["count_lbl"].text = ""
			slot["btn"].visible = false
			slot["slot_bg"].visible = false

	# Update page label
	_page_label.text = "%d/%d" % [_page + 1, total_pages]
	_page_back_btn.visible = _page > 0
	_page_fwd_btn.visible = _page < total_pages - 1

	# Update category label
	_category_label.text = CATEGORY_LABELS[_current_category]
	if _filter_craftable:
		_category_label.text += " (fabricables)"

	# Update filter icon
	_filter_icon.texture = _filter_enabled_tex if _filter_craftable else _filter_disabled_tex

	# Update tab styles (selected = lighter with border, Bedrock dark palette)
	for i in range(TAB_COUNT):
		var style: StyleBoxFlat
		if i == _current_category:
			style = StyleBoxFlat.new()
			style.bg_color = COLOR_TAB_SELECTED
			style.border_color = COLOR_TAB_BORDER
			style.set_border_width_all(2)
			style.set_corner_radius_all(0)
		else:
			style = StyleBoxFlat.new()
			style.bg_color = COLOR_TAB_BG
			style.set_corner_radius_all(0)
		_tab_buttons[i]["btn"].add_theme_stylebox_override("normal", style)

	# Search visibility
	_search_input.visible = (_current_category == Category.SEARCH)


# ============================================================
# EVENTS
# ============================================================
func _on_tab_pressed(idx: int):
	_current_category = idx
	_search_text = ""
	if _search_input:
		_search_input.text = ""
	_apply_filter()


func _on_filter_toggle():
	_filter_craftable = not _filter_craftable
	_apply_filter()


func _on_search_changed(new_text: String):
	_search_text = new_text
	_apply_filter()


func _on_page_back():
	if _page > 0:
		_page -= 1
		_refresh_grid()


func _on_page_forward():
	var total_pages = maxi(1, ceili(float(_filtered_recipes.size()) / SLOTS_PER_PAGE))
	if _page < total_pages - 1:
		_page += 1
		_refresh_grid()


func _on_recipe_clicked(slot_idx: int):
	var recipe_idx = _page * SLOTS_PER_PAGE + slot_idx
	if recipe_idx >= _filtered_recipes.size():
		return
	var recipe = _filtered_recipes[recipe_idx]
	if not _can_craft_recipe(recipe):
		return

	# Auto-craft: consume inputs, add output
	if player:
		var inv = player.get_all_inventory()
		# Verify once more
		if not CraftRegistry.can_craft(recipe, inv):
			return
		# Consume inputs
		for input_item in recipe["inputs"]:
			player._remove_from_inventory(input_item[0], input_item[1])
		# Add output
		player._add_to_inventory(recipe["output_type"], recipe["output_count"])
		# Signal
		recipe_crafted.emit(recipe)
		# Refresh parent
		if _parent_refresh_func.is_valid():
			_parent_refresh_func.call()
		# Refresh grid (craftability may have changed)
		_refresh_grid()


func _on_recipe_hover(slot_idx: int):
	var recipe_idx = _page * SLOTS_PER_PAGE + slot_idx
	if recipe_idx >= _filtered_recipes.size():
		_tooltip_panel.visible = false
		return
	var recipe = _filtered_recipes[recipe_idx]
	_tooltip_name.text = recipe["name"]
	if recipe["output_count"] > 1:
		_tooltip_name.text += " x%d" % recipe["output_count"]
	_tooltip_ingredients.text = CraftRegistry.get_ingredients_text(recipe)

	var station_text = ""
	match recipe["station"]:
		"hand": station_text = "A la main"
		"wood_table": station_text = "Table en bois"
		"stone_table": station_text = "Table en pierre"
		"iron_table": station_text = "Table en fer"
		"gold_table": station_text = "Table en or"
		"furnace": station_text = "Fourneau"
	if not _can_craft_recipe(recipe):
		if not CraftRegistry.is_recipe_available(recipe, current_tier, has_furnace):
			station_text += " (station manquante)"
		else:
			station_text += " (ingredients manquants)"
	_tooltip_station.text = station_text
	_tooltip_panel.visible = true

	# Position tooltip near the slot
	var slot = _recipe_slots[slot_idx]
	var slot_pos = slot["btn"].position
	_tooltip_panel.position = Vector2(slot_pos.x + 30 * GUI_SCALE, slot_pos.y)
	# Keep within bounds
	_tooltip_panel.reset_size()


func _on_recipe_exit():
	_tooltip_panel.visible = false


# ============================================================
# ICON LOADING
# ============================================================
func _load_sprite(filename: String) -> ImageTexture:
	var path = RB_DIR + filename
	var img = Image.load_from_file(path)
	if img:
		return ImageTexture.create_from_image(img)
	return null


func _load_block_icon(block_type) -> ImageTexture:
	var cache_key = "block_" + str(block_type)
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key]
	var tex_name = BlockRegistry.get_face_texture(block_type, "top")
	if tex_name == "dirt" and block_type != BlockRegistry.BlockType.DIRT:
		tex_name = BlockRegistry.get_face_texture(block_type, "all")
	var abs_path = GC.resolve_block_texture(tex_name)
	if abs_path.is_empty():
		_icon_cache[cache_key] = null; return null
	var img = Image.new()
	if img.load(abs_path) != OK:
		_icon_cache[cache_key] = null; return null
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


func _load_tool_icon_static(tool_or_block_type) -> ImageTexture:
	# For tab icons — try to load a tool texture or fall back to block icon
	var cache_key = "tool_tab_" + str(tool_or_block_type)
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key]
	# Try tool registry first
	if ToolRegistry:
		var tex_path = ToolRegistry.get_item_texture_path(tool_or_block_type)
		if not tex_path.is_empty():
			var abs_path = ProjectSettings.globalize_path(tex_path)
			if FileAccess.file_exists(abs_path):
				var img = Image.new()
				if img.load(abs_path) == OK:
					img.convert(Image.FORMAT_RGBA8)
					var tex = ImageTexture.create_from_image(img)
					_icon_cache[cache_key] = tex
					return tex
	# Fallback to block icon
	var tex = _load_block_icon(tool_or_block_type)
	_icon_cache[cache_key] = tex
	return tex
