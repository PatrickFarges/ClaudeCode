# inventory_ui.gd v3.0.0
# Inventaire Minecraft avec drag & drop + grille craft 2x2
# Meme comportement que crafting_ui.gd mais avec grille 2x2 (recettes main tier 0)
# Ouvert avec I — placement libre, touche T pour trier

extends CanvasLayer

const GC = preload("res://scripts/game_config.gd")
const GUI_DIR = "res://TexturesPack/Faithful32/assets/minecraft/textures/gui/"
const GUI_SCALE = 2
const MAX_STACK = 64

var player: CharacterBody3D = null
var is_open: bool = false
var _icon_cache: Dictionary = {}

# --- Slots inventaire (positions fixes) ---
var _inv_slots_data: Array = []
var _inv_page: int = 0

# --- Drag & drop ---
var _grid_contents: Array = []   # 4 dicts (grille 2x2)
var _held_item: Dictionary = {}
var _matched_recipe: Dictionary = {}
var _available_recipes: Array = []

# --- UI nodes ---
var _background: ColorRect = null
var _inv_texture: TextureRect = null
var _title_label: Label = null
var _grid_ui: Array = []         # 4 slots grille 2x2
var _output_btn: Button = null
var _output_tex: TextureRect = null
var _output_count_lbl: Label = null
var _output_name_lbl: Label = null
var _inv_ui: Array = []          # 36 slots inventaire
var _cursor_tex: TextureRect = null
var _cursor_count: Label = null
var _tooltip_label: Label = null
var _hint_label: Label = null
var _page_label: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null

# Layout (Faithful32 inventory.png, 352x332, scale 2x)
const TEX_W = 352
const TEX_H = 332
const CRAFT_2X2_X = 196   # Grille craft 2x2 (haut droite dans inventory.png)
const CRAFT_2X2_Y = 36
const CRAFT_STEP = 36
const OUT_X = 308          # Slot output
const OUT_Y = 48
const INV_X = 14           # Slots inventaire
const INV_Y = 166
const HOTBAR_Y = 282
const SLOT_SZ = 36
const SLOTS_PER_PAGE = 36
const GRID_SIZE = 4        # 2x2

func _ready():
	layer = 10
	visible = false
	_grid_contents.resize(GRID_SIZE)
	for i in range(GRID_SIZE):
		_grid_contents[i] = {}
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	# Filtrer recettes main (tier 0) pour la grille 2x2
	_available_recipes = []
	for recipe in CraftRegistry.get_all_recipes():
		if recipe.has("_tool_tier"):
			continue
		if recipe.get("output_count", 0) <= 0:
			continue
		if CraftRegistry.is_recipe_available(recipe, 0, false):
			_available_recipes.append(recipe)
	_build_ui()

