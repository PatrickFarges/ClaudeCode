# inventory_ui.gd v3.1.0
# Inventaire MC drag & drop + grille craft 2x2
# Rangee du bas = hotbar (reference, pas de stockage)
# Rangees du haut = inventaire reel (27 slots, pagine)
# Meme comportement que crafting_ui.gd

extends CanvasLayer

const GC = preload("res://scripts/game_config.gd")
const GUI_DIR = "res://TexturesPack/Faithful32/assets/minecraft/textures/gui/"
const GUI_SCALE = 2
const MAX_STACK = 64

var player: CharacterBody3D = null
var is_open: bool = false
var _icon_cache: Dictionary = {}

var _inv_slots_data: Array = []
var _inv_page: int = 0
const INV_SLOTS_PER_PAGE = 27

var _grid_contents: Array = []
var _held_item: Dictionary = {}
var _held_source: String = ""
var _held_hotbar_idx: int = -1
var _matched_recipe: Dictionary = {}
var _available_recipes: Array = []

var _background: ColorRect = null
var _inv_texture: TextureRect = null
var _title_label: Label = null
var _grid_ui: Array = []
var _output_btn: Button = null
var _output_tex: TextureRect = null
var _output_count_lbl: Label = null
var _output_name_lbl: Label = null
var _inv_ui: Array = []
var _hotbar_ui: Array = []
var _cursor_tex: TextureRect = null
var _cursor_count: Label = null
var _tooltip_label: Label = null
var _hint_label: Label = null
var _page_label: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null

const TEX_W = 352
const TEX_H = 332
const CRAFT_2X2_X = 196
const CRAFT_2X2_Y = 36
const CRAFT_STEP = 36
const OUT_X = 306
const OUT_Y = 56
const INV_X = 14
const INV_Y = 166
const HOTBAR_Y = 282
const SLOT_SZ = 36
const GRID_SIZE = 4

func _ready():
	layer = 10; visible = false
	_grid_contents.resize(GRID_SIZE)
	for i in range(GRID_SIZE): _grid_contents[i] = {}
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	_available_recipes = []
	for recipe in CraftRegistry.get_all_recipes():
		if recipe.has("_tool_tier") or recipe.get("output_count", 0) <= 0: continue
		if CraftRegistry.is_recipe_available(recipe, 0, false):
			_available_recipes.append(recipe)
	_build_ui()

