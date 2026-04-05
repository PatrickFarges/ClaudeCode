# hotbar_ui.gd v2.2.0
# HUD Minecraft complet : hotbar + coeurs + faim + armure + bulles d'air + XP bar + crosshair
# Utilise les textures Faithful32 GUI (sprites/hud/*)

extends CanvasLayer

const GC = preload("res://scripts/game_config.gd")

const NUM_SLOTS = 9
const GUI_SCALE = 2  # Faithful32 = 2x vanilla, scale 2x pour 1080p
const GUI_DIR = "res://TexturesPack/Faithful32/assets/minecraft/textures/gui/"

# Chemins des textures HUD
const TEX_HOTBAR = GUI_DIR + "sprites/hud/hotbar.png"
const TEX_SELECTION = GUI_DIR + "sprites/hud/hotbar_selection.png"
const TEX_HEART_FULL = GUI_DIR + "sprites/hud/heart/full.png"
const TEX_HEART_HALF = GUI_DIR + "sprites/hud/heart/half.png"
const TEX_HEART_BG = GUI_DIR + "sprites/hud/heart/container.png"
const TEX_FOOD_FULL = GUI_DIR + "sprites/hud/food_full_hunger.png"
const TEX_FOOD_HALF = GUI_DIR + "sprites/hud/food_half_hunger.png"
const TEX_FOOD_EMPTY = GUI_DIR + "sprites/hud/food_empty_hunger.png"
const TEX_ARMOR_FULL = GUI_DIR + "sprites/hud/armor_full.png"
const TEX_ARMOR_HALF = GUI_DIR + "sprites/hud/armor_half.png"
const TEX_ARMOR_EMPTY = GUI_DIR + "sprites/hud/armor_empty.png"
const TEX_AIR_FULL = GUI_DIR + "sprites/hud/air.png"
const TEX_AIR_BURST = GUI_DIR + "sprites/hud/air_bursting.png"
const TEX_AIR_EMPTY = GUI_DIR + "sprites/hud/air_empty.png"
const TEX_XP_BG = GUI_DIR + "sprites/hud/experience_bar_background.png"
const TEX_XP_FILL = GUI_DIR + "sprites/hud/experience_bar_progress.png"

var player: CharacterBody3D
var _icon_cache: Dictionary = {}

# References nodes HUD
var _hotbar_rect: TextureRect = null       # hotbar.png background
var _selection_rect: TextureRect = null     # hotbar_selection.png
var _slot_icons: Array = []                # [{tex_rect, count_label}, ...]
var _name_label: Label = null
var _heart_icons: Array = []               # [TextureRect x 10]
var _heart_bgs: Array = []                 # [TextureRect x 10]
var _food_icons: Array = []                # [TextureRect x 10]
var _armor_icons: Array = []               # [TextureRect x 10]
var _air_icons: Array = []                 # [TextureRect x 10] — bulles d'oxygene
var _air_visible: bool = false             # bulles visibles seulement sous l'eau
var _burst_timers: Array = []              # timer animation burst par bulle
var _xp_bg: TextureRect = null

# Dirty flags — evite les mises a jour redondantes chaque frame
var _last_hp := -1
var _last_selected_slot := -1
var _last_hotbar_slots: Array = []
var _last_hotbar_tools: Array = []
var _last_hotbar_counts: Array = []
var _xp_fill: TextureRect = null
var _crosshair: TextureRect = null

# Textures chargees
var _tex_cache: Dictionary = {}

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	_build_hud()

func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex = load(path) as Texture2D
	if tex:
		_tex_cache[path] = tex
		return tex
	var img = Image.load_from_file(path)
	if img:
		var itex = ImageTexture.create_from_image(img)
		_tex_cache[path] = itex
		return itex
	return null