func _build_ui():
	var disp_w = TEX_W * GUI_SCALE
	var disp_h = TEX_H * GUI_SCALE
	var tex_left = -disp_w / 2.0
	var tex_top = -disp_h / 2.0
	var icon_sz = 28 * GUI_SCALE
	var slot_px = SLOT_SZ * GUI_SCALE
	var pad = (slot_px - icon_sz) / 2.0

	# Fond sombre
	_background = ColorRect.new()
	_background.color = Color(0, 0, 0, 0.65)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_background.gui_input.connect(_on_bg_input)
	add_child(_background)

	# Texture inventaire MC
	var inv_img = Image.load_from_file(GUI_DIR + "container/inventory.png")
	var inv_tex: ImageTexture = null
	if inv_img:
		var cropped = inv_img.get_region(Rect2i(0, 0, TEX_W, TEX_H))
		inv_tex = ImageTexture.create_from_image(cropped)
	_inv_texture = TextureRect.new()
	_inv_texture.texture = inv_tex
	_inv_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_inv_texture.set_anchors_preset(Control.PRESET_CENTER)
	_inv_texture.offset_left = tex_left; _inv_texture.offset_right = -tex_left
	_inv_texture.offset_top = tex_top; _inv_texture.offset_bottom = -tex_top
	_inv_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_inv_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inv_texture)

	# Titre
	_title_label = _make_label("Inventaire", 20, Color(1, 1, 0.9), true)
	_title_label.set_anchors_preset(Control.PRESET_CENTER)
	_title_label.offset_left = -150; _title_label.offset_right = 150
	_title_label.offset_top = tex_top - 30; _title_label.offset_bottom = tex_top - 4
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title_label)

	# --- Grille craft 2x2 ---
	for r in range(2):
		for c in range(2):
			var idx = r * 2 + c
			var sx = tex_left + (CRAFT_2X2_X + c * CRAFT_STEP) * GUI_SCALE
			var sy = tex_top + (CRAFT_2X2_Y + r * CRAFT_STEP) * GUI_SCALE
			var d = _make_slot(sx, sy, slot_px, icon_sz, pad)
			d["btn"].gui_input.connect(_on_grid_input.bind(idx))
			d["btn"].mouse_entered.connect(_on_grid_hover.bind(idx))
			d["btn"].mouse_exited.connect(_on_hover_exit)
			_grid_ui.append(d)

	# --- Output slot ---
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
	_output_name_lbl = _make_label("", 12, Color(1, 1, 0.8), true)
	_output_name_lbl.set_anchors_preset(Control.PRESET_CENTER)
	var out_cx = tex_left + (OUT_X + SLOT_SZ / 2) * GUI_SCALE
	_output_name_lbl.offset_left = out_cx - 80; _output_name_lbl.offset_right = out_cx + 80
	_output_name_lbl.offset_top = oy - 18; _output_name_lbl.offset_bottom = oy - 2
	_output_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_output_name_lbl)

	# --- Slots inventaire (3x9 + 1x9) ---
	var positions: Array = []
	for row in range(3):
		for col in range(9):
			positions.append(Vector2(
				tex_left + (INV_X + col * SLOT_SZ) * GUI_SCALE,
				tex_top + (INV_Y + row * SLOT_SZ) * GUI_SCALE))
	for col in range(9):
		positions.append(Vector2(
			tex_left + (INV_X + col * SLOT_SZ) * GUI_SCALE,
			tex_top + HOTBAR_Y * GUI_SCALE))
	for i in range(SLOTS_PER_PAGE):
		var pos = positions[i]
		var d = _make_inv_slot(pos.x, pos.y, slot_px, icon_sz, pad)
		d["btn"].gui_input.connect(_on_inv_input.bind(i))
		d["btn"].mouse_entered.connect(_on_inv_hover.bind(i))
		d["btn"].mouse_exited.connect(_on_hover_exit)
		_inv_ui.append(d)

	# --- Pagination ---
	var nav_y = disp_h / 2 + 10
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.15, 0.3, 0.85)
	btn_style.border_color = Color(0.5, 0.3, 0.7, 0.9)
	btn_style.set_border_width_all(2); btn_style.set_corner_radius_all(4)
	_prev_btn = Button.new()
	_prev_btn.text = "< Prec."
	_prev_btn.set_anchors_preset(Control.PRESET_CENTER)
	_prev_btn.offset_left = -120; _prev_btn.offset_right = -30
	_prev_btn.offset_top = nav_y; _prev_btn.offset_bottom = nav_y + 30
	_prev_btn.add_theme_stylebox_override("normal", btn_style)
	_prev_btn.add_theme_color_override("font_color", Color.WHITE)
	_prev_btn.pressed.connect(_on_prev_page)
	add_child(_prev_btn)
	_page_label = _make_label("1/1", 14, Color(1, 1, 0.9))
	_page_label.set_anchors_preset(Control.PRESET_CENTER)
	_page_label.offset_left = -30; _page_label.offset_right = 30
	_page_label.offset_top = nav_y + 4; _page_label.offset_bottom = nav_y + 30
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_page_label)
	_next_btn = Button.new()
	_next_btn.text = "Suiv. >"
	_next_btn.set_anchors_preset(Control.PRESET_CENTER)
	_next_btn.offset_left = 30; _next_btn.offset_right = 120
	_next_btn.offset_top = nav_y; _next_btn.offset_bottom = nav_y + 30
	_next_btn.add_theme_stylebox_override("normal", btn_style)
	_next_btn.add_theme_color_override("font_color", Color.WHITE)
	_next_btn.pressed.connect(_on_next_page)
	add_child(_next_btn)

	# --- Tooltip ---
	_tooltip_label = Label.new()
	_tooltip_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tooltip_label.add_theme_font_size_override("font_size", 14)
	_tooltip_label.add_theme_color_override("font_color", Color.WHITE)
	_tooltip_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 1))
	_tooltip_label.add_theme_constant_override("shadow_offset_x", 2)
	_tooltip_label.add_theme_constant_override("shadow_offset_y", 2)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.visible = false
	var tip_style = StyleBoxFlat.new()
	tip_style.bg_color = Color(0.1, 0.05, 0.15, 0.9)
	tip_style.border_color = Color(0.4, 0.2, 0.6, 0.8)
	tip_style.set_border_width_all(2); tip_style.set_corner_radius_all(4)
	tip_style.content_margin_left = 6; tip_style.content_margin_right = 6
	tip_style.content_margin_top = 3; tip_style.content_margin_bottom = 3
	_tooltip_label.add_theme_stylebox_override("normal", tip_style)
	add_child(_tooltip_label)

	# --- Hint ---
	_hint_label = _make_label("", 13, Color(0.8, 0.8, 0.7, 0.8), true)
	_hint_label.set_anchors_preset(Control.PRESET_CENTER)
	_hint_label.offset_left = -disp_w / 2; _hint_label.offset_right = disp_w / 2
	_hint_label.offset_top = disp_h / 2 + 6; _hint_label.offset_bottom = disp_h / 2 + 24
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)

	# --- Curseur ---
	_cursor_tex = TextureRect.new()
	_cursor_tex.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cursor_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cursor_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cursor_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_tex.visible = false
	add_child(_cursor_tex)
	_cursor_count = Label.new()
	_cursor_count.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cursor_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cursor_count.add_theme_font_size_override("font_size", 14)
	_cursor_count.add_theme_color_override("font_color", Color.WHITE)
	_cursor_count.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
	_cursor_count.add_theme_constant_override("shadow_offset_x", 2)
	_cursor_count.add_theme_constant_override("shadow_offset_y", 2)
	_cursor_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_count.visible = false
	add_child(_cursor_count)