func _build_ui():
	var disp_w = TEX_W * GUI_SCALE; var disp_h = TEX_H * GUI_SCALE
	var tex_left = -disp_w / 2.0; var tex_top = -disp_h / 2.0
	var icon_sz = 28 * GUI_SCALE; var slot_px = SLOT_SZ * GUI_SCALE; var pad = (slot_px - icon_sz) / 2.0

	_background = ColorRect.new(); _background.color = Color(0, 0, 0, 0.65)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_background.gui_input.connect(_on_bg_input); add_child(_background)

	var inv_img = Image.load_from_file(GUI_DIR + "container/inventory.png")
	var inv_tex: ImageTexture = null
	if inv_img: inv_tex = ImageTexture.create_from_image(inv_img.get_region(Rect2i(0, 0, TEX_W, TEX_H)))
	_inv_texture = TextureRect.new(); _inv_texture.texture = inv_tex
	_inv_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_inv_texture.set_anchors_preset(Control.PRESET_CENTER)
	_inv_texture.offset_left = tex_left; _inv_texture.offset_right = -tex_left
	_inv_texture.offset_top = tex_top; _inv_texture.offset_bottom = -tex_top
	_inv_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_inv_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_inv_texture)

	_title_label = _make_label("Inventaire", 20, Color(1, 1, 0.9), true)
	_title_label.set_anchors_preset(Control.PRESET_CENTER)
	_title_label.offset_left = -150; _title_label.offset_right = 150
	_title_label.offset_top = tex_top - 30; _title_label.offset_bottom = tex_top - 4
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_title_label)

	# Grille craft 2x2
	for r in range(2):
		for c in range(2):
			var idx = r * 2 + c
			var sx = tex_left + (CRAFT_2X2_X + c * CRAFT_STEP) * GUI_SCALE
			var sy = tex_top + (CRAFT_2X2_Y + r * CRAFT_STEP) * GUI_SCALE
			var d = _make_slot(sx, sy, slot_px, icon_sz, pad)
			d["btn"].gui_input.connect(_on_grid_input.bind(idx))
			d["btn"].mouse_entered.connect(_on_grid_hover.bind(idx))
			d["btn"].mouse_exited.connect(_on_hover_exit); _grid_ui.append(d)

	# Output
	var ox = tex_left + OUT_X * GUI_SCALE; var oy = tex_top + OUT_Y * GUI_SCALE
	_output_btn = Button.new(); _output_btn.flat = true
	_output_btn.set_anchors_preset(Control.PRESET_CENTER)
	_output_btn.offset_left = ox; _output_btn.offset_right = ox + slot_px
	_output_btn.offset_top = oy; _output_btn.offset_bottom = oy + slot_px
	_output_btn.gui_input.connect(_on_output_input)
	_output_btn.mouse_entered.connect(_on_output_hover)
	_output_btn.mouse_exited.connect(_on_hover_exit); add_child(_output_btn)
	_output_tex = _make_tex_rect(ox + pad, oy + pad, icon_sz); add_child(_output_tex)
	_output_count_lbl = _make_count_label(ox, oy, slot_px); add_child(_output_count_lbl)
	_output_name_lbl = _make_label("", 12, Color(1, 1, 0.8), true)
	_output_name_lbl.set_anchors_preset(Control.PRESET_CENTER)
	var out_cx = tex_left + (OUT_X + SLOT_SZ / 2) * GUI_SCALE
	_output_name_lbl.offset_left = out_cx - 80; _output_name_lbl.offset_right = out_cx + 80
	_output_name_lbl.offset_top = oy - 18; _output_name_lbl.offset_bottom = oy - 2
	_output_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_output_name_lbl)

	# 27 slots inventaire
	for row in range(3):
		for col in range(9):
			var sx = tex_left + (INV_X + col * SLOT_SZ) * GUI_SCALE
			var sy = tex_top + (INV_Y + row * SLOT_SZ) * GUI_SCALE
			var d = _make_inv_slot(sx, sy, slot_px, icon_sz, pad)
			d["btn"].gui_input.connect(_on_inv_input.bind(_inv_ui.size()))
			d["btn"].mouse_entered.connect(_on_inv_hover.bind(_inv_ui.size()))
			d["btn"].mouse_exited.connect(_on_hover_exit); _inv_ui.append(d)

	# 9 slots hotbar
	for col in range(9):
		var sx = tex_left + (INV_X + col * SLOT_SZ) * GUI_SCALE
		var sy = tex_top + HOTBAR_Y * GUI_SCALE
		var d = _make_inv_slot(sx, sy, slot_px, icon_sz, pad)
		d["btn"].gui_input.connect(_on_hotbar_input.bind(col))
		d["btn"].mouse_entered.connect(_on_hotbar_hover.bind(col))
		d["btn"].mouse_exited.connect(_on_hover_exit); _hotbar_ui.append(d)

	# Pagination
	var nav_y = disp_h / 2 + 10
	var bs = StyleBoxFlat.new(); bs.bg_color = Color(0.2, 0.15, 0.3, 0.85)
	bs.border_color = Color(0.5, 0.3, 0.7, 0.9); bs.set_border_width_all(2); bs.set_corner_radius_all(4)
	_prev_btn = Button.new(); _prev_btn.text = "< Prec."
	_prev_btn.set_anchors_preset(Control.PRESET_CENTER)
	_prev_btn.offset_left = -120; _prev_btn.offset_right = -30
	_prev_btn.offset_top = nav_y; _prev_btn.offset_bottom = nav_y + 30
	_prev_btn.add_theme_stylebox_override("normal", bs)
	_prev_btn.add_theme_color_override("font_color", Color.WHITE)
	_prev_btn.pressed.connect(_on_prev_page); add_child(_prev_btn)
	_page_label = _make_label("1/1", 14, Color(1, 1, 0.9))
	_page_label.set_anchors_preset(Control.PRESET_CENTER)
	_page_label.offset_left = -30; _page_label.offset_right = 30
	_page_label.offset_top = nav_y + 4; _page_label.offset_bottom = nav_y + 30
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_page_label)
	_next_btn = Button.new(); _next_btn.text = "Suiv. >"
	_next_btn.set_anchors_preset(Control.PRESET_CENTER)
	_next_btn.offset_left = 30; _next_btn.offset_right = 120
	_next_btn.offset_top = nav_y; _next_btn.offset_bottom = nav_y + 30
	_next_btn.add_theme_stylebox_override("normal", bs)
	_next_btn.add_theme_color_override("font_color", Color.WHITE)
	_next_btn.pressed.connect(_on_next_page); add_child(_next_btn)

	# Tooltip
	_tooltip_label = Label.new(); _tooltip_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tooltip_label.add_theme_font_size_override("font_size", 14)
	_tooltip_label.add_theme_color_override("font_color", Color.WHITE)
	_tooltip_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 1))
	_tooltip_label.add_theme_constant_override("shadow_offset_x", 2)
	_tooltip_label.add_theme_constant_override("shadow_offset_y", 2)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; _tooltip_label.visible = false
	var ts = StyleBoxFlat.new(); ts.bg_color = Color(0.1, 0.05, 0.15, 0.9)
	ts.border_color = Color(0.4, 0.2, 0.6, 0.8); ts.set_border_width_all(2); ts.set_corner_radius_all(4)
	ts.content_margin_left = 6; ts.content_margin_right = 6
	ts.content_margin_top = 3; ts.content_margin_bottom = 3
	_tooltip_label.add_theme_stylebox_override("normal", ts); add_child(_tooltip_label)

	_hint_label = _make_label("", 13, Color(0.8, 0.8, 0.7, 0.8), true)
	_hint_label.set_anchors_preset(Control.PRESET_CENTER)
	_hint_label.offset_left = -disp_w / 2; _hint_label.offset_right = disp_w / 2
	_hint_label.offset_top = disp_h / 2 + 6; _hint_label.offset_bottom = disp_h / 2 + 24
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_hint_label)

	_cursor_tex = TextureRect.new(); _cursor_tex.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cursor_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cursor_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cursor_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE; _cursor_tex.visible = false; add_child(_cursor_tex)
	_cursor_count = Label.new(); _cursor_count.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cursor_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cursor_count.add_theme_font_size_override("font_size", 14)
	_cursor_count.add_theme_color_override("font_color", Color.WHITE)
	_cursor_count.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
	_cursor_count.add_theme_constant_override("shadow_offset_x", 2)
	_cursor_count.add_theme_constant_override("shadow_offset_y", 2)
	_cursor_count.mouse_filter = Control.MOUSE_FILTER_IGNORE; _cursor_count.visible = false; add_child(_cursor_count)