func _build_hud():
	# Crosshair = gere par la scene Crosshair existante dans main.tscn

	# ============================================================
	# HOTBAR (bas centre)
	# ============================================================
	# Hotbar background (364x44 @ scale 2 = 728x88)
	var hotbar_tex = _load_tex(TEX_HOTBAR)
	_hotbar_rect = TextureRect.new()
	_hotbar_rect.texture = hotbar_tex
	_hotbar_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hotbar_rect.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var hw = 364 * GUI_SCALE
	var hh = 44 * GUI_SCALE
	_hotbar_rect.offset_left = -hw / 2
	_hotbar_rect.offset_right = hw / 2
	_hotbar_rect.offset_top = -hh - 2
	_hotbar_rect.offset_bottom = -2
	_hotbar_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_hotbar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotbar_rect)

	# Selection highlight (48x46 @ scale 2 = 96x92)
	_selection_rect = TextureRect.new()
	_selection_rect.texture = _load_tex(TEX_SELECTION)
	_selection_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_selection_rect.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_selection_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_selection_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_selection_rect)

	# Slot item icons (9 slots, chaque slot = 40px dans la texture hotbar a scale 2)
	var slot_size = 40 * GUI_SCALE  # 80px par slot
	var icon_size = 32 * GUI_SCALE  # 64px icone
	var hotbar_left = -hw / 2.0
	var slot_start_x = hotbar_left + 6 * GUI_SCALE  # 6px de marge dans la texture
	var slot_y = -hh - 2 + 6 * GUI_SCALE  # 6px depuis le haut de la hotbar

	for i in range(NUM_SLOTS):
		var slot_x = slot_start_x + i * slot_size

		var tex_rect = TextureRect.new()
		tex_rect.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		tex_rect.offset_left = slot_x + (slot_size - icon_size) / 2.0 - 2
		tex_rect.offset_right = tex_rect.offset_left + icon_size
		tex_rect.offset_top = slot_y + (slot_size - icon_size) / 2.0 - 6
		tex_rect.offset_bottom = tex_rect.offset_top + icon_size
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex_rect)

		var count_label = Label.new()
		count_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		count_label.offset_left = slot_x + slot_size - 28 * GUI_SCALE
		count_label.offset_right = slot_x + slot_size - 2 * GUI_SCALE
		count_label.offset_top = slot_y + slot_size - 16 * GUI_SCALE
		count_label.offset_bottom = slot_y + slot_size
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_font_size_override("font_size", 16)
		count_label.add_theme_color_override("font_color", Color.WHITE)
		count_label.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1.0))
		count_label.add_theme_constant_override("shadow_offset_x", 2)
		count_label.add_theme_constant_override("shadow_offset_y", 2)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(count_label)

		_slot_icons.append({"tex_rect": tex_rect, "count_label": count_label})

	# Item name label (above hotbar)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_name_label.offset_left = -300
	_name_label.offset_right = 300
	_name_label.offset_top = -hh - 24
	_name_label.offset_bottom = -hh - 4
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1.0))
	_name_label.add_theme_constant_override("shadow_offset_x", 2)
	_name_label.add_theme_constant_override("shadow_offset_y", 2)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	# ============================================================
	# COEURS (au-dessus de la hotbar, cote gauche)
	# ============================================================
	var icon_s = 18 * GUI_SCALE  # 36px
	var icon_spacing = 16 * GUI_SCALE  # 32px (chevauche un peu comme MC)
	var hearts_y = -hh - 8 - icon_s  # au-dessus de la hotbar
	var hearts_x = hotbar_left + 2 * GUI_SCALE

	for i in range(10):
		var bg = TextureRect.new()
		bg.texture = _load_tex(TEX_HEART_BG)
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		bg.offset_left = hearts_x + i * icon_spacing
		bg.offset_right = bg.offset_left + icon_s
		bg.offset_top = hearts_y
		bg.offset_bottom = hearts_y + icon_s
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		_heart_bgs.append(bg)

		var heart = TextureRect.new()
		heart.texture = _load_tex(TEX_HEART_FULL)
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		heart.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		heart.offset_left = bg.offset_left
		heart.offset_right = bg.offset_right
		heart.offset_top = bg.offset_top
		heart.offset_bottom = bg.offset_bottom
		heart.stretch_mode = TextureRect.STRETCH_SCALE
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(heart)
		_heart_icons.append(heart)

	# ============================================================
	# FAIM (au-dessus de la hotbar, cote droit — miroir des coeurs)
	# ============================================================
	var food_x_start = -hotbar_left - 2 * GUI_SCALE  # cote droit
	for i in range(10):
		var food = TextureRect.new()
		food.texture = _load_tex(TEX_FOOD_FULL)
		food.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		food.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		# Miroir : de droite a gauche
		food.offset_right = food_x_start - i * icon_spacing
		food.offset_left = food.offset_right - icon_s
		food.offset_top = hearts_y
		food.offset_bottom = hearts_y + icon_s
		food.stretch_mode = TextureRect.STRETCH_SCALE
		food.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(food)
		_food_icons.append(food)

	# ============================================================
	# ARMURE (au-dessus des coeurs)
	# ============================================================
	var armor_y = hearts_y - icon_s - 2
	for i in range(10):
		var armor = TextureRect.new()
		armor.texture = _load_tex(TEX_ARMOR_EMPTY)
		armor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		armor.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		armor.offset_left = hearts_x + i * icon_spacing
		armor.offset_right = armor.offset_left + icon_s
		armor.offset_top = armor_y
		armor.offset_bottom = armor_y + icon_s
		armor.stretch_mode = TextureRect.STRETCH_SCALE
		armor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		armor.visible = false  # Cache par defaut, visible quand armure equipee
		add_child(armor)
		_armor_icons.append(armor)

	# ============================================================
	# BULLES D'AIR (au-dessus de la faim, cote droit — comme MC)
	# Visibles uniquement quand la tete est sous l'eau
	# ============================================================
	var air_y = hearts_y - icon_s - 2  # meme ligne que l'armure mais cote droit
	for i in range(10):
		var air = TextureRect.new()
		air.texture = _load_tex(TEX_AIR_FULL)
		air.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		air.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		air.offset_right = food_x_start - i * icon_spacing
		air.offset_left = air.offset_right - icon_s
		air.offset_top = air_y
		air.offset_bottom = air_y + icon_s
		air.stretch_mode = TextureRect.STRETCH_SCALE
		air.mouse_filter = Control.MOUSE_FILTER_IGNORE
		air.visible = false  # Cache par defaut
		add_child(air)
		_air_icons.append(air)
		_burst_timers.append(0.0)

	# ============================================================
	# BARRE XP (juste au-dessus de la hotbar)
	# ============================================================
	_xp_bg = TextureRect.new()
	_xp_bg.texture = _load_tex(TEX_XP_BG)
	_xp_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_xp_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var xp_w = 364 * GUI_SCALE
	var xp_h = 10 * GUI_SCALE
	_xp_bg.offset_left = -xp_w / 2
	_xp_bg.offset_right = xp_w / 2
	_xp_bg.offset_top = -hh - 4
	_xp_bg.offset_bottom = -hh - 4 + xp_h
	_xp_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_xp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bg.visible = false  # Pas de systeme XP encore
	add_child(_xp_bg)