# ============================================================
# HELPERS UI
# ============================================================
func _make_label(text: String, size: int, color: Color, shadow: bool = false) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if shadow:
		lbl.add_theme_color_override("font_shadow_color", Color(0.15, 0.15, 0.15, 1))
		lbl.add_theme_constant_override("shadow_offset_x", 2)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _make_tex_rect(x: float, y: float, sz: float) -> TextureRect:
	var tr = TextureRect.new()
	tr.set_anchors_preset(Control.PRESET_CENTER)
	tr.offset_left = x; tr.offset_right = x + sz
	tr.offset_top = y; tr.offset_bottom = y + sz
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _make_count_label(sx: float, sy: float, slot_px: float) -> Label:
	var lbl = Label.new()
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left = sx + slot_px - 26 * GUI_SCALE; lbl.offset_right = sx + slot_px - 2
	lbl.offset_top = sy + slot_px - 14 * GUI_SCALE; lbl.offset_bottom = sy + slot_px
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _make_slot(sx: float, sy: float, slot_px: float, icon_sz: float, pad: float) -> Dictionary:
	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_CENTER)
	btn.offset_left = sx; btn.offset_right = sx + slot_px
	btn.offset_top = sy; btn.offset_bottom = sy + slot_px
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(1, 1, 1, 0.12)
	btn.add_theme_stylebox_override("hover", hover_style)
	add_child(btn)
	var tex = _make_tex_rect(sx + pad, sy + pad, icon_sz)
	add_child(tex)
	var cnt = _make_count_label(sx, sy, slot_px)
	add_child(cnt)
	return {"btn": btn, "tex": tex, "count_lbl": cnt}