# ============================================================
# HELPERS
# ============================================================
func _make_label(text, size, color, shadow = false) -> Label:
	var l = Label.new(); l.text = text; l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0.15, 0.15, 0.15, 1))
		l.add_theme_constant_override("shadow_offset_x", 2); l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; return l

func _make_tex_rect(x, y, sz) -> TextureRect:
	var t = TextureRect.new(); t.set_anchors_preset(Control.PRESET_CENTER)
	t.offset_left = x; t.offset_right = x + sz; t.offset_top = y; t.offset_bottom = y + sz
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; t.mouse_filter = Control.MOUSE_FILTER_IGNORE; return t

func _make_count_label(sx, sy, slot_px) -> Label:
	var l = Label.new(); l.set_anchors_preset(Control.PRESET_CENTER)
	l.offset_left = sx + slot_px - 26 * GUI_SCALE; l.offset_right = sx + slot_px - 2
	l.offset_top = sy + slot_px - 14 * GUI_SCALE; l.offset_bottom = sy + slot_px
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
	l.add_theme_constant_override("shadow_offset_x", 2); l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; return l

func _make_slot(sx, sy, slot_px, icon_sz, pad) -> Dictionary:
	var b = Button.new(); b.flat = true; b.set_anchors_preset(Control.PRESET_CENTER)
	b.offset_left = sx; b.offset_right = sx + slot_px; b.offset_top = sy; b.offset_bottom = sy + slot_px
	var hs = StyleBoxFlat.new(); hs.bg_color = Color(1, 1, 1, 0.12); b.add_theme_stylebox_override("hover", hs)
	add_child(b); var t = _make_tex_rect(sx + pad, sy + pad, icon_sz); add_child(t)
	var c = _make_count_label(sx, sy, slot_px); add_child(c)
	return {"btn": b, "tex": t, "count_lbl": c}

