# recipe_book_ui.gd v1.1.0
# Panneau de recettes MC Bedrock — s'affiche à gauche de l'inventaire ou du craft
# 5 onglets : Recherche, Construction, Equipement, Objets, Nature
# Filtre fabricables, barre de recherche, grille paginée, auto-craft au clic
# v1.1.0 — Fix positionnement : onglets hors du panneau, loupe en haut à droite, search sous le label

extends Control

const GC = preload("res://scripts/game_config.gd")
const GUI_DIR = "res://TexturesPack/Faithful32/assets/minecraft/textures/gui/"
const RB_DIR = GUI_DIR + "sprites/recipe_book/"
const GUI_SCALE = 2

# Atlas recipe_book.png : panneau = region (2,2)-(296,334) en Faithful32
const PANEL_ATLAS_X = 2
const PANEL_ATLAS_Y = 2
const PANEL_ATLAS_W = 294
const PANEL_ATLAS_H = 332

# Layout — tabs ABOVE the panel (negative Y = outside, protruding)
const TAB_W = 54         # largeur d'un onglet (Faithful32)
const TAB_H = 30         # hauteur d'un onglet
const TAB_COUNT = 5
const TAB_MARGIN_LEFT = 6
const TAB_SPACING = 2
const TAB_Y_OFFSET = -28  # pixels au-dessus du panneau (négatif = hors du panel)

# Loupe en haut à droite du panneau
const LOUPE_SIZE = 20     # taille icône loupe (Faithful32)
const LOUPE_MARGIN = 8    # marge depuis le bord

# Search bar sous le label catégorie
const SEARCH_Y = 30       # Y dans le panneau (Faithful32 px)
const SEARCH_H = 24
const SEARCH_MARGIN = 10

const FILTER_W = 52
const FILTER_H = 26

const GRID_COLS = 5
const GRID_ROWS = 4
const GRID_MARGIN_LEFT = 12
const GRID_MARGIN_TOP = 62  # sous la barre de recherche
const GRID_SPACING = 2

const SLOTS_PER_PAGE = 20  # 5x4
const PAGE_BTN_W = 24
const PAGE_BTN_H = 34

# Categories
enum Category { SEARCH, CONSTRUCTION, EQUIPMENT, ITEMS, NATURE }

# Category icons — block types pour chaque onglet
const CATEGORY_ICONS = [
	-1,  # SEARCH — utilise la loupe du fond
	BlockRegistry.BlockType.BRICK,          # CONSTRUCTION
	BlockRegistry.BlockType.IRON_SWORD,     # EQUIPMENT (sera tool icon)
	BlockRegistry.BlockType.TORCH,          # ITEMS
	BlockRegistry.BlockType.LEAVES,         # NATURE
]

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
var _panel_bg: TextureRect = null
var _tab_buttons: Array = []      # [{btn, icon, tab_bg}]
var _tab_selected_tex: ImageTexture = null
var _tab_normal_tex: ImageTexture = null
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
var _parent_refresh_func: Callable

signal recipe_crafted(recipe: Dictionary)


# Persistent state — remembered across open/close
static var _was_open: bool = false

func _ready():
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false  # Allow tabs to protrude above the panel


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
	if visible:
		_page = 0
		_apply_filter()


func _build_ui():
	var pw = PANEL_ATLAS_W * GUI_SCALE
	var ph = PANEL_ATLAS_H * GUI_SCALE

	# --- Panel background ---
	var atlas_img = Image.load_from_file(GUI_DIR + "recipe_book.png")
	if atlas_img:
		atlas_img.convert(Image.FORMAT_RGBA8)
		var panel_region = atlas_img.get_region(Rect2i(PANEL_ATLAS_X, PANEL_ATLAS_Y, PANEL_ATLAS_W, PANEL_ATLAS_H))
		_panel_bg = TextureRect.new()
		_panel_bg.texture = ImageTexture.create_from_image(panel_region)
		_panel_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_panel_bg.position = Vector2.ZERO
		_panel_bg.size = Vector2(pw, ph)
		_panel_bg.stretch_mode = TextureRect.STRETCH_SCALE
		_panel_bg.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_panel_bg)

	size = Vector2(pw, ph)

	# --- Load sprite textures ---
	_tab_selected_tex = _load_sprite("tab_selected.png")
	_tab_normal_tex = _load_sprite("tab.png")
	_filter_enabled_tex = _load_sprite("filter_enabled.png")
	_filter_disabled_tex = _load_sprite("filter_disabled.png")
	_slot_craftable_tex = _load_sprite("slot_craftable.png")
	_slot_uncraftable_tex = _load_sprite("slot_uncraftable.png")

	# --- Tabs ---
	_build_tabs()

	# --- Category label (en haut du panneau, à gauche) ---
	_category_label = Label.new()
	_category_label.text = CATEGORY_LABELS[0]
	_category_label.position = Vector2(10 * GUI_SCALE, 6 * GUI_SCALE)
	_category_label.size = Vector2(140 * GUI_SCALE, 18 * GUI_SCALE)
	_category_label.add_theme_font_size_override("font_size", 14)
	_category_label.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25))
	_category_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_category_label)

	# --- Filter toggle (à droite du label catégorie) ---
	var filter_x = pw - (FILTER_W + 10) * GUI_SCALE
	var filter_y = 4 * GUI_SCALE
	_filter_btn = Button.new()
	_filter_btn.flat = true
	_filter_btn.position = Vector2(filter_x, filter_y)
	_filter_btn.size = Vector2(FILTER_W * GUI_SCALE, FILTER_H * GUI_SCALE)
	_filter_btn.pressed.connect(_on_filter_toggle)
	_filter_btn.tooltip_text = "Toutes / Fabricables"
	add_child(_filter_btn)
	_filter_icon = TextureRect.new()
	_filter_icon.texture = _filter_disabled_tex
	_filter_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_filter_icon.position = Vector2(filter_x, filter_y)
	_filter_icon.size = Vector2(FILTER_W * GUI_SCALE, FILTER_H * GUI_SCALE)
	_filter_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_filter_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_filter_icon)

	# --- Search input (sous le label catégorie) ---
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Rechercher..."
	_search_input.position = Vector2(SEARCH_MARGIN * GUI_SCALE, SEARCH_Y * GUI_SCALE)
	_search_input.size = Vector2((PANEL_ATLAS_W - SEARCH_MARGIN * 2) * GUI_SCALE, SEARCH_H * GUI_SCALE)
	_search_input.add_theme_font_size_override("font_size", 13)
	_search_input.text_changed.connect(_on_search_changed)
	add_child(_search_input)

	# --- Recipe grid ---
	_build_recipe_grid()

	# --- Page navigation ---
	_build_page_nav(pw, ph)

	# --- Tooltip ---
	_build_tooltip()


