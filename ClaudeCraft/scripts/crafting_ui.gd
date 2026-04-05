# crafting_ui.gd v3.4.0
# Craft MC drag & drop — slots fixes, placement libre
# Rangee du bas = hotbar (reference, pas de stockage)
# Rangees du haut = inventaire reel (27 slots, pagine)
# Hotbar ne modifie JAMAIS l'inventaire — c'est un raccourci

extends CanvasLayer

const GC = preload("res://scripts/game_config.gd")
const GUI_DIR = "res://TexturesPack/Faithful32/assets/minecraft/textures/gui/"
const GUI_SCALE = 2
const MAX_STACK = 64

var player: CharacterBody3D = null
var is_open: bool = false
var current_tier: int = 0
var has_furnace: bool = false
var _icon_cache: Dictionary = {}

# --- Slots inventaire (27 slots, pagines) ---
var _inv_slots_data: Array = []
var _inv_page: int = 0
const INV_SLOTS_PER_PAGE = 27  # 3x9

# --- Drag & drop ---
var _grid_contents: Array = []
var _held_item: Dictionary = {}  # {"is_tool":bool, "block_type":X, "tool_type":X, "count":N} ou {}
var _held_source: String = ""    # "inv", "grid", "hotbar"
var _held_hotbar_idx: int = -1
var _matched_recipe: Dictionary = {}
var _available_recipes: Array = []

# --- UI nodes ---
var _background: ColorRect = null
var _craft_texture: TextureRect = null
var _title_label: Label = null
var _station_label: Label = null
var _grid_ui: Array = []
var _output_btn: Button = null
var _output_tex: TextureRect = null
var _output_count_lbl: Label = null
var _inv_ui: Array = []       # 27 slots inventaire
var _hotbar_ui: Array = []    # 9 slots hotbar
var _cursor_tex: TextureRect = null
var _cursor_count: Label = null
var _hover_name_label: Label = null
var _hint_label: Label = null
var _page_label: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null

# Recipe book
var _recipe_book: Control = null
var _recipe_book_btn: Button = null
var _recipe_book_icon: TextureRect = null
const RB_DIR = GUI_DIR + "sprites/recipe_book/"

const TEX_W = 352
const TEX_H = 332
const GRID_X = 60
const GRID_Y = 34
const GRID_STEP = 36
const OUT_X = 248
const OUT_Y = 70
const INV_X = 14
const INV_Y = 166
const HOTBAR_Y = 282
const SLOT_SZ = 36

func _ready():
	layer = 10
	visible = false
	add_to_group("crafting_ui")
	_grid_contents.resize(9)
	for i in range(9):
		_grid_contents[i] = {}
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	_build_ui()