func _make_inv_slot(sx, sy, slot_px, icon_sz, pad) -> Dictionary:
	var d = _make_slot(sx, sy, slot_px, icon_sz, pad)
	var bg = ColorRect.new(); bg.set_anchors_preset(Control.PRESET_CENTER)
	bg.offset_left = sx + 1; bg.offset_right = sx + slot_px - 1
	bg.offset_top = sy + 1; bg.offset_bottom = sy + slot_px - 1
	bg.color = Color(0, 0, 0, 0.45); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(bg)
	var l = Label.new(); l.set_anchors_preset(Control.PRESET_CENTER)
	l.offset_left = sx + 2; l.offset_right = sx + slot_px - 2; l.offset_top = sy + 2; l.offset_bottom = sy + slot_px - 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("shadow_offset_x", 1); l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(l)
	d["name_bg"] = bg; d["name_lbl"] = l; return d

# ============================================================
# OPEN / CLOSE
# ============================================================
func open_inventory():
	is_open = true; _inv_page = 0; _held_item = {}; _held_source = ""
	for i in range(GRID_SIZE): _grid_contents[i] = {}
	_matched_recipe = {}
	_build_inv_slots(); visible = true; _refresh_all()

func close_inventory():
	_return_items_to_inventory(); is_open = false; visible = false

# ============================================================
# SLOT DATA
# ============================================================
func _build_inv_slots():
	_inv_slots_data.clear()
	if not player: return
	var inv = player.get_all_inventory(); var st: Array = []
	for bt in inv:
		if inv[bt] > 0: st.append(bt)
	st.sort_custom(func(a, b): return int(a) < int(b))
	for bt in st: _inv_slots_data.append({"block_type": bt, "count": inv[bt]})
	# Outils
	var tools = player.get_all_tools()
	for tt in tools:
		if tools[tt] > 0:
			_inv_slots_data.append({"is_tool": true, "tool_type": tt, "count": tools[tt]})
	var ms = maxi(INV_SLOTS_PER_PAGE, _inv_slots_data.size() + INV_SLOTS_PER_PAGE)
	while _inv_slots_data.size() < ms: _inv_slots_data.append({})

func _add_to_inv_slot_and_dict(bt, count):
	player._add_to_inventory(bt, count)
	for i in range(_inv_slots_data.size()):
		if not _inv_slots_data[i].is_empty() and _inv_slots_data[i]["block_type"] == bt:
			_inv_slots_data[i]["count"] += count; return
	for i in range(_inv_slots_data.size()):
		if _inv_slots_data[i].is_empty():
			_inv_slots_data[i] = {"block_type": bt, "count": count}; return
	_inv_slots_data.append({"block_type": bt, "count": count})

func sort_inventory(): _build_inv_slots(); _inv_page = 0; _refresh_all()

# ============================================================
# REFRESH
# ============================================================
func _refresh_all():
	_refresh_inv_slots(); _refresh_hotbar_slots(); _refresh_grid_visuals()
	_check_recipe(); _update_output(); _update_cursor(); _update_pagination()

func _refresh_inv_slots():
	var offset = _inv_page * INV_SLOTS_PER_PAGE
	for i in range(_inv_ui.size()):
		var ui = _inv_ui[i]; var idx = offset + i
		if idx < _inv_slots_data.size() and not _inv_slots_data[idx].is_empty():
			var item = _inv_slots_data[idx]
			if item.get("is_tool", false):
				ui["tex"].texture = _load_tool_icon(item["tool_type"])
				ui["name_lbl"].text = ToolRegistry.get_tool_name(item["tool_type"])
			else:
				ui["tex"].texture = _load_block_icon(item["block_type"])
				ui["name_lbl"].text = BlockRegistry.get_block_name(item["block_type"])
			ui["tex"].modulate = Color.WHITE
			ui["count_lbl"].text = str(item["count"]) if item["count"] > 1 else ""
			ui["name_bg"].visible = true; ui["name_lbl"].visible = true
		else:
			ui["tex"].texture = null; ui["count_lbl"].text = ""
			ui["name_lbl"].text = ""; ui["name_bg"].visible = false; ui["name_lbl"].visible = false
		ui["btn"].visible = true