func _make_inv_slot(sx: float, sy: float, slot_px: float, icon_sz: float, pad: float) -> Dictionary:
	var d = _make_slot(sx, sy, slot_px, icon_sz, pad)
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_CENTER)
	bg.offset_left = sx + 1; bg.offset_right = sx + slot_px - 1
	bg.offset_top = sy + 1; bg.offset_bottom = sy + slot_px - 1
	bg.color = Color(0, 0, 0, 0.45)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var lbl = Label.new()
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left = sx + 2; lbl.offset_right = sx + slot_px - 2
	lbl.offset_top = sy + 2; lbl.offset_bottom = sy + slot_px - 2
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	d["name_bg"] = bg
	d["name_lbl"] = lbl
	return d

# ============================================================
# OPEN / CLOSE
# ============================================================
func open_inventory():
	is_open = true
	_inv_page = 0
	_held_item = {}
	for i in range(GRID_SIZE):
		_grid_contents[i] = {}
	_matched_recipe = {}
	_build_inv_slots()
	visible = true
	_refresh_all()

func close_inventory():
	_return_items_to_inventory()
	is_open = false
	visible = false

# ============================================================
# SLOT DATA
# ============================================================
func _build_inv_slots():
	_inv_slots_data.clear()
	if not player:
		return
	var inv = player.get_all_inventory()
	var sorted_types: Array = []
	for bt in inv:
		if inv[bt] > 0:
			sorted_types.append(bt)
	sorted_types.sort_custom(func(a, b): return int(a) < int(b))
	for bt in sorted_types:
		_inv_slots_data.append({"block_type": bt, "count": inv[bt]})
	var min_size = maxi(SLOTS_PER_PAGE, _inv_slots_data.size() + SLOTS_PER_PAGE)
	while _inv_slots_data.size() < min_size:
		_inv_slots_data.append({})

func _add_to_inv_slot_and_dict(bt, count: int):
	player._add_to_inventory(bt, count)
	for i in range(_inv_slots_data.size()):
		if not _inv_slots_data[i].is_empty() and _inv_slots_data[i]["block_type"] == bt:
			_inv_slots_data[i]["count"] += count
			return
	for i in range(_inv_slots_data.size()):
		if _inv_slots_data[i].is_empty():
			_inv_slots_data[i] = {"block_type": bt, "count": count}
			return
	_inv_slots_data.append({"block_type": bt, "count": count})

func sort_inventory():
	_build_inv_slots()
	_inv_page = 0
	_refresh_all()

# ============================================================
# REFRESH
# ============================================================
func _refresh_all():
	_refresh_inv_slots()
	_refresh_grid_visuals()
	_check_recipe()
	_update_output()
	_update_cursor()
	_update_pagination()

func _refresh_inv_slots():
	var offset = _inv_page * SLOTS_PER_PAGE
	for i in range(_inv_ui.size()):
		var slot_ui = _inv_ui[i]
		var idx = offset + i
		if idx < _inv_slots_data.size() and not _inv_slots_data[idx].is_empty():
			var item = _inv_slots_data[idx]
			slot_ui["tex"].texture = _load_block_icon(item["block_type"])
			slot_ui["tex"].modulate = Color.WHITE
			slot_ui["count_lbl"].text = str(item["count"]) if item["count"] > 1 else ""
			slot_ui["name_lbl"].text = BlockRegistry.get_block_name(item["block_type"])
			slot_ui["name_bg"].visible = true
			slot_ui["name_lbl"].visible = true
		else:
			slot_ui["tex"].texture = null
			slot_ui["count_lbl"].text = ""
			slot_ui["name_lbl"].text = ""
			slot_ui["name_bg"].visible = false
			slot_ui["name_lbl"].visible = false
		slot_ui["btn"].visible = true