# ============================================================
# BUILD UI
# ============================================================
func _build_ui():
	var disp_w = TEX_W * GUI_SCALE
	var disp_h = TEX_H * GUI_SCALE
	var tex_left = -disp_w / 2.0
	var tex_top = -disp_h / 2.0
	var icon_sz = 28 * GUI_SCALE
	var slot_px = SLOT_SZ * GUI_SCALE
	var pad = (slot_px - icon_sz) / 2.0

	_background = ColorRect.new()
	_background.color = Color(0, 0, 0, 0.65)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_background.gui_input.connect(_on_bg_input)
	add_child(_background)

	var img = Image.load_from_file(GUI_DIR + "container/crafting_table.png")
	var craft_tex: ImageTexture = null
	if img:
		craft_tex = ImageTexture.create_from_image(img.get_region(Rect2i(0, 0, TEX_W, TEX_H)))
	_craft_texture = TextureRect.new()
	_craft_texture.texture = craft_tex
	_craft_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_craft_texture.set_anchors_preset(Control.PRESET_CENTER)
	_craft_texture.offset_left = tex_left; _craft_texture.offset_right = -tex_left
	_craft_texture.offset_top = tex_top; _craft_texture.offset_bottom = -tex_top
	_craft_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_craft_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_craft_texture)

	_title_label = _make_label("Crafting", 16, Color(0.25, 0.25, 0.25))
	_title_label.set_anchors_preset(Control.PRESET_CENTER)
	_title_label.offset_left = -150; _title_label.offset_right = 150
	_title_label.offset_top = tex_top + 6 * GUI_SCALE; _title_label.offset_bottom = tex_top + 20 * GUI_SCALE
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title_label)
	_station_label = _make_label("", 14, Color(1, 0.9, 0.7), true)
	_station_label.set_anchors_preset(Control.PRESET_CENTER)
	_station_label.offset_left = -200; _station_label.offset_right = 200
	_station_label.offset_top = tex_top - 24; _station_label.offset_bottom = tex_top - 4
	_station_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_station_label)

	# --- Grille craft 3x3 ---
	for r in range(3):
		for c in range(3):
			var idx = r * 3 + c
			var sx = tex_left + (GRID_X + c * GRID_STEP) * GUI_SCALE
			var sy = tex_top + (GRID_Y + r * GRID_STEP) * GUI_SCALE
			var d = _make_slot(sx, sy, slot_px, icon_sz, pad)
			d["btn"].gui_input.connect(_on_grid_input.bind(idx))
			d["btn"].mouse_entered.connect(_on_grid_hover.bind(idx))
			d["btn"].mouse_exited.connect(_on_hover_exit)
			_grid_ui.append(d)

	# --- Output ---
	var ox = tex_left + OUT_X * GUI_SCALE
	var oy = tex_top + OUT_Y * GUI_SCALE
	_output_btn = Button.new()
	_output_btn.flat = true
	_output_btn.set_anchors_preset(Control.PRESET_CENTER)
	_output_btn.offset_left = ox; _output_btn.offset_right = ox + slot_px
	_output_btn.offset_top = oy; _output_btn.offset_bottom = oy + slot_px
	_output_btn.gui_input.connect(_on_output_input)
	_output_btn.mouse_entered.connect(_on_output_hover)
	_output_btn.mouse_exited.connect(_on_hover_exit)
	add_child(_output_btn)
	_output_tex = _make_tex_rect(ox + pad, oy + pad, icon_sz)
	add_child(_output_tex)
	_output_count_lbl = _make_count_label(ox, oy, slot_px)
	add_child(_output_count_lbl)

	# --- 27 slots inventaire (3x9) ---
	for row in range(3):
		for col in range(9):
			var sx = tex_left + (INV_X + col * SLOT_SZ) * GUI_SCALE
			var sy = tex_top + (INV_Y + row * SLOT_SZ) * GUI_SCALE
			var d = _make_inv_slot(sx, sy, slot_px, icon_sz, pad)
			d["btn"].gui_input.connect(_on_inv_input.bind(_inv_ui.size()))
			d["btn"].mouse_entered.connect(_on_inv_hover.bind(_inv_ui.size()))
			d["btn"].mouse_exited.connect(_on_hover_exit)
			_inv_ui.append(d)

	# --- 9 slots hotbar (rangee du bas) ---
	for col in range(9):
		var sx = tex_left + (INV_X + col * SLOT_SZ) * GUI_SCALE
		var sy = tex_top + HOTBAR_Y * GUI_SCALE
		var d = _make_inv_slot(sx, sy, slot_px, icon_sz, pad)
		d["btn"].gui_input.connect(_on_hotbar_input.bind(col))
		d["btn"].mouse_entered.connect(_on_hotbar_hover.bind(col))
		d["btn"].mouse_exited.connect(_on_hover_exit)
		_hotbar_ui.append(d)

	# --- Pagination ---
	var nav_y = disp_h / 2 + 10
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.15, 0.3, 0.85)
	btn_style.border_color = Color(0.5, 0.3, 0.7, 0.9)
	btn_style.set_border_width_all(2); btn_style.set_corner_radius_all(4)
	_prev_btn = Button.new()
	_prev_btn.text = "< Prec."; _prev_btn.set_anchors_preset(Control.PRESET_CENTER)
	_prev_btn.offset_left = -120; _prev_btn.offset_right = -30
	_prev_btn.offset_top = nav_y; _prev_btn.offset_bottom = nav_y + 30
	_prev_btn.add_theme_stylebox_override("normal", btn_style)
	_prev_btn.add_theme_color_override("font_color", Color.WHITE)
	_prev_btn.pressed.connect(_on_prev_page); add_child(_prev_btn)
	_page_label = _make_label("1/1", 14, Color(1, 1, 0.9))
	_page_label.set_anchors_preset(Control.PRESET_CENTER)
	_page_label.offset_left = -30; _page_label.offset_right = 30
	_page_label.offset_top = nav_y + 4; _page_label.offset_bottom = nav_y + 30
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_page_label)
	_next_btn = Button.new()
	_next_btn.text = "Suiv. >"; _next_btn.set_anchors_preset(Control.PRESET_CENTER)
	_next_btn.offset_left = 30; _next_btn.offset_right = 120
	_next_btn.offset_top = nav_y; _next_btn.offset_bottom = nav_y + 30
	_next_btn.add_theme_stylebox_override("normal", btn_style)
	_next_btn.add_theme_color_override("font_color", Color.WHITE)
	_next_btn.pressed.connect(_on_next_page); add_child(_next_btn)

	# --- Label nom de l'objet survolé (fixe, centré entre grille et inventaire) ---
	_hover_name_label = Label.new(); _hover_name_label.set_anchors_preset(Control.PRESET_CENTER)
	_hover_name_label.add_theme_font_size_override("font_size", 15)
	_hover_name_label.add_theme_color_override("font_color", Color.WHITE)
	_hover_name_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 1))
	_hover_name_label.add_theme_constant_override("shadow_offset_x", 2)
	_hover_name_label.add_theme_constant_override("shadow_offset_y", 2)
	_hover_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_name_label.offset_left = tex_left; _hover_name_label.offset_right = -tex_left
	_hover_name_label.offset_top = tex_top + 148 * GUI_SCALE; _hover_name_label.offset_bottom = tex_top + 165 * GUI_SCALE
	_hover_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; _hover_name_label.visible = false
	add_child(_hover_name_label)

	_hint_label = _make_label("Glissez les ingredients sur la grille pour crafter", 13, Color(0.8, 0.8, 0.7, 0.8), true)
	_hint_label.set_anchors_preset(Control.PRESET_CENTER)
	_hint_label.offset_left = -disp_w / 2; _hint_label.offset_right = disp_w / 2
	_hint_label.offset_top = disp_h / 2 + 6; _hint_label.offset_bottom = disp_h / 2 + 24
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_hint_label)

	# --- Curseur drag&drop (CRITIQUE — doit être créé quoi qu'il arrive) ---
	_cursor_tex = TextureRect.new()
	_cursor_tex.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cursor_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cursor_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cursor_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE; _cursor_tex.visible = false
	add_child(_cursor_tex)
	_cursor_count = Label.new()
	_cursor_count.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cursor_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cursor_count.add_theme_font_size_override("font_size", 14)
	_cursor_count.add_theme_color_override("font_color", Color.WHITE)
	_cursor_count.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
	_cursor_count.add_theme_constant_override("shadow_offset_x", 2)
	_cursor_count.add_theme_constant_override("shadow_offset_y", 2)
	_cursor_count.mouse_filter = Control.MOUSE_FILTER_IGNORE; _cursor_count.visible = false
	add_child(_cursor_count)

	# --- Recipe book (bouton + panel — protégé pour ne pas casser le curseur) ---
	_setup_recipe_book(tex_left, tex_top)

