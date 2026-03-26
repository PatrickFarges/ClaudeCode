# inventory_ui.gd v2.3.0
# Inventaire style Minecraft avec texture Faithful32 (inventory.png)
# Ouvert avec I — affiche uniquement les items possedes (count > 0)

extends CanvasLayer

const GC = preload("res://scripts/game_config.gd")
const GUI_DIR = "res://TexturesPack/Faithful32/assets/minecraft/textures/gui/"
const GUI_SCALE = 2

var player: CharacterBody3D = null
var is_open: bool = false
var _icon_cache: Dictionary = {}
var _background: ColorRect = null
var _inv_texture: TextureRect = null
var _title_label: Label = null
var _slot_buttons: Array = []  # [{button, tex_rect, count_label, block_type}, ...]
var _tab_buttons: Array = []
var _current_tab: int = 0
var _current_page: int = 0
var _page_label: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null
var _tooltip_label: Label = null
const SLOTS_PER_PAGE = 36  # 3x9 + 1x9 hotbar

# Texture content area (Faithful32 = 2x vanilla MC 176x166)
const TEX_W = 352  # pixels dans la texture
const TEX_H = 332

# Liste dynamique des items possedes (rebuilt a chaque ouverture/refresh)
var _owned_items: Array = []

func _ready():
	layer = 10
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	_build_ui()
	visible = false