func _refresh_grid_visuals():
	for i in range(GRID_SIZE):
		var cell = _grid_contents[i]
		var ui = _grid_ui[i]
		if not cell.is_empty():
			ui["tex"].texture = _load_block_icon(cell["block_type"])
			ui["tex"].modulate = Color.WHITE
			ui["count_lbl"].text = str(cell["count"]) if cell["count"] > 1 else ""
		else:
			ui["tex"].texture = null
			ui["count_lbl"].text = ""

func _update_output():
	if not _matched_recipe.is_empty():
		_output_tex.texture = _load_block_icon(_matched_recipe["output_type"])
		_output_tex.modulate = Color.WHITE
		var oc = _matched_recipe.get("output_count", 1)
		_output_count_lbl.text = "x%d" % oc if oc > 1 else ""
		_output_name_lbl.text = BlockRegistry.get_block_name(_matched_recipe["output_type"])
		_hint_label.text = _matched_recipe.get("name", "")
		_hint_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 0.9))
	else:
		_output_tex.texture = null
		_output_count_lbl.text = ""
		_output_name_lbl.text = ""
		var has_items = false
		for cell in _grid_contents:
			if not cell.is_empty():
				has_items = true
				break
		if has_items:
			_hint_label.text = "Aucune recette ne correspond"
			_hint_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5, 0.9))
		else:
			_hint_label.text = ""
			_hint_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7, 0.8))

func _update_cursor():
	if not _held_item.is_empty():
		_cursor_tex.texture = _load_block_icon(_held_item["block_type"])
		_cursor_tex.visible = true
		_cursor_count.text = str(_held_item["count"]) if _held_item["count"] > 1 else ""
		_cursor_count.visible = _held_item["count"] > 1
	else:
		_cursor_tex.visible = false
		_cursor_count.visible = false

func _update_pagination():
	var total = maxi(1, ceili(float(_inv_slots_data.size()) / SLOTS_PER_PAGE))
	if _page_label:
		_page_label.text = "%d/%d" % [_inv_page + 1, total]
	if _prev_btn:
		_prev_btn.visible = total > 1
		_prev_btn.disabled = _inv_page <= 0
	if _next_btn:
		_next_btn.visible = total > 1
		_next_btn.disabled = _inv_page >= total - 1

# ============================================================
# INPUT — INVENTORY SLOTS
# ============================================================
func _on_inv_input(event: InputEvent, index: int):
	if not (event is InputEventMouseButton and event.pressed):
		return
	var slot_idx = _inv_page * SLOTS_PER_PAGE + index
	while slot_idx >= _inv_slots_data.size():
		_inv_slots_data.append({})
	var slot = _inv_slots_data[slot_idx]

	if event.button_index == MOUSE_BUTTON_LEFT:
		if _held_item.is_empty():
			if not slot.is_empty():
				_held_item = slot.duplicate()
				player._remove_from_inventory(slot["block_type"], slot["count"])
				_inv_slots_data[slot_idx] = {}
				_refresh_all()
		else:
			if slot.is_empty():
				_inv_slots_data[slot_idx] = _held_item.duplicate()
				player._add_to_inventory(_held_item["block_type"], _held_item["count"])
				_held_item = {}
				_refresh_all()
			elif slot["block_type"] == _held_item["block_type"]:
				slot["count"] += _held_item["count"]
				player._add_to_inventory(_held_item["block_type"], _held_item["count"])
				_held_item = {}
				_refresh_all()
			else:
				var temp = slot.duplicate()
				_inv_slots_data[slot_idx] = _held_item.duplicate()
				player._add_to_inventory(_held_item["block_type"], _held_item["count"])
				player._remove_from_inventory(temp["block_type"], temp["count"])
				_held_item = temp
				_refresh_all()

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if not _held_item.is_empty():
			if slot.is_empty():
				_inv_slots_data[slot_idx] = {"block_type": _held_item["block_type"], "count": 1}
				player._add_to_inventory(_held_item["block_type"], 1)
				_held_item["count"] -= 1
				if _held_item["count"] <= 0:
					_held_item = {}
				_refresh_all()
			elif slot["block_type"] == _held_item["block_type"]:
				slot["count"] += 1
				player._add_to_inventory(_held_item["block_type"], 1)
				_held_item["count"] -= 1
				if _held_item["count"] <= 0:
					_held_item = {}
				_refresh_all()
		else:
			if not slot.is_empty():
				var take = ceili(slot["count"] / 2.0)
				_held_item = {"block_type": slot["block_type"], "count": take}
				player._remove_from_inventory(slot["block_type"], take)
				slot["count"] -= take
				if slot["count"] <= 0:
					_inv_slots_data[slot_idx] = {}
				_refresh_all()