func _setup_recipe_book(tex_left: float, tex_top: float):
	var rb_btn_img = Image.load_from_file(RB_DIR + "button.png")
	if rb_btn_img:
		var rb_icon_tex = ImageTexture.create_from_image(rb_btn_img)
		var rb_w = 40 * GUI_SCALE
		var rb_h = 36 * GUI_SCALE
		var rb_x = tex_left + (TEX_W - 46) * GUI_SCALE
		var rb_y = tex_top - rb_h  # bord inférieur de l'icône = bord supérieur du panneau
		_recipe_book_icon = TextureRect.new()
		_recipe_book_icon.texture = rb_icon_tex
		_recipe_book_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_recipe_book_icon.set_anchors_preset(Control.PRESET_CENTER)
		_recipe_book_icon.offset_left = rb_x; _recipe_book_icon.offset_right = rb_x + rb_w
		_recipe_book_icon.offset_top = rb_y; _recipe_book_icon.offset_bottom = rb_y + rb_h
		_recipe_book_icon.stretch_mode = TextureRect.STRETCH_SCALE
		_recipe_book_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_recipe_book_icon)
		_recipe_book_btn = Button.new()
		_recipe_book_btn.flat = true
		_recipe_book_btn.set_anchors_preset(Control.PRESET_CENTER)
		_recipe_book_btn.offset_left = rb_x; _recipe_book_btn.offset_right = rb_x + rb_w
		_recipe_book_btn.offset_top = rb_y; _recipe_book_btn.offset_bottom = rb_y + rb_h
		_recipe_book_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_recipe_book_btn.pressed.connect(_on_recipe_book_toggle)
		add_child(_recipe_book_btn)
	var rb_script = load("res://scripts/recipe_book_ui.gd")
	if rb_script:
		_recipe_book = rb_script.new()
		_recipe_book.set_anchors_preset(Control.PRESET_CENTER)
		var rb_panel_w = 260 * GUI_SCALE  # match PANEL_W in recipe_book_ui.gd
		_recipe_book.offset_left = tex_left - rb_panel_w - 4
		_recipe_book.offset_right = tex_left - 4
		_recipe_book.offset_top = tex_top
		_recipe_book.offset_bottom = tex_top + TEX_H * GUI_SCALE
		add_child(_recipe_book)

# ============================================================
# HELPERS
# ============================================================
func _make_label(text: String, size: int, color: Color, shadow: bool = false) -> Label:
	var lbl = Label.new(); lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if shadow:
		lbl.add_theme_color_override("font_shadow_color", Color(0.15, 0.15, 0.15, 1))
		lbl.add_theme_constant_override("shadow_offset_x", 2); lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE; return lbl

func _make_tex_rect(x: float, y: float, sz: float) -> TextureRect:
	var tr = TextureRect.new(); tr.set_anchors_preset(Control.PRESET_CENTER)
	tr.offset_left = x; tr.offset_right = x + sz; tr.offset_top = y; tr.offset_bottom = y + sz
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE; return tr

func _make_count_label(sx: float, sy: float, slot_px: float) -> Label:
	var lbl = Label.new(); lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left = sx + slot_px - 26 * GUI_SCALE; lbl.offset_right = sx + slot_px - 2
	lbl.offset_top = sy + slot_px - 14 * GUI_SCALE; lbl.offset_bottom = sy + slot_px
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
	lbl.add_theme_constant_override("shadow_offset_x", 2); lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE; return lbl

func _make_slot(sx: float, sy: float, slot_px: float, icon_sz: float, pad: float) -> Dictionary:
	var btn = Button.new(); btn.flat = true; btn.set_anchors_preset(Control.PRESET_CENTER)
	btn.offset_left = sx; btn.offset_right = sx + slot_px; btn.offset_top = sy; btn.offset_bottom = sy + slot_px
	var hs = StyleBoxFlat.new(); hs.bg_color = Color(1, 1, 1, 0.12); btn.add_theme_stylebox_override("hover", hs)
	add_child(btn)
	var tex = _make_tex_rect(sx + pad, sy + pad, icon_sz); add_child(tex)
	var cnt = _make_count_label(sx, sy, slot_px); add_child(cnt)
	return {"btn": btn, "tex": tex, "count_lbl": cnt}

func _make_inv_slot(sx: float, sy: float, slot_px: float, icon_sz: float, pad: float) -> Dictionary:
	return _make_slot(sx, sy, slot_px, icon_sz, pad)

