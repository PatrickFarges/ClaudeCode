# crafting_ui.gd v2.1.0
# UI de crafting style Minecraft avec texture crafting_table.png Faithful32
# Grille 3x3, slot output, liste de recettes dans les slots inventaire

extends CanvasLayer

const GC = preload("res://scripts/game_config.gd")
const GUI_DIR = "res://TexturesPack/Faithful32/assets/minecraft/textures/gui/"
const GUI_SCALE = 2

var player: CharacterBody3D = null
var is_open: bool = false
var current_tier: int = 0
var has_furnace: bool = false
var _icon_cache: Dictionary = {}

# UI nodes
var _background: ColorRect = null
var _craft_texture: TextureRect = null
var _title_label: Label = null
var _station_label: Label = null
var _grid_slots: Array = []       # 9 TextureRect pour la grille 3x3
var _grid_count_labels: Array = [] # 9 Labels compteurs pour la grille
var _grid_hover_buttons: Array = [] # 9 Buttons invisibles pour hover grille
var _output_slot: TextureRect = null
var _output_count_label: Label = null
var _recipe_buttons: Array = []   # boutons dans les slots inventaire
var _selected_recipe: Dictionary = {}
var _tooltip_label: Label = null   # nom de l'item au survol
var _hint_label: Label = null      # instruction en bas
var _output_name_label: Label = null  # nom de l'output

# Texture content area (meme que inventory.png)
const TEX_W = 352
const TEX_H = 332

# Slot positions in Faithful32 crafting_table.png
const CRAFT_GRID_X = 60
const CRAFT_GRID_Y = 34
const CRAFT_SLOT_STEP = 36
const OUTPUT_X = 248
const OUTPUT_Y = 70
const INV_X = 14
const INV_Y = 166
const HOTBAR_Y = 282
const SLOT_SIZE = 36

func _ready():
	layer = 10
	visible = false
	add_to_group("crafting_ui")
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	_build_ui()