# ============================================================
# INPUT — GRILLE CRAFT 2x2
# ============================================================
func _on_grid_input(event: InputEvent, index: int):
	if not (event is InputEventMouseButton and event.pressed):
		return
	var cell = _grid_contents[index]

	if event.button_index == MOUSE_BUTTON_LEFT:
		if _held_item.is_empty():
			if not cell.is_empty():
				_held_item = cell.duplicate()
				_grid_contents[index] = {}
				_refresh_all()
		else:
			if cell.is_empty():
				_grid_contents[index] = _held_item.duplicate()
				_held_item = {}
				_refresh_all()
			elif cell["block_type"] == _held_item["block_type"]:
				cell["count"] += _held_item["count"]
				_held_item = {}
				_refresh_all()
			else:
				var temp = cell.duplicate()
				_grid_contents[index] = _held_item.duplicate()
				_held_item = temp
				_refresh_all()

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if not _held_item.is_empty():
			if cell.is_empty():
				_grid_contents[index] = {"block_type": _held_item["block_type"], "count": 1}
				_held_item["count"] -= 1
				if _held_item["count"] <= 0:
					_held_item = {}
				_refresh_all()
			elif cell["block_type"] == _held_item["block_type"]:
				cell["count"] += 1
				_held_item["count"] -= 1
				if _held_item["count"] <= 0:
					_held_item = {}
				_refresh_all()
		else:
			if not cell.is_empty():
				var take = ceili(cell["count"] / 2.0)
				_held_item = {"block_type": cell["block_type"], "count": take}
				cell["count"] -= take
				if cell["count"] <= 0:
					_grid_contents[index] = {}
				_refresh_all()

# ============================================================
# INPUT — OUTPUT (craft)
# ============================================================
func _on_output_input(event: InputEvent):
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _matched_recipe.is_empty() or not player:
		return
	_consume_grid_for_recipe(_matched_recipe)
	_add_to_inv_slot_and_dict(_matched_recipe["output_type"], _matched_recipe["output_count"])
	var audio = get_tree().get_first_node_in_group("audio_manager")
	if audio and audio.has_method("play_craft_success"):
		audio.play_craft_success()
	_refresh_all()

func _on_bg_input(event: InputEvent):
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and not _held_item.is_empty():
		_add_to_inv_slot_and_dict(_held_item["block_type"], _held_item["count"])
		_held_item = {}
		_refresh_all()

func _on_prev_page():
	if _inv_page > 0:
		_inv_page -= 1
		_refresh_inv_slots()
		_update_pagination()

func _on_next_page():
	var total = maxi(1, ceili(float(_inv_slots_data.size()) / SLOTS_PER_PAGE))
	if _inv_page < total - 1:
		_inv_page += 1
		_refresh_inv_slots()
		_update_pagination()