# ============================================================
# OPEN / CLOSE
# ============================================================
func open_crafting(tier: int = 0, furnace: bool = false):
	is_open = true
	current_tier = tier; has_furnace = furnace
	_inv_page = 0; _held_item = {}; _held_source = ""
	for i in range(9): _grid_contents[i] = {}
	_matched_recipe = {}
	_available_recipes = []
	for recipe in CraftRegistry.get_all_recipes():
		if recipe.has("_tool_tier") or recipe.get("output_count", 0) <= 0:
			continue
		if CraftRegistry.is_recipe_available(recipe, current_tier, has_furnace):
			_available_recipes.append(recipe)
	_build_inv_slots()
	_update_station_label()
	visible = true
	_refresh_all()
	# Restaurer l'état du recipe book
	if _recipe_book:
		var RecipeBookUI = load("res://scripts/recipe_book_ui.gd")
		if RecipeBookUI._was_open:
			_recipe_book.setup(player, current_tier, has_furnace, self, Callable(self, "_on_recipe_book_craft"))
			_recipe_book.visible = true
		else:
			_recipe_book.visible = false

func close_crafting():
	# Mémoriser l'état du recipe book
	if _recipe_book:
		var RecipeBookUI = load("res://scripts/recipe_book_ui.gd")
		RecipeBookUI._was_open = _recipe_book.visible
		_recipe_book.visible = false
	_return_items_to_inventory()
	is_open = false; visible = false

func _on_recipe_book_toggle():
	if _recipe_book:
		if not _recipe_book.visible:
			_recipe_book.setup(player, current_tier, has_furnace, self, Callable(self, "_on_recipe_book_craft"))
		_recipe_book.toggle()

func _on_recipe_book_craft():
	_build_inv_slots()
	_refresh_all()

func _update_station_label():
	if has_furnace: _station_label.text = Locale.tr_ui("craft_furnace")
	elif current_tier >= 4: _station_label.text = Locale.tr_ui("craft_tier_4")
	elif current_tier == 3: _station_label.text = Locale.tr_ui("craft_tier_3")
	elif current_tier == 2: _station_label.text = Locale.tr_ui("craft_tier_2")
	elif current_tier == 1: _station_label.text = Locale.tr_ui("craft_tier_1")
	else: _station_label.text = Locale.tr_ui("craft_hand")

# ============================================================
# SLOT DATA
# ============================================================
func _build_inv_slots():
	_inv_slots_data.clear()
	if not player: return
	# Blocs
	var inv = player.get_all_inventory()
	var sorted_types: Array = []
	for bt in inv:
		if inv[bt] > 0: sorted_types.append(bt)
	sorted_types.sort_custom(func(a, b): return int(a) < int(b))
	for bt in sorted_types:
		_inv_slots_data.append({"block_type": bt, "count": inv[bt]})
	# Outils
	var tools = player.get_all_tools()
	for tt in tools:
		if tools[tt] > 0:
			_inv_slots_data.append({"is_tool": true, "tool_type": tt, "count": tools[tt]})
	# Padding
	var min_size = maxi(INV_SLOTS_PER_PAGE, _inv_slots_data.size() + INV_SLOTS_PER_PAGE)
	while _inv_slots_data.size() < min_size:
		_inv_slots_data.append({})

func _add_to_inv_slot_and_dict(bt, count: int):
	player._add_to_inventory(bt, count)
	for i in range(_inv_slots_data.size()):
		if not _inv_slots_data[i].is_empty() and not _inv_slots_data[i].get("is_tool", false) and _inv_slots_data[i].get("block_type") == bt:
			_inv_slots_data[i]["count"] += count; return
	for i in range(_inv_slots_data.size()):
		if _inv_slots_data[i].is_empty():
			_inv_slots_data[i] = {"block_type": bt, "count": count}; return
	_inv_slots_data.append({"block_type": bt, "count": count})

func _pick_from_inv_slot(slot_idx: int):
	var slot = _inv_slots_data[slot_idx]
	if slot.get("is_tool", false):
		_held_item = {"is_tool": true, "tool_type": slot["tool_type"], "count": slot.get("count", 1)}
		player.tool_inventory[slot["tool_type"]] = player.tool_inventory.get(slot["tool_type"], 1) - slot.get("count", 1)
	else:
		_held_item = {"is_tool": false, "block_type": slot["block_type"], "count": slot["count"]}
		player._remove_from_inventory(slot["block_type"], slot["count"])
	_held_source = "inv"
	_inv_slots_data[slot_idx] = {}

func _place_on_inv_slot(slot_idx: int):
	if _held_item.get("is_tool", false):
		_inv_slots_data[slot_idx] = {"is_tool": true, "tool_type": _held_item["tool_type"], "count": _held_item.get("count", 1)}
		player.tool_inventory[_held_item["tool_type"]] = player.tool_inventory.get(_held_item["tool_type"], 0) + _held_item.get("count", 1)
	else:
		_inv_slots_data[slot_idx] = {"block_type": _held_item["block_type"], "count": _held_item["count"]}
		player._add_to_inventory(_held_item["block_type"], _held_item["count"])
	_held_item = {}; _held_source = ""

func sort_inventory():
	_build_inv_slots(); _inv_page = 0; _refresh_all()

