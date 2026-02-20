extends CanvasLayer

const GC = preload("res://scripts/game_config.gd")
@onready var hotbar: HBoxContainer = $MarginContainer/HBoxContainer
var slot_panels: Array = []
var player: CharacterBody3D
var name_label: Label

const NUM_SLOTS = 9
var _icon_cache: Dictionary = {}

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	_create_name_label()
	_create_hotbar_slots()
	_update_hotbar()

func _create_name_label():
	name_label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	name_label.offset_left = -200
	name_label.offset_right = 200
	name_label.offset_top = -100
	name_label.offset_bottom = -82
	name_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.add_theme_constant_override("outline_size", 4)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	add_child(name_label)

func _create_hotbar_slots():
	for i in range(NUM_SLOTS):
		var panel = Panel.new()
		panel.custom_minimum_size = Vector2(56, 56)

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.5, 0.5, 0.5, 1.0)
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_left = 3
		style.corner_radius_bottom_right = 3
		panel.add_theme_stylebox_override("panel", style)

		var num_label = Label.new()
		num_label.text = str(i + 1)
		num_label.position = Vector2(3, 1)
		num_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.7))
		num_label.add_theme_font_size_override("font_size", 10)
		panel.add_child(num_label)

		# ColorRect (fallback pour les blocs sans texture)
		var color_rect = ColorRect.new()
		color_rect.size = Vector2(36, 36)
		color_rect.position = Vector2(10, 12)
		panel.add_child(color_rect)

		# TextureRect pour les icones (blocs et outils)
		var tex_rect = TextureRect.new()
		tex_rect.size = Vector2(36, 36)
		tex_rect.position = Vector2(10, 12)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex_rect.visible = false
		panel.add_child(tex_rect)

		var count_label = Label.new()
		count_label.text = "0"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.size = Vector2(48, 20)
		count_label.position = Vector2(4, 36)
		count_label.add_theme_color_override("font_color", Color.WHITE)
		count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
		count_label.add_theme_constant_override("shadow_offset_x", 1)
		count_label.add_theme_constant_override("shadow_offset_y", 1)
		count_label.add_theme_font_size_override("font_size", 14)
		count_label.add_theme_constant_override("outline_size", 3)
		count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
		panel.add_child(count_label)

		hotbar.add_child(panel)
		slot_panels.append({
			"panel": panel,
			"color_rect": color_rect,
			"tex_rect": tex_rect,
			"style": style,
			"count_label": count_label
		})

func _process(_delta):
	if player:
		_update_hotbar()

func _update_hotbar():
	if not player:
		return

	if name_label and player.selected_slot >= 0 and player.selected_slot < player.hotbar_slots.size():
		var tool_type = player._get_selected_tool()
		if tool_type != ToolRegistry.ToolType.NONE:
			name_label.text = ToolRegistry.get_tool_name(tool_type)
		else:
			var block_type = player.hotbar_slots[player.selected_slot]
			name_label.text = BlockRegistry.get_block_name(block_type)

	for i in range(min(slot_panels.size(), player.hotbar_slots.size())):
		var slot = slot_panels[i]
		var tool_type = ToolRegistry.ToolType.NONE
		if i < player.hotbar_tool_slots.size():
			tool_type = player.hotbar_tool_slots[i]

		if tool_type != ToolRegistry.ToolType.NONE:
			# Slot outil — afficher la texture d'item
			var tex = _load_item_icon(ToolRegistry.get_item_texture_path(tool_type))
			if tex:
				slot["tex_rect"].texture = tex
				slot["tex_rect"].visible = true
				slot["color_rect"].visible = false
			else:
				slot["color_rect"].color = Color(0.6, 0.55, 0.5, 1.0)
				slot["color_rect"].visible = true
				slot["tex_rect"].visible = false
			slot["count_label"].text = "1"
			slot["count_label"].add_theme_color_override("font_color", Color(1, 1, 1, 1))
			slot["count_label"].add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
		else:
			var block_type = player.hotbar_slots[i]
			var count = player.get_inventory_count(block_type)
			# Essayer d'afficher la texture du bloc (face top ou all)
			var block_tex = _load_block_icon(block_type)
			if block_tex:
				slot["tex_rect"].texture = block_tex
				slot["tex_rect"].visible = true
				slot["tex_rect"].modulate = Color(1,1,1,1) if count > 0 else Color(0.4, 0.4, 0.4, 0.6)
				slot["color_rect"].visible = false
			else:
				var color = BlockRegistry.get_block_color(block_type)
				slot["color_rect"].color = color if count > 0 else color * 0.35
				slot["color_rect"].visible = true
				slot["tex_rect"].visible = false
			slot["count_label"].text = str(count)
			if count == 0:
				slot["count_label"].add_theme_color_override("font_color", Color(0.4, 0.3, 0.3, 0.6))
				slot["count_label"].add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.3))
			else:
				slot["count_label"].add_theme_color_override("font_color", Color(1, 1, 1, 1))
				slot["count_label"].add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))

		if i == player.selected_slot:
			slot["style"].border_color = Color(1.0, 1.0, 0.5, 1.0)
			slot["style"].border_width_left = 3
			slot["style"].border_width_top = 3
			slot["style"].border_width_right = 3
			slot["style"].border_width_bottom = 3
		else:
			slot["style"].border_color = Color(0.5, 0.5, 0.5, 1.0)
			slot["style"].border_width_left = 2
			slot["style"].border_width_top = 2
			slot["style"].border_width_right = 2
			slot["style"].border_width_bottom = 2

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
	# Appliquer le tint si necessaire
	var tint = BlockRegistry.get_block_tint(block_type, "top")
	if tint != Color(1,1,1,1):
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c = img.get_pixel(x, y)
				img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	var tex = ImageTexture.create_from_image(img)
	_icon_cache[cache_key] = tex
	return tex
