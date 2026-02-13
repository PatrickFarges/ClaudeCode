extends CanvasLayer

# Écran de crafting — ouvert avec C
# Liste de recettes, clic pour crafter

var player: CharacterBody3D = null
var is_open: bool = false
var current_tier: int = 0
var has_furnace: bool = false

# UI elements
var background: ColorRect
var panel: PanelContainer
var title_label: Label
var station_label: Label
var scroll: ScrollContainer
var recipe_list: VBoxContainer
var hint_label: Label
var recipe_rows: Array = []  # Array of {container, button, recipe, ...}

func _ready():
	layer = 10
	visible = false
	add_to_group("crafting_ui")
	
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	
	_build_ui()

func _build_ui():
	# ============================================================
	# FOND SOMBRE
	# ============================================================
	background = ColorRect.new()
	background.color = Color(0, 0, 0, 0.6)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)
	
	# ============================================================
	# PANNEAU CENTRAL
	# ============================================================
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 420)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.5, 0.5, 0.6, 0.8)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(content_vbox)
	
	# ============================================================
	# TITRE
	# ============================================================
	title_label = Label.new()
	title_label.text = Locale.tr_ui("crafting_title")
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(1, 0.9, 0.7, 1))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_vbox.add_child(title_label)
	
	# Label station
	station_label = Label.new()
	station_label.text = Locale.tr_ui("craft_hand")
	station_label.add_theme_font_size_override("font_size", 14)
	station_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9, 1))
	station_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_vbox.add_child(station_label)
	
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	content_vbox.add_child(sep)
	
	# ============================================================
	# LISTE SCROLLABLE DES RECETTES
	# ============================================================
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(scroll)
	
	recipe_list = VBoxContainer.new()
	recipe_list.add_theme_constant_override("separation", 4)
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(recipe_list)
	
	# ============================================================
	# INSTRUCTIONS
	# ============================================================
	var sep2 = HSeparator.new()
	sep2.add_theme_constant_override("separation", 6)
	content_vbox.add_child(sep2)
	
	hint_label = Label.new()
	hint_label.text = Locale.tr_ui("craft_hint")
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_vbox.add_child(hint_label)

func open_crafting(tier: int = 0, furnace: bool = false):
	"""Ouvrir l'écran de crafting"""
	is_open = true
	current_tier = tier
	has_furnace = furnace
	visible = true
	_rebuild_recipe_list()

func close_crafting():
	"""Fermer l'écran de crafting"""
	is_open = false
	visible = false

func _rebuild_recipe_list():
	"""Reconstruire la liste des recettes"""
	# Vider la liste
	for child in recipe_list.get_children():
		child.queue_free()
	recipe_rows.clear()
	
	var recipes = CraftRegistry.get_all_recipes()

	# Mettre à jour le label de station
	if has_furnace:
		station_label.text = Locale.tr_ui("craft_furnace")
		station_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3, 1))
	elif current_tier >= 4:
		station_label.text = Locale.tr_ui("craft_tier_4")
		station_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3, 1))
	elif current_tier == 3:
		station_label.text = Locale.tr_ui("craft_tier_3")
		station_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 1))
	elif current_tier == 2:
		station_label.text = Locale.tr_ui("craft_tier_2")
		station_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6, 1))
	elif current_tier == 1:
		station_label.text = Locale.tr_ui("craft_tier_1")
		station_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4, 1))
	else:
		station_label.text = Locale.tr_ui("craft_hand")
		station_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9, 1))

	# Mettre à jour le hint
	if current_tier == 0 and not has_furnace:
		hint_label.text = Locale.tr_ui("craft_hint_hand")
	else:
		hint_label.text = Locale.tr_ui("craft_hint_station")

	# Trier : craftables en premier, puis par disponibilité
	var sorted_recipes = recipes.duplicate()
	var inventory = player.get_all_inventory() if player else {}

	sorted_recipes.sort_custom(func(a, b):
		var can_a = CraftRegistry.can_craft(a, inventory)
		var can_b = CraftRegistry.can_craft(b, inventory)
		var avail_a = CraftRegistry.is_recipe_available(a, current_tier, has_furnace)
		var avail_b = CraftRegistry.is_recipe_available(b, current_tier, has_furnace)
		# Craftables et disponibles d'abord
		if (can_a and avail_a) != (can_b and avail_b):
			return can_a and avail_a
		if avail_a != avail_b:
			return avail_a
		return false
	)
	
	for recipe in sorted_recipes:
		_add_recipe_row(recipe)