# ============================================================
# REFRESH
# ============================================================
func _refresh_all():
	_refresh_inv_slots()
	_refresh_hotbar_slots()
	_refresh_grid_visuals()
	_check_recipe()
	_update_output()
	_update_cursor()
	_update_pagination()

func _refresh_inv_slots():
	var offset = _inv_page * INV_SLOTS_PER_PAGE
	for i in range(_inv_ui.size()):
		var ui = _inv_ui[i]; var idx = offset + i
		if idx < _inv_slots_data.size() and not _inv_slots_data[idx].is_empty():
			var item = _inv_slots_data[idx]
			if item.get("is_tool", false):
				ui["tex"].texture = _load_tool_icon(item["tool_type"])
			else:
				ui["tex"].texture = _load_block_icon(item["block_type"])
			ui["tex"].modulate = Color.WHITE
			ui["count_lbl"].text = str(item["count"]) if item["count"] > 1 else ""
		else:
			ui["tex"].texture = null; ui["count_lbl"].text = ""
		ui["btn"].visible = true

func _refresh_hotbar_slots():
	if not player: return
	for i in range(9):
		var ui = _hotbar_ui[i]
		var tool_type = player.hotbar_tool_slots[i] if i < player.hotbar_tool_slots.size() else ToolRegistry.ToolType.NONE
		if tool_type != ToolRegistry.ToolType.NONE:
			ui["tex"].texture = _load_tool_icon(tool_type)
			ui["tex"].modulate = Color.WHITE
			ui["count_lbl"].text = ""
		else:
			var bt = player.hotbar_slots[i] if i < player.hotbar_slots.size() else 0
			var count = player.get_inventory_count(bt)
			if count > 0:
				ui["tex"].texture = _load_block_icon(bt)
				ui["tex"].modulate = Color.WHITE
				ui["count_lbl"].text = str(count) if count > 1 else ""
			else:
				ui["tex"].texture = null; ui["count_lbl"].text = ""
		ui["btn"].visible = true

func _refresh_grid_visuals():
	for i in range(9):
		var cell = _grid_contents[i]; var ui = _grid_ui[i]
		if not cell.is_empty():
			ui["tex"].texture = _load_block_icon(cell["block_type"])
			ui["tex"].modulate = Color.WHITE
			ui["count_lbl"].text = str(cell["count"]) if cell["count"] > 1 else ""
		else:
			ui["tex"].texture = null; ui["count_lbl"].text = ""

func _update_output():
	if not _matched_recipe.is_empty():
		_output_tex.texture = _load_block_icon(_matched_recipe["output_type"])
		_output_tex.modulate = Color.WHITE
		var oc = _matched_recipe.get("output_count", 1)
		_output_count_lbl.text = "x%d" % oc if oc > 1 else ""
		_hint_label.text = _matched_recipe.get("name", "")
		_hint_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 0.9))
	else:
		_output_tex.texture = null; _output_count_lbl.text = ""
		var has_items = false
		for cell in _grid_contents:
			if not cell.is_empty(): has_items = true; break
		if has_items:
			_hint_label.text = "Aucune recette ne correspond"
			_hint_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5, 0.9))
		else:
			_hint_label.text = "Glissez les ingredients sur la grille pour crafter"
			_hint_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7, 0.8))

func _update_cursor():
	if not _held_item.is_empty():
		if _held_item.get("is_tool", false):
			_cursor_tex.texture = _load_tool_icon(_held_item["tool_type"])
		else:
			_cursor_tex.texture = _load_block_icon(_held_item["block_type"])
		_cursor_tex.visible = true
		var c = _held_item.get("count", 0)
		_cursor_count.text = str(c) if c > 1 else ""
		_cursor_count.visible = c > 1
	else:
		_cursor_tex.visible = false; _cursor_count.visible = false

func _update_pagination():
	var total = maxi(1, ceili(float(_inv_slots_data.size()) / INV_SLOTS_PER_PAGE))
	if _page_label: _page_label.text = "%d/%d" % [_inv_page + 1, total]
	if _prev_btn: _prev_btn.visible = total > 1; _prev_btn.disabled = _inv_page <= 0
	if _next_btn: _next_btn.visible = total > 1; _next_btn.disabled = _inv_page >= total - 1

# ============================================================
# INPUT — INVENTORY (items reels, modifie le dictionnaire)
# ============================================================
func _same_inv_type(a: Dictionary, b: Dictionary) -> bool:
	if a.get("is_tool", false) != b.get("is_tool", false): return false
	if a.get("is_tool", false): return a.get("tool_type") == b.get("tool_type")
	return a.get("block_type") == b.get("block_type")

func _dict_add_held():
	# Ajoute le held_item au dictionnaire correspondant (bloc ou outil)
	if _held_item.get("is_tool", false):
		player.tool_inventory[_held_item["tool_type"]] = player.tool_inventory.get(_held_item["tool_type"], 0) + _held_item.get("count", 1)
	else:
		player._add_to_inventory(_held_item["block_type"], _held_item["count"])

func _dict_remove_slot(slot: Dictionary):
	# Retire un slot du dictionnaire correspondant
	if slot.get("is_tool", false):
		player.tool_inventory[slot["tool_type"]] = maxi(0, player.tool_inventory.get(slot["tool_type"], 0) - slot.get("count", 1))
	else:
		player._remove_from_inventory(slot["block_type"], slot["count"])