func _refresh_hotbar_slots():
	if not player: return
	for i in range(9):
		var ui = _hotbar_ui[i]
		var tt = player.hotbar_tool_slots[i] if i < player.hotbar_tool_slots.size() else ToolRegistry.ToolType.NONE
		if tt != ToolRegistry.ToolType.NONE:
			ui["tex"].texture = _load_tool_icon(tt); ui["tex"].modulate = Color.WHITE
			ui["count_lbl"].text = ""; ui["name_lbl"].text = ToolRegistry.get_tool_name(tt)
			ui["name_bg"].visible = true; ui["name_lbl"].visible = true
		else:
			var bt = player.hotbar_slots[i] if i < player.hotbar_slots.size() else 0
			var count = player.get_inventory_count(bt)
			if count > 0:
				ui["tex"].texture = _load_block_icon(bt); ui["tex"].modulate = Color.WHITE
				ui["count_lbl"].text = str(count) if count > 1 else ""
				ui["name_lbl"].text = BlockRegistry.get_block_name(bt)
				ui["name_bg"].visible = true; ui["name_lbl"].visible = true
			else:
				ui["tex"].texture = null; ui["count_lbl"].text = ""
				ui["name_lbl"].text = ""; ui["name_bg"].visible = false; ui["name_lbl"].visible = false
		ui["btn"].visible = true

func _refresh_grid_visuals():
	for i in range(GRID_SIZE):
		var cell = _grid_contents[i]; var ui = _grid_ui[i]
		if not cell.is_empty():
			ui["tex"].texture = _load_block_icon(cell["block_type"]); ui["tex"].modulate = Color.WHITE
			ui["count_lbl"].text = str(cell["count"]) if cell["count"] > 1 else ""
		else: ui["tex"].texture = null; ui["count_lbl"].text = ""

func _update_output():
	if not _matched_recipe.is_empty():
		_output_tex.texture = _load_block_icon(_matched_recipe["output_type"]); _output_tex.modulate = Color.WHITE
		var oc = _matched_recipe.get("output_count", 1)
		_output_count_lbl.text = "x%d" % oc if oc > 1 else ""
		_output_name_lbl.text = BlockRegistry.get_block_name(_matched_recipe["output_type"])
		_hint_label.text = _matched_recipe.get("name", "")
		_hint_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 0.9))
	else:
		_output_tex.texture = null; _output_count_lbl.text = ""; _output_name_lbl.text = ""
		var hi = false
		for cell in _grid_contents:
			if not cell.is_empty(): hi = true; break
		if hi:
			_hint_label.text = "Aucune recette ne correspond"
			_hint_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5, 0.9))
		else:
			_hint_label.text = ""
			_hint_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7, 0.8))

func _update_cursor():
	if not _held_item.is_empty():
		if _held_item.get("is_tool", false):
			_cursor_tex.texture = _load_tool_icon(_held_item["tool_type"])
		else:
			_cursor_tex.texture = _load_block_icon(_held_item["block_type"])
		_cursor_tex.visible = true
		var c = _held_item.get("count", 0)
		_cursor_count.text = str(c) if c > 1 else ""; _cursor_count.visible = c > 1
	else: _cursor_tex.visible = false; _cursor_count.visible = false

func _update_pagination():
	var total = maxi(1, ceili(float(_inv_slots_data.size()) / INV_SLOTS_PER_PAGE))
	if _page_label: _page_label.text = "%d/%d" % [_inv_page + 1, total]
	if _prev_btn: _prev_btn.visible = total > 1; _prev_btn.disabled = _inv_page <= 0
	if _next_btn: _next_btn.visible = total > 1; _next_btn.disabled = _inv_page >= total - 1