func _build_ui():
	# Fond sombre
	_background = ColorRect.new()
	_background.color = Color(0, 0, 0, 0.65)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_background)

	# Texture crafting table MC (croppee a 352x332)
	var craft_img = Image.load_from_file(GUI_DIR + "container/crafting_table.png")
	var craft_tex: ImageTexture = null
	if craft_img:
		var cropped = craft_img.get_region(Rect2i(0, 0, TEX_W, TEX_H))
		craft_tex = ImageTexture.create_from_image(cropped)

	_craft_texture = TextureRect.new()
	_craft_texture.texture = craft_tex
	_craft_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_craft_texture.set_anchors_preset(Control.PRESET_CENTER)
	var disp_w = TEX_W * GUI_SCALE
	var disp_h = TEX_H * GUI_SCALE
	_craft_texture.offset_left = -disp_w / 2
	_craft_texture.offset_right = disp_w / 2
	_craft_texture.offset_top = -disp_h / 2
	_craft_texture.offset_bottom = disp_h / 2
	_craft_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_craft_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_craft_texture)

	var tex_left = -disp_w / 2.0
	var tex_top = -disp_h / 2.0
	var icon_size = 28 * GUI_SCALE
	var slot_px = SLOT_SIZE * GUI_SCALE
	var pad = (slot_px - icon_size) / 2.0

	# Titre
	_title_label = Label.new()
	_title_label.text = "Crafting"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.set_anchors_preset(Control.PRESET_CENTER)
	_title_label.offset_left = -150
	_title_label.offset_right = 150
	_title_label.offset_top = tex_top + 6 * GUI_SCALE
	_title_label.offset_bottom = tex_top + 20 * GUI_SCALE
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25, 1))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	# Station label (sous le titre)
	_station_label = Label.new()
	_station_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_station_label.set_anchors_preset(Control.PRESET_CENTER)
	_station_label.offset_left = -200
	_station_label.offset_right = 200
	_station_label.offset_top = tex_top - 24
	_station_label.offset_bottom = tex_top - 4
	_station_label.add_theme_font_size_override("font_size", 14)
	_station_label.add_theme_color_override("font_color", Color(1, 0.9, 0.7, 1))
	_station_label.add_theme_color_override("font_shadow_color", Color(0.15, 0.15, 0.15, 1))
	_station_label.add_theme_constant_override("shadow_offset_x", 2)
	_station_label.add_theme_constant_override("shadow_offset_y", 2)
	_station_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_station_label)

	# Grille craft 3x3 (affichage seulement — montre les ingredients de la recette selectionnee)
	_grid_count_labels = []
	_grid_hover_buttons = []
	for r in range(3):
		for c in range(3):
			var sx = tex_left + (CRAFT_GRID_X + c * CRAFT_SLOT_STEP) * GUI_SCALE
			var sy = tex_top + (CRAFT_GRID_Y + r * CRAFT_SLOT_STEP) * GUI_SCALE
			var tex_rect = TextureRect.new()
			tex_rect.set_anchors_preset(Control.PRESET_CENTER)
			tex_rect.offset_left = sx + pad
			tex_rect.offset_right = sx + pad + icon_size
			tex_rect.offset_top = sy + pad
			tex_rect.offset_bottom = sy + pad + icon_size
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(tex_rect)
			_grid_slots.append(tex_rect)
			# Bouton invisible pour capter le hover sur le slot de la grille
			var grid_btn = Button.new()
			grid_btn.set_anchors_preset(Control.PRESET_CENTER)
			grid_btn.offset_left = sx
			grid_btn.offset_right = sx + slot_px
			grid_btn.offset_top = sy
			grid_btn.offset_bottom = sy + slot_px
			grid_btn.flat = true
			var grid_idx = r * 3 + c
			grid_btn.mouse_entered.connect(_on_grid_hover.bind(grid_idx))
			grid_btn.mouse_exited.connect(_on_slot_unhover)
			add_child(grid_btn)
			_grid_hover_buttons.append(grid_btn)
			# Label compteur (ex: "x4" en bas a droite du slot)
			var grid_count = Label.new()
			grid_count.set_anchors_preset(Control.PRESET_CENTER)
			grid_count.offset_left = sx + slot_px - 28 * GUI_SCALE
			grid_count.offset_right = sx + slot_px - 2
			grid_count.offset_top = sy + slot_px - 14 * GUI_SCALE
			grid_count.offset_bottom = sy + slot_px
			grid_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid_count.add_theme_font_size_override("font_size", 14)
			grid_count.add_theme_color_override("font_color", Color.WHITE)
			grid_count.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
			grid_count.add_theme_constant_override("shadow_offset_x", 2)
			grid_count.add_theme_constant_override("shadow_offset_y", 2)
			grid_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(grid_count)
			_grid_count_labels.append(grid_count)

	# Slot output
	var ox = tex_left + OUTPUT_X * GUI_SCALE
	var oy = tex_top + OUTPUT_Y * GUI_SCALE
	_output_slot = TextureRect.new()
	_output_slot.set_anchors_preset(Control.PRESET_CENTER)
	_output_slot.offset_left = ox + pad
	_output_slot.offset_right = ox + pad + icon_size
	_output_slot.offset_top = oy + pad
	_output_slot.offset_bottom = oy + pad + icon_size
	_output_slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_output_slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_output_slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_output_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_output_slot)

	_output_count_label = Label.new()
	_output_count_label.set_anchors_preset(Control.PRESET_CENTER)
	_output_count_label.offset_left = ox + slot_px - 26 * GUI_SCALE
	_output_count_label.offset_right = ox + slot_px - 2
	_output_count_label.offset_top = oy + slot_px - 14 * GUI_SCALE
	_output_count_label.offset_bottom = oy + slot_px
	_output_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_output_count_label.add_theme_font_size_override("font_size", 14)
	_output_count_label.add_theme_color_override("font_color", Color.WHITE)
	_output_count_label.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
	_output_count_label.add_theme_constant_override("shadow_offset_x", 2)
	_output_count_label.add_theme_constant_override("shadow_offset_y", 2)
	_output_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_output_count_label)

	# Bouton craft sur le slot output (clic = crafter)
	var output_btn = Button.new()
	output_btn.set_anchors_preset(Control.PRESET_CENTER)
	output_btn.offset_left = ox
	output_btn.offset_right = ox + slot_px
	output_btn.offset_top = oy
	output_btn.offset_bottom = oy + slot_px
	output_btn.flat = true
	output_btn.pressed.connect(_on_craft_output_pressed)
	add_child(output_btn)

	# Slots inventaire/hotbar = recettes disponibles (cliquables)
	var all_slots: Array = []
	for row in range(3):
		for col in range(9):
			var sx = tex_left + (INV_X + col * SLOT_SIZE) * GUI_SCALE
			var sy = tex_top + (INV_Y + row * SLOT_SIZE) * GUI_SCALE
			all_slots.append(Vector2(sx, sy))
	for col in range(9):
		var sx = tex_left + (INV_X + col * SLOT_SIZE) * GUI_SCALE
		var sy = tex_top + HOTBAR_Y * GUI_SCALE
		all_slots.append(Vector2(sx, sy))

	for i in range(all_slots.size()):
		var pos = all_slots[i]
		var btn = Button.new()
		btn.set_anchors_preset(Control.PRESET_CENTER)
		btn.offset_left = pos.x
		btn.offset_right = pos.x + slot_px
		btn.offset_top = pos.y
		btn.offset_bottom = pos.y + slot_px
		btn.flat = true
		btn.pressed.connect(_on_recipe_slot_pressed.bind(i))
		add_child(btn)

		var tex_rect = TextureRect.new()
		tex_rect.set_anchors_preset(Control.PRESET_CENTER)
		tex_rect.offset_left = pos.x + pad
		tex_rect.offset_right = pos.x + pad + icon_size
		tex_rect.offset_top = pos.y + pad
		tex_rect.offset_bottom = pos.y + pad + icon_size
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex_rect)

		# Fond semi-transparent pour le nom
		var name_bg = ColorRect.new()
		name_bg.set_anchors_preset(Control.PRESET_CENTER)
		name_bg.offset_left = pos.x + 1
		name_bg.offset_right = pos.x + slot_px - 1
		name_bg.offset_top = pos.y + 1
		name_bg.offset_bottom = pos.y + slot_px - 1
		name_bg.color = Color(0, 0, 0, 0.45)
		name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(name_bg)

		# Nom de l'item sur le slot
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
		count_label.offset_left = pos.x + slot_px - 26 * GUI_SCALE
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

		_recipe_buttons.append({
			"button": btn,
			"tex_rect": tex_rect,
			"name_bg": name_bg,
			"name_label": name_label,
			"count_label": count_label,
			"recipe": {},
		})

	# Nom de l'output (au-dessus du slot output)
	_output_name_label = Label.new()
	_output_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_output_name_label.set_anchors_preset(Control.PRESET_CENTER)
	var out_cx = tex_left + (OUTPUT_X + SLOT_SIZE / 2) * GUI_SCALE
	_output_name_label.offset_left = out_cx - 80
	_output_name_label.offset_right = out_cx + 80
	_output_name_label.offset_top = tex_top + OUTPUT_Y * GUI_SCALE - 18
	_output_name_label.offset_bottom = tex_top + OUTPUT_Y * GUI_SCALE - 2
	_output_name_label.add_theme_font_size_override("font_size", 12)
	_output_name_label.add_theme_color_override("font_color", Color(1, 1, 0.8, 1))
	_output_name_label.add_theme_color_override("font_shadow_color", Color(0.15, 0.15, 0.15, 1))
	_output_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_output_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_output_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_output_name_label)

	# Tooltip flottant (suit la souris)
	_tooltip_label = Label.new()
	_tooltip_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tooltip_label.add_theme_font_size_override("font_size", 14)
	_tooltip_label.add_theme_color_override("font_color", Color.WHITE)
	_tooltip_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 1))
	_tooltip_label.add_theme_constant_override("shadow_offset_x", 2)
	_tooltip_label.add_theme_constant_override("shadow_offset_y", 2)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.visible = false
	# Fond du tooltip
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

	# Hint en bas
	_hint_label = Label.new()
	_hint_label.text = "Cliquer une recette pour la selectionner, puis cliquer l'output pour crafter"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.set_anchors_preset(Control.PRESET_CENTER)
	_hint_label.offset_left = -disp_w / 2
	_hint_label.offset_right = disp_w / 2
	_hint_label.offset_top = disp_h / 2 + 6
	_hint_label.offset_bottom = disp_h / 2 + 24
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7, 0.8))
	_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_label)

	# Connecter le hover sur les boutons recettes
	for i in range(_recipe_buttons.size()):
		var btn = _recipe_buttons[i]["button"]
		btn.mouse_entered.connect(_on_recipe_hover.bind(i))
		btn.mouse_exited.connect(_on_slot_unhover)