func _readd_to_inv_slots(item: Dictionary):
	# Remettre un item dans _inv_slots_data (fusionner si même type existe)
	for i in range(_inv_slots_data.size()):
		if _same_inv_type(_inv_slots_data[i], item):
			_inv_slots_data[i]["count"] = _inv_slots_data[i].get("count", 1) + item.get("count", 1)
			return
	for i in range(_inv_slots_data.size()):
		if _inv_slots_data[i].is_empty():
			_inv_slots_data[i] = item.duplicate(); return
	_inv_slots_data.append(item.duplicate())

func _on_inv_input(event: InputEvent, index: int):
	if not (event is InputEventMouseButton and event.pressed): return
	var slot_idx = _inv_page * INV_SLOTS_PER_PAGE + index
	while slot_idx >= _inv_slots_data.size(): _inv_slots_data.append({})
	var slot = _inv_slots_data[slot_idx]

	if event.button_index == MOUSE_BUTTON_LEFT:
		if _held_item.is_empty():
			# Prendre depuis le slot
			if not slot.is_empty():
				_held_item = slot.duplicate()
				_held_source = "inv"
				_dict_remove_slot(slot)
				_inv_slots_data[slot_idx] = {}
				_refresh_all()
		else:
			if _held_source == "hotbar":
				_restore_hotbar_held(); _refresh_all(); return
			if slot.is_empty():
				# Poser sur slot vide
				_inv_slots_data[slot_idx] = _held_item.duplicate()
				_dict_add_held()
				_held_item = {}; _held_source = ""; _refresh_all()
			elif _same_inv_type(slot, _held_item):
				# Empiler meme type
				slot["count"] = slot.get("count", 1) + _held_item.get("count", 1)
				_dict_add_held()
				_held_item = {}; _held_source = ""; _refresh_all()
			else:
				# Swap types differents
				var temp = slot.duplicate()
				# Poser le held dans le slot
				_inv_slots_data[slot_idx] = _held_item.duplicate()
				_dict_add_held()
				# Prendre l'ancien contenu du slot
				_dict_remove_slot(temp)
				_held_item = temp; _held_source = "inv"
				_refresh_all()

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if not _held_item.is_empty() and not _held_item.get("is_tool", false) and _held_source != "hotbar":
			# Poser 1 bloc
			if slot.is_empty():
				_inv_slots_data[slot_idx] = {"block_type": _held_item["block_type"], "count": 1}
				player._add_to_inventory(_held_item["block_type"], 1)
				_held_item["count"] -= 1
				if _held_item["count"] <= 0: _held_item = {}; _held_source = ""
				_refresh_all()
			elif not slot.get("is_tool", false) and slot.get("block_type") == _held_item.get("block_type"):
				slot["count"] += 1; player._add_to_inventory(_held_item["block_type"], 1)
				_held_item["count"] -= 1
				if _held_item["count"] <= 0: _held_item = {}; _held_source = ""
				_refresh_all()
		elif _held_item.is_empty() and not slot.is_empty() and not slot.get("is_tool", false):
			# Prendre la moitie
			var take = ceili(slot["count"] / 2.0)
			_held_item = {"is_tool": false, "block_type": slot["block_type"], "count": take}
			_held_source = "inv"; player._remove_from_inventory(slot["block_type"], take)
			slot["count"] -= take
			if slot["count"] <= 0: _inv_slots_data[slot_idx] = {}
			_refresh_all()

# ============================================================
# INPUT — HOTBAR (reference seulement, ne touche PAS au dictionnaire)
# ============================================================
func _on_hotbar_input(event: InputEvent, col: int):
	if not (event is InputEventMouseButton and event.pressed): return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _held_item.is_empty():
			# Prendre depuis la hotbar (reference)
			if not player.is_hotbar_slot_empty(col):
				var tool_type = player.hotbar_tool_slots[col] if col < player.hotbar_tool_slots.size() else ToolRegistry.ToolType.NONE
				if tool_type != ToolRegistry.ToolType.NONE:
					_held_item = {"is_tool": true, "tool_type": tool_type, "count": 0}
				else:
					var bt = player.hotbar_slots[col]
					_held_item = {"is_tool": false, "block_type": bt, "count": 0}
				_held_source = "hotbar"; _held_hotbar_idx = col
				player._clear_hotbar_slot(col)
				_refresh_all()
		else:
			if _held_source == "hotbar":
				# Deplacer entre slots hotbar
				if _held_item.get("is_tool", false):
					player.assign_hotbar_tool(col, _held_item["tool_type"])
				else:
					player.assign_hotbar_slot(col, _held_item["block_type"])
				_held_item = {}; _held_source = ""; _refresh_all()
			elif _held_source == "inv":
				# Assigner depuis inventaire vers hotbar = créer pointeur + remettre dans inventaire
				if _held_item.get("is_tool", false):
					player.assign_hotbar_tool(col, _held_item["tool_type"])
				else:
					player.assign_hotbar_slot(col, _held_item["block_type"])
				_dict_add_held()
				_readd_to_inv_slots(_held_item)
				_held_item = {}; _held_source = ""; _refresh_all()
			elif _held_source == "grid":
				# Depuis la grille → assigner a hotbar + retourner en inv
				if not _held_item.get("is_tool", false):
					player.assign_hotbar_slot(col, _held_item["block_type"])
					_add_to_inv_slot_and_dict(_held_item["block_type"], _held_item["count"])
				_held_item = {}; _held_source = ""; _refresh_all()