# ============================================================
# RECIPE MATCHING
# ============================================================
func _check_recipe():
	var grid_totals: Dictionary = {}
	for cell in _grid_contents:
		if not cell.is_empty():
			var bt = cell["block_type"]
			grid_totals[bt] = grid_totals.get(bt, 0) + cell["count"]
	if grid_totals.is_empty():
		_matched_recipe = {}
		return
	var best: Dictionary = {}
	var best_score: int = 0
	for recipe in _available_recipes:
		var inputs = recipe.get("inputs", [])
		var matches = true
		var score = 0
		for inp in inputs:
			var have = grid_totals.get(inp[0], 0)
			if have < inp[1]:
				matches = false
				break
			score += inp[1]
		if matches and score > best_score:
			best = recipe
			best_score = score
	_matched_recipe = best

func _consume_grid_for_recipe(recipe: Dictionary):
	var required: Dictionary = {}
	for inp in recipe["inputs"]:
		required[inp[0]] = required.get(inp[0], 0) + inp[1]
	for bt in required:
		var remaining = required[bt]
		for i in range(GRID_SIZE):
			if remaining <= 0:
				break
			if _grid_contents[i].is_empty() or _grid_contents[i]["block_type"] != bt:
				continue
			var take = mini(remaining, _grid_contents[i]["count"])
			_grid_contents[i]["count"] -= take
			remaining -= take
			if _grid_contents[i]["count"] <= 0:
				_grid_contents[i] = {}

func _return_items_to_inventory():
	if not player:
		return
	if not _held_item.is_empty():
		_add_to_inv_slot_and_dict(_held_item["block_type"], _held_item["count"])
		_held_item = {}
	for i in range(GRID_SIZE):
		if not _grid_contents[i].is_empty():
			_add_to_inv_slot_and_dict(_grid_contents[i]["block_type"], _grid_contents[i]["count"])
			_grid_contents[i] = {}

# ============================================================
# HOVER / TOOLTIPS
# ============================================================
func _on_inv_hover(index: int):
	var slot_idx = _inv_page * SLOTS_PER_PAGE + index
	if slot_idx < _inv_slots_data.size() and not _inv_slots_data[slot_idx].is_empty():
		var item = _inv_slots_data[slot_idx]
		_tooltip_label.text = "%s (x%d)" % [BlockRegistry.get_block_name(item["block_type"]), item["count"]]
		_tooltip_label.visible = true

func _on_grid_hover(index: int):
	if index < GRID_SIZE and not _grid_contents[index].is_empty():
		var cell = _grid_contents[index]
		_tooltip_label.text = "%s (x%d)" % [BlockRegistry.get_block_name(cell["block_type"]), cell["count"]]
		_tooltip_label.visible = true

func _on_output_hover():
	if not _matched_recipe.is_empty():
		_tooltip_label.text = "Cliquer pour crafter : %s" % BlockRegistry.get_block_name(_matched_recipe["output_type"])
		_tooltip_label.visible = true

func _on_hover_exit():
	if _tooltip_label:
		_tooltip_label.visible = false

# ============================================================
# PROCESS
# ============================================================
func _process(_delta):
	if not is_open:
		return
	var mpos = get_viewport().get_mouse_position()
	if _cursor_tex and _cursor_tex.visible:
		var sz = 28 * GUI_SCALE
		_cursor_tex.offset_left = mpos.x - sz / 2
		_cursor_tex.offset_top = mpos.y - sz / 2
		_cursor_tex.offset_right = mpos.x + sz / 2
		_cursor_tex.offset_bottom = mpos.y + sz / 2
		if _cursor_count and _cursor_count.visible:
			_cursor_count.offset_left = mpos.x + sz / 2 - 24
			_cursor_count.offset_top = mpos.y + sz / 2 - 16
			_cursor_count.offset_right = mpos.x + sz / 2 + 12
			_cursor_count.offset_bottom = mpos.y + sz / 2 + 4
	if _tooltip_label and _tooltip_label.visible:
		_tooltip_label.offset_left = mpos.x + 16
		_tooltip_label.offset_top = mpos.y - 10
		_tooltip_label.offset_right = mpos.x + 250
		_tooltip_label.offset_bottom = mpos.y + 16

# ============================================================
# ICON LOADING
# ============================================================
func _load_block_icon(block_type) -> ImageTexture:
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