# ============================================================
# INPUT — INVENTORY
# ============================================================
func _on_inv_input(event: InputEvent, index: int):
	if not (event is InputEventMouseButton and event.pressed): return
	var slot_idx = _inv_page * INV_SLOTS_PER_PAGE + index
	while slot_idx >= _inv_slots_data.size(): _inv_slots_data.append({})
	var slot = _inv_slots_data[slot_idx]
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _held_item.is_empty():
			if not slot.is_empty():
				_held_item = slot.duplicate(); _held_item["is_tool"] = false; _held_source = "inv"
				player._remove_from_inventory(slot["block_type"], slot["count"])
				_inv_slots_data[slot_idx] = {}; _refresh_all()
		else:
			if _held_source == "hotbar": _restore_hotbar_held(); _refresh_all(); return
			if slot.is_empty():
				_inv_slots_data[slot_idx] = {"block_type": _held_item["block_type"], "count": _held_item["count"]}
				player._add_to_inventory(_held_item["block_type"], _held_item["count"])
				_held_item = {}; _held_source = ""; _refresh_all()
			elif slot["block_type"] == _held_item["block_type"]:
				slot["count"] += _held_item["count"]
				player._add_to_inventory(_held_item["block_type"], _held_item["count"])
				_held_item = {}; _held_source = ""; _refresh_all()
			else:
				var temp = slot.duplicate()
				_inv_slots_data[slot_idx] = {"block_type": _held_item["block_type"], "count": _held_item["count"]}
				player._add_to_inventory(_held_item["block_type"], _held_item["count"])
				player._remove_from_inventory(temp["block_type"], temp["count"])
				_held_item = temp; _held_item["is_tool"] = false; _held_source = "inv"; _refresh_all()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if not _held_item.is_empty() and not _held_item.get("is_tool", false) and _held_source != "hotbar":
			if slot.is_empty():
				_inv_slots_data[slot_idx] = {"block_type": _held_item["block_type"], "count": 1}
				player._add_to_inventory(_held_item["block_type"], 1)
				_held_item["count"] -= 1
				if _held_item["count"] <= 0: _held_item = {}; _held_source = ""
				_refresh_all()
			elif slot["block_type"] == _held_item["block_type"]:
				slot["count"] += 1; player._add_to_inventory(_held_item["block_type"], 1)
				_held_item["count"] -= 1
				if _held_item["count"] <= 0: _held_item = {}; _held_source = ""
				_refresh_all()
		elif _held_item.is_empty():
			if not slot.is_empty():
				var take = ceili(slot["count"] / 2.0)
				_held_item = {"is_tool": false, "block_type": slot["block_type"], "count": take}
				_held_source = "inv"; player._remove_from_inventory(slot["block_type"], take)
				slot["count"] -= take
				if slot["count"] <= 0: _inv_slots_data[slot_idx] = {}
				_refresh_all()

# ============================================================
# INPUT — HOTBAR
# ============================================================
func _on_hotbar_input(event: InputEvent, col: int):
	if not (event is InputEventMouseButton and event.pressed): return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _held_item.is_empty():
			if not player.is_hotbar_slot_empty(col):
				var tt = player.hotbar_tool_slots[col] if col < player.hotbar_tool_slots.size() else ToolRegistry.ToolType.NONE
				if tt != ToolRegistry.ToolType.NONE:
					_held_item = {"is_tool": true, "tool_type": tt, "count": 0}
				else:
					_held_item = {"is_tool": false, "block_type": player.hotbar_slots[col], "count": 0}
				_held_source = "hotbar"; _held_hotbar_idx = col
				player._clear_hotbar_slot(col); _refresh_all()
		else:
			if _held_source == "hotbar":
				if _held_item.get("is_tool", false):
					player.assign_hotbar_tool(col, _held_item["tool_type"])
				else:
					player.assign_hotbar_slot(col, _held_item["block_type"])
				_held_item = {}; _held_source = ""; _refresh_all()
			elif _held_source == "inv" or _held_source == "grid":
				if not _held_item.get("is_tool", false):
					player.assign_hotbar_slot(col, _held_item["block_type"])
					_add_to_inv_slot_and_dict(_held_item["block_type"], _held_item["count"])
				_held_item = {}; _held_source = ""; _refresh_all()