func _restore_hotbar_held():
	# Remet l'item hotbar tenu dans son slot d'origine
	if _held_hotbar_idx >= 0:
		if _held_item.get("is_tool", false):
			player.assign_hotbar_tool(_held_hotbar_idx, _held_item["tool_type"])
		else:
			player.assign_hotbar_slot(_held_hotbar_idx, _held_item["block_type"])
	_held_item = {}; _held_source = ""; _held_hotbar_idx = -1

# ============================================================
# INPUT — GRILLE CRAFT
# ============================================================
func _on_grid_input(event: InputEvent, index: int):
	if not (event is InputEventMouseButton and event.pressed): return
	var cell = _grid_contents[index]
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _held_item.is_empty():
			if not cell.is_empty():
				_held_item = cell.duplicate(); _held_item["is_tool"] = false
				_held_source = "grid"
				_grid_contents[index] = {}; _refresh_all()
		else:
			if _held_item.get("is_tool", false):
				# Outils ne vont pas sur la grille craft
				return
			if _held_source == "hotbar":
				# Reference hotbar → restaurer
				_restore_hotbar_held(); _refresh_all(); return
			if cell.is_empty():
				_grid_contents[index] = {"block_type": _held_item["block_type"], "count": _held_item["count"]}
				_held_item = {}; _held_source = ""; _refresh_all()
			elif cell["block_type"] == _held_item["block_type"]:
				cell["count"] += _held_item["count"]
				_held_item = {}; _held_source = ""; _refresh_all()
			else:
				var temp = cell.duplicate()
				_grid_contents[index] = {"block_type": _held_item["block_type"], "count": _held_item["count"]}
				_held_item = temp; _held_item["is_tool"] = false; _held_source = "grid"
				_refresh_all()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if not _held_item.is_empty() and not _held_item.get("is_tool", false) and _held_source != "hotbar":
			if cell.is_empty():
				_grid_contents[index] = {"block_type": _held_item["block_type"], "count": 1}
				_held_item["count"] -= 1
				if _held_item["count"] <= 0: _held_item = {}; _held_source = ""
				_refresh_all()
			elif cell["block_type"] == _held_item["block_type"]:
				cell["count"] += 1; _held_item["count"] -= 1
				if _held_item["count"] <= 0: _held_item = {}; _held_source = ""
				_refresh_all()
		elif _held_item.is_empty():
			if not cell.is_empty():
				var take = ceili(cell["count"] / 2.0)
				_held_item = {"is_tool": false, "block_type": cell["block_type"], "count": take}
				_held_source = "grid"
				cell["count"] -= take
				if cell["count"] <= 0: _grid_contents[index] = {}
				_refresh_all()

func _on_output_input(event: InputEvent):
	if not (event is InputEventMouseButton and event.pressed): return
	if event.button_index != MOUSE_BUTTON_LEFT or _matched_recipe.is_empty() or not player: return
	_consume_grid_for_recipe(_matched_recipe)
	_add_to_inv_slot_and_dict(_matched_recipe["output_type"], _matched_recipe["output_count"])
	var audio = get_tree().get_first_node_in_group("audio_manager")
	if audio and audio.has_method("play_craft_success"): audio.play_craft_success()
	_refresh_all()

func _on_bg_input(event: InputEvent):
	if not (event is InputEventMouseButton and event.pressed): return
	if event.button_index != MOUSE_BUTTON_LEFT or _held_item.is_empty(): return
	if _held_source == "hotbar":
		# Lacher sur le fond = supprimer le pointeur hotbar (l'item reste dans l'inventaire)
		_held_item = {}; _held_source = ""; _held_hotbar_idx = -1; _refresh_all()
	else:
		# Retourner item reel en inventaire
		if _held_item.get("is_tool", false):
			_dict_add_held()
		else:
			_add_to_inv_slot_and_dict(_held_item["block_type"], _held_item["count"])
		_held_item = {}; _held_source = ""; _refresh_all()

func _on_prev_page():
	if _inv_page > 0: _inv_page -= 1; _refresh_inv_slots(); _update_pagination()
func _on_next_page():
	var total = maxi(1, ceili(float(_inv_slots_data.size()) / INV_SLOTS_PER_PAGE))
	if _inv_page < total - 1: _inv_page += 1; _refresh_inv_slots(); _update_pagination()

# ============================================================
# RECIPE
# ============================================================
func _check_recipe():
	var grid_totals: Dictionary = {}
	for cell in _grid_contents:
		if not cell.is_empty():
			var bt = cell["block_type"]; grid_totals[bt] = grid_totals.get(bt, 0) + cell["count"]
	if grid_totals.is_empty(): _matched_recipe = {}; return
	var best: Dictionary = {}; var best_score: int = 0
	for recipe in _available_recipes:
		var inputs = recipe.get("inputs", []); var matches = true; var score = 0
		for inp in inputs:
			if grid_totals.get(inp[0], 0) < inp[1]: matches = false; break
			score += inp[1]
		if matches and score > best_score: best = recipe; best_score = score
	_matched_recipe = best