func _on_grid_hover(grid_index: int):
	if _selected_recipe.is_empty():
		return
	var inputs: Array = _selected_recipe.get("inputs", [])
	if grid_index < inputs.size():
		var block_type = inputs[grid_index][0]
		var count = inputs[grid_index][1]
		var have = player.get_inventory_count(block_type) if player else 0
		var name = BlockRegistry.get_block_name(block_type)
		_tooltip_label.text = "%s (%d/%d)" % [name, min(have, count), count]
		_tooltip_label.visible = true
	else:
		_tooltip_label.visible = false

func _on_recipe_hover(index: int):
	if index < _recipe_buttons.size():
		var slot = _recipe_buttons[index]
		if not slot["recipe"].is_empty():
			var recipe = slot["recipe"]
			var name = BlockRegistry.get_block_name(recipe["output_type"])
			_tooltip_label.text = name
			_tooltip_label.visible = true

func _on_slot_unhover():
	_tooltip_label.visible = false

func open_crafting(tier: int = 0, furnace: bool = false):
	is_open = true
	current_tier = tier
	has_furnace = furnace
	visible = true
	_update_station_label()
	_populate_recipes()

func close_crafting():
	is_open = false
	visible = false

func _update_station_label():
	if has_furnace:
		_station_label.text = Locale.tr_ui("craft_furnace")
	elif current_tier >= 4:
		_station_label.text = Locale.tr_ui("craft_tier_4")
	elif current_tier == 3:
		_station_label.text = Locale.tr_ui("craft_tier_3")
	elif current_tier == 2:
		_station_label.text = Locale.tr_ui("craft_tier_2")
	elif current_tier == 1:
		_station_label.text = Locale.tr_ui("craft_tier_1")
	else:
		_station_label.text = Locale.tr_ui("craft_hand")