func _restore_hotbar_held():
	if _held_hotbar_idx >= 0:
		if _held_item.get("is_tool", false):
			player.assign_hotbar_tool(_held_hotbar_idx, _held_item["tool_type"])
		else:
			player.assign_hotbar_slot(_held_hotbar_idx, _held_item["block_type"])
	_held_item = {}; _held_source = ""; _held_hotbar_idx = -1

# ============================================================
# INPUT — GRID 2x2
# ============================================================
func _on_grid_input(event: InputEvent, index: int):
	if not (event is InputEventMouseButton and event.pressed): return
	var cell = _grid_contents[index]
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _held_item.is_empty():
			if not cell.is_empty():
				_held_item = cell.duplicate(); _held_item["is_tool"] = false; _held_source = "grid"
				_grid_contents[index] = {}; _refresh_all()
		else:
			if _held_item.get("is_tool", false) or _held_source == "hotbar":
				if _held_source == "hotbar": _restore_hotbar_held()
				_refresh_all(); return
			if cell.is_empty():
				_grid_contents[index] = {"block_type": _held_item["block_type"], "count": _held_item["count"]}
				_held_item = {}; _held_source = ""; _refresh_all()
			elif cell["block_type"] == _held_item["block_type"]:
				cell["count"] += _held_item["count"]; _held_item = {}; _held_source = ""; _refresh_all()
			else:
				var temp = cell.duplicate()
				_grid_contents[index] = {"block_type": _held_item["block_type"], "count": _held_item["count"]}
				_held_item = temp; _held_item["is_tool"] = false; _held_source = "grid"; _refresh_all()
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
		elif _held_item.is_empty() and not cell.is_empty():
			var take = ceili(cell["count"] / 2.0)
			_held_item = {"is_tool": false, "block_type": cell["block_type"], "count": take}
			_held_source = "grid"; cell["count"] -= take
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
		_held_item = {}; _held_source = ""; _refresh_all()
	else:
		if not _held_item.get("is_tool", false):
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
	var gt: Dictionary = {}
	for cell in _grid_contents:
		if not cell.is_empty(): var bt = cell["block_type"]; gt[bt] = gt.get(bt, 0) + cell["count"]
	if gt.is_empty(): _matched_recipe = {}; return
	var best: Dictionary = {}; var bs: int = 0
	for recipe in _available_recipes:
		var inputs = recipe.get("inputs", []); var ok = true; var sc = 0
		for inp in inputs:
			if gt.get(inp[0], 0) < inp[1]: ok = false; break
			sc += inp[1]
		if ok and sc > bs: best = recipe; bs = sc
	_matched_recipe = best

func _consume_grid_for_recipe(recipe):
	var req: Dictionary = {}
	for inp in recipe["inputs"]: req[inp[0]] = req.get(inp[0], 0) + inp[1]
	for bt in req:
		var rem = req[bt]
		for i in range(GRID_SIZE):
			if rem <= 0: break
			if _grid_contents[i].is_empty() or _grid_contents[i]["block_type"] != bt: continue
			var take = mini(rem, _grid_contents[i]["count"])
			_grid_contents[i]["count"] -= take; rem -= take
			if _grid_contents[i]["count"] <= 0: _grid_contents[i] = {}

func _return_items_to_inventory():
	if not player: return
	if not _held_item.is_empty():
		if _held_source == "hotbar": _restore_hotbar_held()
		elif not _held_item.get("is_tool", false):
			_add_to_inv_slot_and_dict(_held_item["block_type"], _held_item["count"])
		_held_item = {}; _held_source = ""
	for i in range(GRID_SIZE):
		if not _grid_contents[i].is_empty():
			_add_to_inv_slot_and_dict(_grid_contents[i]["block_type"], _grid_contents[i]["count"])
			_grid_contents[i] = {}

# ============================================================
# HOVER
# ============================================================
func _on_inv_hover(index):
	var si = _inv_page * INV_SLOTS_PER_PAGE + index
	if si < _inv_slots_data.size() and not _inv_slots_data[si].is_empty():
		var item = _inv_slots_data[si]
		_tooltip_label.text = "%s (x%d)" % [BlockRegistry.get_block_name(item["block_type"]), item["count"]]
		_tooltip_label.visible = true