func _build_tabs():
	var tw = TAB_W * GUI_SCALE
	var th = TAB_H * GUI_SCALE
	var ty = TAB_Y_OFFSET * GUI_SCALE  # négatif = au-dessus du panneau

	for i in range(TAB_COUNT):
		var tx = (TAB_MARGIN_LEFT + i * (TAB_W + TAB_SPACING)) * GUI_SCALE

		# Tab background
		var tab_bg = TextureRect.new()
		tab_bg.texture = _tab_selected_tex if i == 0 else _tab_normal_tex
		tab_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tab_bg.position = Vector2(tx, ty)
		tab_bg.size = Vector2(tw, th)
		tab_bg.stretch_mode = TextureRect.STRETCH_SCALE
		tab_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tab_bg)

		# Tab icon
		var icon = TextureRect.new()
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var icon_sz = 20 * GUI_SCALE
		var icon_pad_x = (tw - icon_sz) / 2.0
		var icon_pad_y = (th - icon_sz) / 2.0
		icon.position = Vector2(tx + icon_pad_x, ty + icon_pad_y)
		icon.size = Vector2(icon_sz, icon_sz)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Load category icon
		var bt = CATEGORY_ICONS[i]
		if bt == -1:
			# Search tab — load loupe sprite
			icon.texture = _load_sprite("filter_disabled.png")
		elif bt == BlockRegistry.BlockType.IRON_SWORD:
			icon.texture = _load_tool_icon_static(bt)
		else:
			icon.texture = _load_block_icon(bt)
		add_child(icon)

		# Tab button (clickable)
		var btn = Button.new()
		btn.flat = true
		btn.position = Vector2(tx, ty)
		btn.size = Vector2(tw, th)
		btn.pressed.connect(_on_tab_pressed.bind(i))
		add_child(btn)

		_tab_buttons.append({"btn": btn, "bg": tab_bg, "icon": icon})


func _build_recipe_grid():
	var slot_px = SLOT_SIZE / 2 * GUI_SCALE  # slots are 25 vanilla → 50 F32 / 2 for display
	# Actually let's use a good size for the grid
	var grid_slot = 26 * GUI_SCALE  # 26 vanilla pixels per slot
	var icon_sz = 20 * GUI_SCALE
	var pad = (grid_slot - icon_sz) / 2.0

	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var sx = (GRID_MARGIN_LEFT + col * (26 + GRID_SPACING)) * GUI_SCALE
			var sy = (GRID_MARGIN_TOP + row * (26 + GRID_SPACING)) * GUI_SCALE

			# Slot background
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

			# Count label
			var cnt = Label.new()
			cnt.position = Vector2(sx + grid_slot - 20 * GUI_SCALE, sy + grid_slot - 12 * GUI_SCALE)
			cnt.size = Vector2(18 * GUI_SCALE, 12 * GUI_SCALE)
			cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cnt.add_theme_font_size_override("font_size", 12)
			cnt.add_theme_color_override("font_color", Color.WHITE)
			cnt.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
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
	var nav_y = ph - 40 * GUI_SCALE
	var center_x = pw / 2.0

	# Page back
	var back_tex = _load_sprite("page_backward.png")
	_page_back_btn = Button.new()
	_page_back_btn.flat = true
	_page_back_btn.position = Vector2(center_x - 60 * GUI_SCALE, nav_y)
	_page_back_btn.size = Vector2(PAGE_BTN_W * GUI_SCALE, PAGE_BTN_H * GUI_SCALE)
	_page_back_btn.pressed.connect(_on_page_back)
	if back_tex:
		_page_back_btn.icon = back_tex
	add_child(_page_back_btn)

	# Page label
	_page_label = Label.new()
	_page_label.text = "1/1"
	_page_label.position = Vector2(center_x - 20 * GUI_SCALE, nav_y + 4 * GUI_SCALE)
	_page_label.size = Vector2(40 * GUI_SCALE, 20 * GUI_SCALE)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.add_theme_font_size_override("font_size", 13)
	_page_label.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25))
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
	style.bg_color = Color(0.12, 0.08, 0.18, 0.95)
	style.border_color = Color(0.4, 0.3, 0.6, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
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

	# Update tab backgrounds
	for i in range(TAB_COUNT):
		_tab_buttons[i]["bg"].texture = _tab_selected_tex if i == _current_category else _tab_normal_tex

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