func _populate_recipes():
	var recipes = CraftRegistry.get_all_recipes()
	var inventory = player.get_all_inventory() if player else {}

	# Filtrer les recettes disponibles pour cette station
	var filtered: Array = []
	for recipe in recipes:
		if CraftRegistry.is_recipe_available(recipe, current_tier, has_furnace):
			filtered.append(recipe)

	# Trier : craftables en premier
	filtered.sort_custom(func(a, b):
		var can_a = CraftRegistry.can_craft(a, inventory)
		var can_b = CraftRegistry.can_craft(b, inventory)
		if can_a != can_b:
			return can_a
		return false
	)

	# Remplir les slots avec les recettes
	for i in range(_recipe_buttons.size()):
		var slot = _recipe_buttons[i]
		if i < filtered.size():
			var recipe = filtered[i]
			slot["recipe"] = recipe
			var output_tex = _load_block_icon(recipe["output_type"])
			slot["tex_rect"].texture = output_tex
			var can_do = CraftRegistry.can_craft(recipe, inventory)
			slot["tex_rect"].modulate = Color.WHITE if can_do else Color(0.4, 0.4, 0.4, 0.6)
			# Afficher le nombre en stock de l'output
			var have = inventory.get(recipe["output_type"], 0)
			slot["count_label"].text = str(have) if have > 0 else ""
			# Nom de l'item sur le slot
			var item_name = BlockRegistry.get_block_name(recipe["output_type"])
			slot["name_label"].text = item_name
			slot["name_bg"].visible = true
			slot["name_label"].visible = true
			if can_do:
				slot["name_bg"].color = Color(0, 0, 0, 0.45)
				slot["name_label"].add_theme_color_override("font_color", Color.WHITE)
			else:
				slot["name_bg"].color = Color(0, 0, 0, 0.3)
				slot["name_label"].add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.6))
			slot["button"].visible = true
		else:
			slot["recipe"] = {}
			slot["tex_rect"].texture = null
			slot["count_label"].text = ""
			slot["name_label"].text = ""
			slot["name_bg"].visible = false
			slot["name_label"].visible = false
			slot["button"].visible = true

	# Selectionner la premiere recette craftable
	_selected_recipe = {}
	for recipe in filtered:
		if CraftRegistry.can_craft(recipe, inventory):
			_selected_recipe = recipe
			break
	if _selected_recipe.is_empty() and not filtered.is_empty():
		_selected_recipe = filtered[0]
	_update_craft_preview()