func _add_recipe_row(recipe: Dictionary):
	"""Ajouter une ligne de recette"""
	var inventory = player.get_all_inventory() if player else {}
	var can_craft = CraftRegistry.can_craft(recipe, inventory)
	var station_available = CraftRegistry.is_recipe_available(recipe, current_tier, has_furnace)
	var is_craftable = can_craft and station_available
	
	# Container horizontal pour la ligne
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Style fond de la ligne
	var row_panel = PanelContainer.new()
	var row_style = StyleBoxFlat.new()
	row_style.corner_radius_top_left = 4
	row_style.corner_radius_top_right = 4
	row_style.corner_radius_bottom_left = 4
	row_style.corner_radius_bottom_right = 4
	row_style.content_margin_left = 10
	row_style.content_margin_right = 10
	row_style.content_margin_top = 6
	row_style.content_margin_bottom = 6
	
	if is_craftable:
		row_style.bg_color = Color(0.18, 0.22, 0.18, 1.0)
		row_style.border_color = Color(0.4, 0.6, 0.4, 0.6)
	elif station_available:
		row_style.bg_color = Color(0.18, 0.18, 0.18, 1.0)
		row_style.border_color = Color(0.35, 0.35, 0.35, 0.4)
	else:
		row_style.bg_color = Color(0.15, 0.15, 0.17, 0.6)
		row_style.border_color = Color(0.3, 0.3, 0.35, 0.3)
	
	row_style.border_width_left = 1
	row_style.border_width_top = 1
	row_style.border_width_right = 1
	row_style.border_width_bottom = 1
	row_panel.add_theme_stylebox_override("panel", row_style)
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.add_child(row)
	recipe_list.add_child(row_panel)
	
	# === Couleur de l'output ===
	var output_color = ColorRect.new()
	output_color.custom_minimum_size = Vector2(28, 28)
	output_color.color = BlockRegistry.get_block_color(recipe["output_type"])
	if not is_craftable:
		output_color.color = output_color.color * 0.4
	output_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(output_color)
	
	# === Nom + quantité output ===
	var output_label = Label.new()
	output_label.text = "%s  x%d" % [Locale.tr_recipe(recipe["name"]), recipe["output_count"]]
	output_label.add_theme_font_size_override("font_size", 15)
	output_label.custom_minimum_size = Vector2(160, 0)
	output_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_craftable:
		output_label.add_theme_color_override("font_color", Color(1, 1, 0.9, 1))
	elif station_available:
		output_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	else:
		output_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45, 1))
	row.add_child(output_label)
	
	# === Flèche ===
	var arrow = Label.new()
	arrow.text = "←"
	arrow.add_theme_font_size_override("font_size", 14)
	arrow.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	
	# === Ingrédients ===
	var ingredients_box = HBoxContainer.new()
	ingredients_box.add_theme_constant_override("separation", 4)
	ingredients_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ingredients_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ingredients_box)
	
	for input_item in recipe["inputs"]:
		var block_type = input_item[0]
		var required = input_item[1]
		var have = inventory.get(block_type, 0)
		var ing_name = BlockRegistry.get_block_name(block_type)
		
		# Couleur de l'ingrédient
		var ing_color = ColorRect.new()
		ing_color.custom_minimum_size = Vector2(14, 14)
		ing_color.color = BlockRegistry.get_block_color(block_type)
		if not is_craftable:
			ing_color.color = ing_color.color * 0.5
		ing_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ingredients_box.add_child(ing_color)
		
		# Nom + quantité de l'ingrédient (TOUJOURS visible)
		var ing_label = Label.new()
		ing_label.text = "%s %d/%d" % [ing_name, min(have, required), required]
		ing_label.add_theme_font_size_override("font_size", 13)
		ing_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if have >= required:
			ing_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5, 1))
		else:
			ing_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4, 1))
		ingredients_box.add_child(ing_label)
	
	# === Bouton Crafter ===
	var craft_btn = Button.new()
	craft_btn.custom_minimum_size = Vector2(80, 30)
	craft_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	if is_craftable:
		craft_btn.text = Locale.tr_ui("craft_btn")
		craft_btn.disabled = false
		
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.25, 0.45, 0.25, 1.0)
		btn_style.corner_radius_top_left = 4
		btn_style.corner_radius_top_right = 4
		btn_style.corner_radius_bottom_left = 4
		btn_style.corner_radius_bottom_right = 4
		btn_style.border_width_left = 1
		btn_style.border_width_top = 1
		btn_style.border_width_right = 1
		btn_style.border_width_bottom = 1
		btn_style.border_color = Color(0.4, 0.7, 0.4, 0.8)
		craft_btn.add_theme_stylebox_override("normal", btn_style)
		
		var btn_hover = btn_style.duplicate()
		btn_hover.bg_color = Color(0.3, 0.55, 0.3, 1.0)
		btn_hover.border_color = Color(0.5, 0.8, 0.5, 1.0)
		craft_btn.add_theme_stylebox_override("hover", btn_hover)
		
		var btn_pressed = btn_style.duplicate()
		btn_pressed.bg_color = Color(0.2, 0.35, 0.2, 1.0)
		craft_btn.add_theme_stylebox_override("pressed", btn_pressed)
		
		craft_btn.add_theme_color_override("font_color", Color(0.9, 1, 0.9, 1))
		craft_btn.add_theme_font_size_override("font_size", 13)
	elif not station_available:
		var need_key = CraftRegistry.get_recipe_station_label(recipe)
		craft_btn.text = Locale.tr_ui(need_key) if need_key != "" else "?"
		craft_btn.disabled = true
		craft_btn.add_theme_color_override("font_color", Color(0.5, 0.45, 0.3, 1))
		craft_btn.add_theme_font_size_override("font_size", 11)
	else:
		craft_btn.text = Locale.tr_ui("craft_missing")
		craft_btn.disabled = true
		craft_btn.add_theme_color_override("font_color", Color(0.5, 0.4, 0.4, 1))
		craft_btn.add_theme_font_size_override("font_size", 12)
	
	craft_btn.pressed.connect(_on_craft_pressed.bind(recipe))
	row.add_child(craft_btn)
	
	recipe_rows.append({
		"panel": row_panel,
		"button": craft_btn,
		"recipe": recipe
	})

func _on_craft_pressed(recipe: Dictionary):
	"""Crafter une recette"""
	if not player:
		return
	
	var inventory = player.get_all_inventory()
	if not CraftRegistry.can_craft(recipe, inventory):
		return
	
	# Retirer les ingrédients
	for input_item in recipe["inputs"]:
		var block_type = input_item[0]
		var count = input_item[1]
		player._remove_from_inventory(block_type, count)
	
	# Ajouter le résultat
	player._add_to_inventory(recipe["output_type"], recipe["output_count"])
	
	# Son de craft réussi
	var audio = get_tree().get_first_node_in_group("audio_manager")
	if audio:
		audio.play_craft_success()
	
	# Rebuild la liste pour mettre à jour les quantités
	_rebuild_recipe_list()

func _process(_delta):
	# Pas besoin de mise à jour continue — on rebuild quand on craft
	pass