func _process(delta):
	if player:
		_update_hotbar()
		_update_hearts()
		_update_food()
		_update_air(delta)

# ============================================================
# HOTBAR UPDATE
# ============================================================
func _update_hotbar():
	var current_slot = player.selected_slot
	var slot_changed = current_slot != _last_selected_slot

	# Build current state snapshot for dirty check
	var cur_slots: Array = player.hotbar_slots.duplicate()
	var cur_tools: Array = player.hotbar_tool_slots.duplicate() if player.hotbar_tool_slots.size() > 0 else []
	var cur_counts: Array = []
	for i in range(min(NUM_SLOTS, cur_slots.size())):
		if player.is_hotbar_slot_empty(i):
			cur_counts.append(0)
		else:
			var tool_type = cur_tools[i] if i < cur_tools.size() else ToolRegistry.ToolType.NONE
			if tool_type != ToolRegistry.ToolType.NONE:
				cur_counts.append(-1)  # tools have no count
			else:
				cur_counts.append(player.get_inventory_count(cur_slots[i]))

	var contents_changed = cur_slots != _last_hotbar_slots or cur_tools != _last_hotbar_tools or cur_counts != _last_hotbar_counts

	if not slot_changed and not contents_changed:
		return

	_last_selected_slot = current_slot
	_last_hotbar_slots = cur_slots
	_last_hotbar_tools = cur_tools
	_last_hotbar_counts = cur_counts

	# Selection highlight position
	if _selection_rect and _hotbar_rect and slot_changed:
		var slot_size = 40 * GUI_SCALE
		var hw = 364 * GUI_SCALE
		var sel_w = 48 * GUI_SCALE
		var sel_h = 46 * GUI_SCALE
		var slot_start_x = -hw / 2.0 + 6 * GUI_SCALE
		var sel_x = slot_start_x + current_slot * slot_size - (sel_w - slot_size) / 2.0
		_selection_rect.offset_left = sel_x
		_selection_rect.offset_right = sel_x + sel_w
		var hh = 44 * GUI_SCALE
		_selection_rect.offset_top = -hh - 2 - (sel_h - hh) / 2.0
		_selection_rect.offset_bottom = _selection_rect.offset_top + sel_h

	# Item name (depends on selected slot + its content)
	if _name_label and (slot_changed or contents_changed):
		if player.is_hotbar_slot_empty(current_slot):
			_name_label.text = ""
		else:
			var tool_type = player._get_selected_tool()
			if tool_type != ToolRegistry.ToolType.NONE:
				_name_label.text = ToolRegistry.get_tool_name(tool_type)
			else:
				var block_type = player.hotbar_slots[current_slot]
				_name_label.text = BlockRegistry.get_block_name(block_type)

	# Slot icons + counts (only when contents changed)
	if contents_changed:
		for i in range(min(_slot_icons.size(), player.hotbar_slots.size())):
			var slot = _slot_icons[i]

			# Verifier si le slot est vide (SUPPR ou jamais assigne)
			if player.is_hotbar_slot_empty(i):
				slot["tex_rect"].texture = null
				slot["count_label"].text = ""
				continue

			var tool_type = ToolRegistry.ToolType.NONE
			if i < player.hotbar_tool_slots.size():
				tool_type = player.hotbar_tool_slots[i]

			if tool_type != ToolRegistry.ToolType.NONE:
				var tex = _load_item_icon(ToolRegistry.get_item_texture_path(tool_type))
				slot["tex_rect"].texture = tex
				slot["tex_rect"].modulate = Color.WHITE
				slot["count_label"].text = ""
			else:
				var block_type = player.hotbar_slots[i]
				var count = cur_counts[i]
				var block_tex = _load_block_icon(block_type)
				slot["tex_rect"].texture = block_tex
				slot["tex_rect"].modulate = Color.WHITE
				slot["count_label"].text = str(count) if count > 1 else ""
				slot["count_label"].add_theme_color_override("font_color", Color.WHITE)