func _build_ui():
	# Fond sombre semi-transparent
	_background = ColorRect.new()
	_background.color = Color(0, 0, 0, 0.65)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_background)

	# Texture inventaire MC — cropper a la zone de contenu (352x332 dans le 512x512)
	var inv_img = Image.load_from_file(GUI_DIR + "container/inventory.png")
	var inv_tex: ImageTexture = null
	if inv_img:
		var cropped = inv_img.get_region(Rect2i(0, 0, TEX_W, TEX_H))
		inv_tex = ImageTexture.create_from_image(cropped)

	_inv_texture = TextureRect.new()
	_inv_texture.texture = inv_tex
	_inv_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_inv_texture.set_anchors_preset(Control.PRESET_CENTER)
	var disp_w = TEX_W * GUI_SCALE
	var disp_h = TEX_H * GUI_SCALE
	_inv_texture.offset_left = -disp_w / 2
	_inv_texture.offset_right = disp_w / 2
	_inv_texture.offset_top = -disp_h / 2
	_inv_texture.offset_bottom = disp_h / 2
	_inv_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_inv_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inv_texture)

	# Titre "Inventaire"
	_title_label = Label.new()
	_title_label.text = "Inventaire"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.set_anchors_preset(Control.PRESET_CENTER)
	_title_label.offset_left = -150
	_title_label.offset_right = 150
	_title_label.offset_top = -disp_h / 2 - 30
	_title_label.offset_bottom = -disp_h / 2 - 4
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(1, 1, 0.9, 1))
	_title_label.add_theme_color_override("font_shadow_color", Color(0.15, 0.15, 0.15, 1))
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	# Creer les boutons de slot dans la grille inventaire (3x9 + hotbar 1x9)
	# Les slots de la texture sont a des positions fixes
	# Inventaire 3x9 : commence a (14, 166) dans la texture, pas de 36px
	# Hotbar 1x9 : commence a (14, 282)
	var tex_offset_x = -disp_w / 2.0
	var tex_offset_y = -disp_h / 2.0
	var slot_px = 36 * GUI_SCALE  # taille slot a l'ecran
	var icon_px = 28 * GUI_SCALE  # taille icone dans le slot
	var slot_padding = (slot_px - icon_px) / 2.0

	# On utilise la zone inventaire (3x9 = 27 slots + 9 hotbar = 36 slots)
	# pour afficher les blocs disponibles
	var all_slots_pos: Array = []
	# 3 rangees inventaire
	for row in range(3):
		for col in range(9):
			var sx = tex_offset_x + (14 + col * 36) * GUI_SCALE
			var sy = tex_offset_y + (166 + row * 36) * GUI_SCALE
			all_slots_pos.append(Vector2(sx, sy))
	# 1 rangee hotbar
	for col in range(9):
		var sx = tex_offset_x + (14 + col * 36) * GUI_SCALE
		var sy = tex_offset_y + 282 * GUI_SCALE
		all_slots_pos.append(Vector2(sx, sy))

	# Creer un bouton invisible par slot (toujours 36 slots, contenu change avec la page)
	for i in range(SLOTS_PER_PAGE):
		var pos = all_slots_pos[i]

		var btn = Button.new()
		btn.set_anchors_preset(Control.PRESET_CENTER)
		btn.offset_left = pos.x
		btn.offset_right = pos.x + slot_px
		btn.offset_top = pos.y
		btn.offset_bottom = pos.y + slot_px
		btn.flat = true  # pas de fond de bouton (la texture MC fait le fond)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_on_slot_pressed_by_index.bind(i))
		add_child(btn)

		var tex_rect = TextureRect.new()
		tex_rect.set_anchors_preset(Control.PRESET_CENTER)
		tex_rect.offset_left = pos.x + slot_padding
		tex_rect.offset_right = pos.x + slot_padding + icon_px
		tex_rect.offset_top = pos.y + slot_padding
		tex_rect.offset_bottom = pos.y + slot_padding + icon_px
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex_rect)

		# Fond semi-transparent pour le nom (meilleure lisibilite)
		var name_bg = ColorRect.new()
		name_bg.set_anchors_preset(Control.PRESET_CENTER)
		name_bg.offset_left = pos.x + 1
		name_bg.offset_right = pos.x + slot_px - 1
		name_bg.offset_top = pos.y + 1
		name_bg.offset_bottom = pos.y + slot_px - 1
		name_bg.color = Color(0, 0, 0, 0.45)
		name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(name_bg)

		# Nom de l'item (affiche directement sur le slot)
		var name_label = Label.new()
		name_label.set_anchors_preset(Control.PRESET_CENTER)
		name_label.offset_left = pos.x + 2
		name_label.offset_right = pos.x + slot_px - 2
		name_label.offset_top = pos.y + 2
		name_label.offset_bottom = pos.y + slot_px - 2
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 9)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		name_label.add_theme_constant_override("shadow_offset_x", 1)
		name_label.add_theme_constant_override("shadow_offset_y", 1)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(name_label)

		var count_label = Label.new()
		count_label.set_anchors_preset(Control.PRESET_CENTER)
		count_label.offset_left = pos.x + slot_px - 30 * GUI_SCALE
		count_label.offset_right = pos.x + slot_px - 2
		count_label.offset_top = pos.y + slot_px - 14 * GUI_SCALE
		count_label.offset_bottom = pos.y + slot_px
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_font_size_override("font_size", 14)
		count_label.add_theme_color_override("font_color", Color.WHITE)
		count_label.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
		count_label.add_theme_constant_override("shadow_offset_x", 2)
		count_label.add_theme_constant_override("shadow_offset_y", 2)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(count_label)

		_slot_buttons.append({
			"button": btn,
			"tex_rect": tex_rect,
			"name_bg": name_bg,
			"name_label": name_label,
			"count_label": count_label,
		})

	# Hover tooltip sur chaque slot
	for i in range(_slot_buttons.size()):
		var btn = _slot_buttons[i]["button"]
		btn.mouse_entered.connect(_on_slot_hover.bind(i))
		btn.mouse_exited.connect(_on_slot_unhover)

	# Tooltip flottant
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
	tip_style.border_width_left = 2
	tip_style.border_width_top = 2
	tip_style.border_width_right = 2
	tip_style.border_width_bottom = 2
	tip_style.corner_radius_top_left = 4
	tip_style.corner_radius_top_right = 4
	tip_style.corner_radius_bottom_left = 4
	tip_style.corner_radius_bottom_right = 4
	tip_style.content_margin_left = 6
	tip_style.content_margin_right = 6
	tip_style.content_margin_top = 3
	tip_style.content_margin_bottom = 3
	_tooltip_label.add_theme_stylebox_override("normal", tip_style)
	add_child(_tooltip_label)

	# Navigation pages (< Page X/Y >)
	var nav_y = disp_h / 2 + 10
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.15, 0.3, 0.85)
	btn_style.border_color = Color(0.5, 0.3, 0.7, 0.9)
	btn_style.set_border_width_all(2)
	btn_style.set_corner_radius_all(4)

	_prev_btn = Button.new()
	_prev_btn.text = "< Préc."
	_prev_btn.set_anchors_preset(Control.PRESET_CENTER)
	_prev_btn.offset_left = -120
	_prev_btn.offset_right = -30
	_prev_btn.offset_top = nav_y
	_prev_btn.offset_bottom = nav_y + 30
	_prev_btn.add_theme_stylebox_override("normal", btn_style)
	_prev_btn.add_theme_color_override("font_color", Color.WHITE)
	_prev_btn.pressed.connect(_on_prev_page)
	add_child(_prev_btn)

	_page_label = Label.new()
	_page_label.set_anchors_preset(Control.PRESET_CENTER)
	_page_label.offset_left = -30
	_page_label.offset_right = 30
	_page_label.offset_top = nav_y + 4
	_page_label.offset_bottom = nav_y + 30
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.add_theme_font_size_override("font_size", 14)
	_page_label.add_theme_color_override("font_color", Color(1, 1, 0.9, 1))
	_page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page_label)

	_next_btn = Button.new()
	_next_btn.text = "Suiv. >"
	_next_btn.set_anchors_preset(Control.PRESET_CENTER)
	_next_btn.offset_left = 30
	_next_btn.offset_right = 120
	_next_btn.offset_top = nav_y
	_next_btn.offset_bottom = nav_y + 30
	_next_btn.add_theme_stylebox_override("normal", btn_style)
	_next_btn.add_theme_color_override("font_color", Color.WHITE)
	_next_btn.pressed.connect(_on_next_page)
	add_child(_next_btn)

	# Charger les icones
	_refresh_slots()