func _on_recipe_slot_pressed(index: int):
	if index < _recipe_buttons.size():
		var slot = _recipe_buttons[index]
		if not slot["recipe"].is_empty():
			_selected_recipe = slot["recipe"]
			_update_craft_preview()

func _update_craft_preview():
	# Vider la grille
	for i in range(9):
		_grid_slots[i].texture = null
		if i < _grid_count_labels.size():
			_grid_count_labels[i].text = ""
	_output_slot.texture = null
	_output_count_label.text = ""

	if _selected_recipe.is_empty():
		return

	# Afficher les ingredients dans la grille 3x3
	var inputs: Array = _selected_recipe.get("inputs", [])
	for i in range(min(inputs.size(), 9)):
		var block_type = inputs[i][0]
		var count = inputs[i][1]
		_grid_slots[i].texture = _load_block_icon(block_type)
		var have = player.get_inventory_count(block_type) if player else 0
		_grid_slots[i].modulate = Color(0.5, 1.0, 0.5, 1) if have >= count else Color(1.0, 0.4, 0.4, 1)
		# Compteur : "have/need" (ex: "4/6") avec nom abrege
		if i < _grid_count_labels.size():
			var ing_name = BlockRegistry.get_block_name(block_type)
			_grid_count_labels[i].text = "%d/%d" % [min(have, count), count]
			_grid_count_labels[i].add_theme_color_override("font_color",
				Color(0.5, 1.0, 0.5, 1) if have >= count else Color(1.0, 0.5, 0.5, 1))
			_grid_count_labels[i].tooltip_text = ing_name

	# Afficher l'output
	_output_slot.texture = _load_block_icon(_selected_recipe["output_type"])
	var inventory = player.get_all_inventory() if player else {}
	var can_craft = CraftRegistry.can_craft(_selected_recipe, inventory)
	_output_slot.modulate = Color.WHITE if can_craft else Color(0.4, 0.4, 0.4, 0.6)
	var oc = _selected_recipe["output_count"]
	_output_count_label.text = "x%d" % oc if oc > 1 else ""
	# Nom de l'output
	var output_name = BlockRegistry.get_block_name(_selected_recipe["output_type"])
	_output_name_label.text = output_name

func _on_craft_output_pressed():
	if _selected_recipe.is_empty() or not player:
		return
	var inventory = player.get_all_inventory()
	if not CraftRegistry.can_craft(_selected_recipe, inventory):
		return
	# Retirer les ingredients
	for input_item in _selected_recipe["inputs"]:
		player._remove_from_inventory(input_item[0], input_item[1])
	# Ajouter le resultat
	player._add_to_inventory(_selected_recipe["output_type"], _selected_recipe["output_count"])
	# Son
	var audio = get_tree().get_first_node_in_group("audio_manager")
	if audio:
		audio.play_craft_success()
	# Refresh
	_populate_recipes()

func _process(_delta):
	if _tooltip_label and _tooltip_label.visible:
		var mpos = get_viewport().get_mouse_position()
		_tooltip_label.offset_left = mpos.x + 16
		_tooltip_label.offset_top = mpos.y - 10
		_tooltip_label.offset_right = mpos.x + 250
		_tooltip_label.offset_bottom = mpos.y + 16

# ============================================================
# ICON LOADING
# ============================================================
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