func _consume_grid_for_recipe(recipe: Dictionary):
	var required: Dictionary = {}
	for inp in recipe["inputs"]: required[inp[0]] = required.get(inp[0], 0) + inp[1]
	for bt in required:
		var remaining = required[bt]
		for i in range(9):
			if remaining <= 0: break
			if _grid_contents[i].is_empty() or _grid_contents[i]["block_type"] != bt: continue
			var take = mini(remaining, _grid_contents[i]["count"])
			_grid_contents[i]["count"] -= take; remaining -= take
			if _grid_contents[i]["count"] <= 0: _grid_contents[i] = {}

func _return_items_to_inventory():
	if not player: return
	if not _held_item.is_empty():
		if _held_source == "hotbar":
			_restore_hotbar_held()
		elif not _held_item.get("is_tool", false):
			_add_to_inv_slot_and_dict(_held_item["block_type"], _held_item["count"])
		_held_item = {}; _held_source = ""
	for i in range(9):
		if not _grid_contents[i].is_empty():
			_add_to_inv_slot_and_dict(_grid_contents[i]["block_type"], _grid_contents[i]["count"])
			_grid_contents[i] = {}

# ============================================================
# HOVER
# ============================================================
func _set_hover_name(text: String):
	if _hover_name_label:
		_hover_name_label.text = text; _hover_name_label.visible = not text.is_empty()

func _on_inv_hover(index: int):
	var slot_idx = _inv_page * INV_SLOTS_PER_PAGE + index
	if slot_idx < _inv_slots_data.size() and not _inv_slots_data[slot_idx].is_empty():
		var item = _inv_slots_data[slot_idx]
		if item.get("is_tool", false):
			_set_hover_name(ToolRegistry.get_tool_name(item["tool_type"]))
		else:
			_set_hover_name(BlockRegistry.get_block_name(item["block_type"]))
	else: _set_hover_name("")

func _on_hotbar_hover(col: int):
	if not player: return
	var tool_type = player.hotbar_tool_slots[col] if col < player.hotbar_tool_slots.size() else ToolRegistry.ToolType.NONE
	if tool_type != ToolRegistry.ToolType.NONE:
		_set_hover_name(ToolRegistry.get_tool_name(tool_type))
	elif not player.is_hotbar_slot_empty(col):
		var bt = player.hotbar_slots[col]
		_set_hover_name(BlockRegistry.get_block_name(bt))
	else: _set_hover_name("")

func _on_grid_hover(index: int):
	if not _grid_contents[index].is_empty():
		var cell = _grid_contents[index]
		_set_hover_name(BlockRegistry.get_block_name(cell["block_type"]))
	else: _set_hover_name("")

func _on_output_hover():
	if not _matched_recipe.is_empty():
		_set_hover_name(BlockRegistry.get_block_name(_matched_recipe["output_type"]))
	else: _set_hover_name("")

func _on_hover_exit():
	_set_hover_name("")

# ============================================================
# PROCESS
# ============================================================
func _process(_delta):
	if not is_open: return
	var mpos = get_viewport().get_mouse_position()
	if _cursor_tex and _cursor_tex.visible:
		var sz = 28 * GUI_SCALE
		_cursor_tex.offset_left = mpos.x - sz / 2; _cursor_tex.offset_top = mpos.y - sz / 2
		_cursor_tex.offset_right = mpos.x + sz / 2; _cursor_tex.offset_bottom = mpos.y + sz / 2
		if _cursor_count and _cursor_count.visible:
			_cursor_count.offset_left = mpos.x + sz / 2 - 24; _cursor_count.offset_top = mpos.y + sz / 2 - 16
			_cursor_count.offset_right = mpos.x + sz / 2 + 12; _cursor_count.offset_bottom = mpos.y + sz / 2 + 4

# ============================================================
# ICON LOADING
# ============================================================
func _load_block_icon(block_type) -> ImageTexture:
	var cache_key = "block_" + str(block_type)
	if _icon_cache.has(cache_key): return _icon_cache[cache_key]
	var tex_name = BlockRegistry.get_face_texture(block_type, "top")
	if tex_name == "dirt" and block_type != BlockRegistry.BlockType.DIRT:
		tex_name = BlockRegistry.get_face_texture(block_type, "all")
	var abs_path = GC.resolve_block_texture(tex_name)
	if abs_path.is_empty(): _icon_cache[cache_key] = null; return null
	var img = Image.new()
	if img.load(abs_path) != OK: _icon_cache[cache_key] = null; return null
	img.convert(Image.FORMAT_RGBA8)
	var tint = BlockRegistry.get_block_tint(block_type, "top")
	if tint != Color(1, 1, 1, 1):
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c = img.get_pixel(x, y)
				img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	var tex = ImageTexture.create_from_image(img)
	_icon_cache[cache_key] = tex; return tex

func _load_tool_icon(tool_type) -> ImageTexture:
	var cache_key = "tool_" + str(tool_type)
	if _icon_cache.has(cache_key): return _icon_cache[cache_key]
	var tex_path = ToolRegistry.get_item_texture_path(tool_type)
	if tex_path.is_empty(): _icon_cache[cache_key] = null; return null
	var abs_path = ProjectSettings.globalize_path(tex_path)
	if not FileAccess.file_exists(abs_path): _icon_cache[cache_key] = null; return null
	var img = Image.new()
	if img.load(abs_path) != OK: _icon_cache[cache_key] = null; return null
	img.convert(Image.FORMAT_RGBA8)
	var tex = ImageTexture.create_from_image(img)
	_icon_cache[cache_key] = tex; return tex