func _get_total_pages() -> int:
	return max(1, ceili(float(_owned_items.size()) / SLOTS_PER_PAGE))

func _build_owned_items():
	_owned_items.clear()
	if not player:
		return
	var inv = player.get_all_inventory()
	for bt in inv:
		if inv[bt] > 0:
			_owned_items.append(bt)
	_owned_items.sort_custom(func(a, b): return int(a) < int(b))

func _refresh_slots():
	_build_owned_items()
	# Corriger la page si depassee
	var total_pages = _get_total_pages()
	if _current_page >= total_pages:
		_current_page = max(0, total_pages - 1)
	var page_offset = _current_page * SLOTS_PER_PAGE
	for i in range(_slot_buttons.size()):
		var slot = _slot_buttons[i]
		var item_index = page_offset + i
		if item_index < _owned_items.size():
			var bt = _owned_items[item_index]
			var count = player.get_inventory_count(bt) if player else 0
			var tex = _load_block_icon(bt)
			slot["tex_rect"].texture = tex
			slot["tex_rect"].modulate = Color.WHITE
			slot["count_label"].text = str(count) if count > 1 else ""
			var block_name = BlockRegistry.get_block_name(bt)
			slot["name_label"].text = block_name
			slot["button"].visible = true
			slot["name_bg"].visible = true
			slot["name_bg"].color = Color(0, 0, 0, 0.45)
			slot["name_label"].add_theme_color_override("font_color", Color.WHITE)
		else:
			slot["tex_rect"].texture = null
			slot["count_label"].text = ""
			slot["name_label"].text = ""
			slot["button"].visible = false
			slot["name_bg"].visible = false

	# Update page navigation
	var total_pages = _get_total_pages()
	if _page_label:
		_page_label.text = "%d/%d" % [_current_page + 1, total_pages]
	if _prev_btn:
		_prev_btn.visible = total_pages > 1
		_prev_btn.disabled = _current_page <= 0
	if _next_btn:
		_next_btn.visible = total_pages > 1
		_next_btn.disabled = _current_page >= total_pages - 1

func open_inventory():
	is_open = true
	visible = true
	_refresh_slots()

func close_inventory():
	is_open = false
	visible = false

func _process(_delta):
	if _tooltip_label and _tooltip_label.visible:
		var mpos = get_viewport().get_mouse_position()
		_tooltip_label.offset_left = mpos.x + 16
		_tooltip_label.offset_top = mpos.y - 10
		_tooltip_label.offset_right = mpos.x + 250
		_tooltip_label.offset_bottom = mpos.y + 16

func _get_block_for_slot(slot_index: int) -> int:
	var item_index = _current_page * SLOTS_PER_PAGE + slot_index
	if item_index < _owned_items.size():
		return _owned_items[item_index]
	return -1

func _on_slot_hover(index: int):
	var bt = _get_block_for_slot(index)
	if bt >= 0:
		var block_name = BlockRegistry.get_block_name(bt)
		var count = player.get_inventory_count(bt) if player else 0
		_tooltip_label.text = "%s (x%d)" % [block_name, count]
		_tooltip_label.visible = true

func _on_slot_unhover():
	if _tooltip_label:
		_tooltip_label.visible = false

func _on_slot_pressed_by_index(slot_index: int):
	var bt = _get_block_for_slot(slot_index)
	if bt >= 0 and player and player.has_method("assign_hotbar_slot"):
		player.assign_hotbar_slot(player.selected_slot, bt)
		_refresh_slots()

func _on_prev_page():
	if _current_page > 0:
		_current_page -= 1
		_refresh_slots()

func _on_next_page():
	if _current_page < _get_total_pages() - 1:
		_current_page += 1
		_refresh_slots()

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
	if tint != Color(1,1,1,1):
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c = img.get_pixel(x, y)
				img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	var tex = ImageTexture.create_from_image(img)
	_icon_cache[cache_key] = tex
	return tex