# ============================================================
# HEARTS UPDATE
# ============================================================
func _update_hearts():
	var hp = player.current_health
	if hp == _last_hp:
		return
	_last_hp = hp
	for i in range(10):
		var heart_val = hp - i * 2  # chaque coeur = 2 HP
		if heart_val >= 2:
			_heart_icons[i].texture = _load_tex(TEX_HEART_FULL)
			_heart_icons[i].visible = true
		elif heart_val == 1:
			_heart_icons[i].texture = _load_tex(TEX_HEART_HALF)
			_heart_icons[i].visible = true
		else:
			_heart_icons[i].visible = false

# ============================================================
# FOOD UPDATE
# ============================================================
func _update_food():
	# TODO: Food system not yet implemented — always 20, skip recalculation each frame.
	# Remove this early return when a hunger system is added.
	return

# ============================================================
# AIR BUBBLES UPDATE
# ============================================================
func _update_air(delta: float):
	var underwater = player.is_head_underwater if "is_head_underwater" in player else false

	if underwater:
		# Afficher les bulles
		if not _air_visible:
			_air_visible = true
			for i in range(10):
				_air_icons[i].visible = true
				_burst_timers[i] = 0.0

		# air_ratio = 1.0 (plein) a 0.0 (noyade)
		var air_ratio = player.get_air_ratio() if player.has_method("get_air_ratio") else 1.0
		# 10 bulles = 20 demi-bulles (comme les coeurs)
		var air_val = int(air_ratio * 20.0)  # 0-20

		for i in range(10):
			var bubble_val = air_val - (9 - i) * 2  # bulles de droite a gauche (9=premiere a disparaitre)
			if bubble_val >= 2:
				_air_icons[i].texture = _load_tex(TEX_AIR_FULL)
				_air_icons[i].modulate.a = 1.0
				_burst_timers[i] = 0.0
			elif bubble_val == 1:
				# Bulle a moitie — montrer burst brievement puis empty
				if _burst_timers[i] < 0.3:
					_air_icons[i].texture = _load_tex(TEX_AIR_BURST)
					_burst_timers[i] += delta
				else:
					_air_icons[i].texture = _load_tex(TEX_AIR_EMPTY)
				_air_icons[i].modulate.a = 1.0
			else:
				# Bulle vide — commence a apparaitre en burst puis disparait
				if _burst_timers[i] > 0.0 and _burst_timers[i] < 0.5:
					_air_icons[i].texture = _load_tex(TEX_AIR_BURST)
					_burst_timers[i] += delta
					_air_icons[i].modulate.a = 1.0
				else:
					_air_icons[i].texture = _load_tex(TEX_AIR_EMPTY)
					_air_icons[i].modulate.a = 0.3  # fantome discret
	else:
		# Cacher les bulles hors de l'eau
		if _air_visible:
			_air_visible = false
			for i in range(10):
				_air_icons[i].visible = false
				_burst_timers[i] = 0.0

# ============================================================
# ICON LOADING (meme systeme que l'ancien hotbar)
# ============================================================
func _load_item_icon(tex_path: String) -> ImageTexture:
	if tex_path.is_empty():
		return null
	if _icon_cache.has(tex_path):
		return _icon_cache[tex_path]
	var abs_path = ProjectSettings.globalize_path(tex_path)
	if not FileAccess.file_exists(abs_path):
		return null
	var img = Image.new()
	if img.load(abs_path) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	var tex = ImageTexture.create_from_image(img)
	_icon_cache[tex_path] = tex
	return tex

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