func _on_hotbar_hover(col):
	if not player: return
	var tt = player.hotbar_tool_slots[col] if col < player.hotbar_tool_slots.size() else ToolRegistry.ToolType.NONE
	if tt != ToolRegistry.ToolType.NONE:
		_tooltip_label.text = ToolRegistry.get_tool_name(tt); _tooltip_label.visible = true
	elif not player.is_hotbar_slot_empty(col):
		var bt = player.hotbar_slots[col]; var c = player.get_inventory_count(bt)
		_tooltip_label.text = "%s (x%d)" % [BlockRegistry.get_block_name(bt), c]; _tooltip_label.visible = true

func _on_grid_hover(index):
	if index < GRID_SIZE and not _grid_contents[index].is_empty():
		var cell = _grid_contents[index]
		_tooltip_label.text = "%s (x%d)" % [BlockRegistry.get_block_name(cell["block_type"]), cell["count"]]
		_tooltip_label.visible = true

func _on_output_hover():
	if not _matched_recipe.is_empty():
		_tooltip_label.text = "Cliquer pour crafter : %s" % BlockRegistry.get_block_name(_matched_recipe["output_type"])
		_tooltip_label.visible = true

func _on_hover_exit():
	if _tooltip_label: _tooltip_label.visible = false

# ============================================================
# PROCESS
# ============================================================
func _process(_delta):
	if not is_open: return
	var m = get_viewport().get_mouse_position()
	if _cursor_tex and _cursor_tex.visible:
		var sz = 28 * GUI_SCALE
		_cursor_tex.offset_left = m.x - sz / 2; _cursor_tex.offset_top = m.y - sz / 2
		_cursor_tex.offset_right = m.x + sz / 2; _cursor_tex.offset_bottom = m.y + sz / 2
		if _cursor_count and _cursor_count.visible:
			_cursor_count.offset_left = m.x + sz / 2 - 24; _cursor_count.offset_top = m.y + sz / 2 - 16
			_cursor_count.offset_right = m.x + sz / 2 + 12; _cursor_count.offset_bottom = m.y + sz / 2 + 4
	if _tooltip_label and _tooltip_label.visible:
		_tooltip_label.offset_left = m.x + 16; _tooltip_label.offset_top = m.y - 10
		_tooltip_label.offset_right = m.x + 250; _tooltip_label.offset_bottom = m.y + 16

# ============================================================
# ICON LOADING
# ============================================================
func _load_block_icon(block_type) -> ImageTexture:
	var k = "block_" + str(block_type)
	if _icon_cache.has(k): return _icon_cache[k]
	var tn = BlockRegistry.get_face_texture(block_type, "top")
	if tn == "dirt" and block_type != BlockRegistry.BlockType.DIRT:
		tn = BlockRegistry.get_face_texture(block_type, "all")
	var ap = GC.resolve_block_texture(tn)
	if ap.is_empty(): _icon_cache[k] = null; return null
	var img = Image.new()
	if img.load(ap) != OK: _icon_cache[k] = null; return null
	img.convert(Image.FORMAT_RGBA8)
	var tint = BlockRegistry.get_block_tint(block_type, "top")
	if tint != Color(1, 1, 1, 1):
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c = img.get_pixel(x, y)
				img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	var tex = ImageTexture.create_from_image(img); _icon_cache[k] = tex; return tex

func _load_tool_icon(tool_type) -> ImageTexture:
	var k = "tool_" + str(tool_type)
	if _icon_cache.has(k): return _icon_cache[k]
	var tp = ToolRegistry.get_item_texture_path(tool_type)
	if tp.is_empty(): _icon_cache[k] = null; return null
	var ap = ProjectSettings.globalize_path(tp)
	if not FileAccess.file_exists(ap): _icon_cache[k] = null; return null
	var img = Image.new()
	if img.load(ap) != OK: _icon_cache[k] = null; return null
	img.convert(Image.FORMAT_RGBA8)
	var tex = ImageTexture.create_from_image(img); _icon_cache[k] = tex; return tex
