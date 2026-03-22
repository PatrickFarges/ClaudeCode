# inventory_ui.gd v2.0.0
# Inventaire style Minecraft avec texture Faithful32 (inventory.png)
# Ouvert avec I — affiche tous les blocs disponibles dans une grille MC

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

# Texture content area (Faithful32 = 2x vanilla MC 176x166)
const TEX_W = 352  # pixels dans la texture
const TEX_H = 332

# Tous les blocs disponibles (meme liste que l'ancienne version)
const ALL_BLOCKS = [
	BlockRegistry.BlockType.DIRT, BlockRegistry.BlockType.GRASS,
	BlockRegistry.BlockType.DARK_GRASS, BlockRegistry.BlockType.STONE,
	BlockRegistry.BlockType.SAND, BlockRegistry.BlockType.GRAVEL,
	BlockRegistry.BlockType.WOOD, BlockRegistry.BlockType.LEAVES,
	BlockRegistry.BlockType.SNOW, BlockRegistry.BlockType.CACTUS,
	BlockRegistry.BlockType.PLANKS, BlockRegistry.BlockType.CRAFTING_TABLE,
	BlockRegistry.BlockType.BRICK, BlockRegistry.BlockType.SANDSTONE,
	BlockRegistry.BlockType.COAL_ORE, BlockRegistry.BlockType.IRON_ORE,
	BlockRegistry.BlockType.GOLD_ORE, BlockRegistry.BlockType.IRON_INGOT,
	BlockRegistry.BlockType.GOLD_INGOT, BlockRegistry.BlockType.FURNACE,
	BlockRegistry.BlockType.STONE_TABLE, BlockRegistry.BlockType.IRON_TABLE,
	BlockRegistry.BlockType.GOLD_TABLE, BlockRegistry.BlockType.COBBLESTONE,
	BlockRegistry.BlockType.DIAMOND_ORE, BlockRegistry.BlockType.COPPER_ORE,
	BlockRegistry.BlockType.SPRUCE_LOG, BlockRegistry.BlockType.BIRCH_LOG,
	BlockRegistry.BlockType.JUNGLE_LOG, BlockRegistry.BlockType.ACACIA_LOG,
	BlockRegistry.BlockType.DARK_OAK_LOG, BlockRegistry.BlockType.CHERRY_LOG,
	BlockRegistry.BlockType.SPRUCE_LEAVES, BlockRegistry.BlockType.BIRCH_LEAVES,
	BlockRegistry.BlockType.JUNGLE_LEAVES, BlockRegistry.BlockType.ACACIA_LEAVES,
	BlockRegistry.BlockType.DARK_OAK_LEAVES, BlockRegistry.BlockType.CHERRY_LEAVES,
	BlockRegistry.BlockType.ANDESITE, BlockRegistry.BlockType.GRANITE,
	BlockRegistry.BlockType.DIORITE, BlockRegistry.BlockType.DEEPSLATE,
	BlockRegistry.BlockType.CLAY, BlockRegistry.BlockType.PODZOL,
	BlockRegistry.BlockType.MOSS_BLOCK, BlockRegistry.BlockType.ICE,
	BlockRegistry.BlockType.GLASS, BlockRegistry.BlockType.TORCH,
	BlockRegistry.BlockType.LANTERN, BlockRegistry.BlockType.CHEST,
	BlockRegistry.BlockType.FARMLAND, BlockRegistry.BlockType.WHEAT_ITEM,
	BlockRegistry.BlockType.BREAD,
	BlockRegistry.BlockType.STONE_BRICKS,
	BlockRegistry.BlockType.OAK_STAIRS, BlockRegistry.BlockType.COBBLESTONE_STAIRS,
	BlockRegistry.BlockType.STONE_BRICK_STAIRS,
	BlockRegistry.BlockType.OAK_SLAB, BlockRegistry.BlockType.COBBLESTONE_SLAB,
	BlockRegistry.BlockType.STONE_SLAB,
	BlockRegistry.BlockType.OAK_DOOR, BlockRegistry.BlockType.IRON_DOOR,
	BlockRegistry.BlockType.OAK_FENCE, BlockRegistry.BlockType.GLASS_PANE,
	BlockRegistry.BlockType.LADDER, BlockRegistry.BlockType.OAK_TRAPDOOR,
	BlockRegistry.BlockType.IRON_BARS,
	BlockRegistry.BlockType.SHORT_GRASS, BlockRegistry.BlockType.FERN,
	BlockRegistry.BlockType.DANDELION, BlockRegistry.BlockType.POPPY,
	BlockRegistry.BlockType.CORNFLOWER,
]

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

	# Texture inventaire MC comme fond
	var inv_tex = load(GUI_DIR + "container/inventory.png") as Texture2D
	if not inv_tex:
		var img = Image.load_from_file(GUI_DIR + "container/inventory.png")
		if img:
			inv_tex = ImageTexture.create_from_image(img)

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

	# Creer un bouton invisible par slot
	for i in range(min(all_slots_pos.size(), ALL_BLOCKS.size())):
		var pos = all_slots_pos[i]
		var block_type = ALL_BLOCKS[i]

		var btn = Button.new()
		btn.set_anchors_preset(Control.PRESET_CENTER)
		btn.offset_left = pos.x
		btn.offset_right = pos.x + slot_px
		btn.offset_top = pos.y
		btn.offset_bottom = pos.y + slot_px
		btn.flat = true  # pas de fond de bouton (la texture MC fait le fond)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_on_slot_pressed.bind(block_type))
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
			"count_label": count_label,
			"block_type": block_type,
		})

	# Charger les icones
	_refresh_slots()

func _refresh_slots():
	for slot in _slot_buttons:
		var bt = slot["block_type"]
		var count = player.get_inventory_count(bt) if player else 0
		var tex = _load_block_icon(bt)
		slot["tex_rect"].texture = tex
		slot["tex_rect"].modulate = Color.WHITE if count > 0 else Color(0.4, 0.4, 0.4, 0.6)
		slot["count_label"].text = str(count) if count > 0 else ""

func open_inventory():
	is_open = true
	visible = true
	_refresh_slots()

func close_inventory():
	is_open = false
	visible = false

func _on_slot_pressed(block_type: BlockRegistry.BlockType):
	if player and player.has_method("assign_hotbar_slot"):
		player.assign_hotbar_slot(player.selected_slot, block_type)
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
