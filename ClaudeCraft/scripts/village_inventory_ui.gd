extends CanvasLayer

# Inventaire du village — ouvert avec F1
# Affiche le stockpile partagé du village, la phase actuelle, le tier d'outils
# Structuré pour supporter plusieurs villages (village_id)

var is_open: bool = false
var village_manager = null
var village_id: int = 0  # Pour supporter plusieurs villages à l'avenir

var background: ColorRect
var panel: PanelContainer
var title_label: Label
var phase_label: Label
var tier_label: Label
var villagers_label: Label
var tasks_label: Label
var stockpile_container: VBoxContainer
var scroll: ScrollContainer
var _update_timer: float = 0.0

func _ready():
	visible = false
	add_to_group("village_inventory_ui")
	_build_ui()

func _process(delta):
	if not is_open:
		return
	_update_timer += delta
	if _update_timer >= 0.5:
		_update_timer = 0.0
		_refresh_contents()

func _build_ui():
	# Fond semi-transparent
	background = ColorRect.new()
	background.color = Color(0, 0, 0, 0.6)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# Panneau central
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(460, 100)
	panel.size = Vector2(500, 600)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.18, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.5, 0.9, 0.8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Titre
	title_label = Label.new()
	title_label.text = "Inventaire du Village"
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	# Séparateur
	var sep1 = HSeparator.new()
	sep1.add_theme_constant_override("separation", 4)
	vbox.add_child(sep1)

	# Phase
	phase_label = Label.new()
	phase_label.add_theme_font_size_override("font_size", 16)
	phase_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(phase_label)

	# Tier
	tier_label = Label.new()
	tier_label.add_theme_font_size_override("font_size", 16)
	tier_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(tier_label)

	# Villageois
	villagers_label = Label.new()
	villagers_label.add_theme_font_size_override("font_size", 14)
	villagers_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7))
	vbox.add_child(villagers_label)

	# Tâches
	tasks_label = Label.new()
	tasks_label.add_theme_font_size_override("font_size", 14)
	tasks_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7))
	vbox.add_child(tasks_label)

	# Séparateur
	var sep2 = HSeparator.new()
	sep2.add_theme_constant_override("separation", 4)
	vbox.add_child(sep2)

	# Label "Ressources"
	var res_label = Label.new()
	res_label.text = "Ressources"
	res_label.add_theme_font_size_override("font_size", 18)
	res_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	vbox.add_child(res_label)

	# Scroll pour la liste des ressources
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	stockpile_container = VBoxContainer.new()
	stockpile_container.add_theme_constant_override("separation", 4)
	scroll.add_child(stockpile_container)

	# Hint
	var hint = Label.new()
	hint.text = "F1 pour fermer"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

func open_inventory():
	village_manager = get_node_or_null("/root/VillageManager")
	is_open = true
	visible = true
	_refresh_contents()

func close_inventory():
	is_open = false
	visible = false

func _refresh_contents():
	if not village_manager:
		return

	var phase_names = ["Phase 0 — Bootstrap", "Phase 1 — Age du Bois", "Phase 2 — Age de la Pierre", "Phase 3 — Age du Fer"]
	phase_label.text = phase_names[village_manager.village_phase]

	var tier_names = ["Mains nues (x1.0)", "Outils bois (x1.67)", "Outils pierre (x2.0)", "Outils fer (x2.5)"]
	tier_label.text = "Outils : " + tier_names[village_manager.village_tool_tier]

	villagers_label.text = "Villageois : %d actifs" % village_manager.villagers.size()
	tasks_label.text = "Tâches en attente : %d" % village_manager.task_queue.size()

	# Nettoyer les entrées précédentes
	for child in stockpile_container.get_children():
		child.queue_free()

	# Afficher chaque ressource du stockpile
	var sorted_resources = []
	for bt in village_manager.stockpile:
		var count = village_manager.stockpile[bt]
		if count > 0:
			sorted_resources.append([bt, count])

	if sorted_resources.size() == 0:
		var empty_label = Label.new()
		empty_label.text = "  (aucune ressource)"
		empty_label.add_theme_font_size_override("font_size", 14)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		stockpile_container.add_child(empty_label)
		return

	# Trier par quantité décroissante
	sorted_resources.sort_custom(func(a, b): return a[1] > b[1])

	for res in sorted_resources:
		var bt = res[0]
		var count = res[1]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		# Icône couleur du bloc
		var color_rect = ColorRect.new()
		color_rect.custom_minimum_size = Vector2(16, 16)
		var block_color = BlockRegistry.get_block_color(bt as BlockRegistry.BlockType)
		color_rect.color = block_color
		row.add_child(color_rect)

		# Nom du bloc
		var name_label = Label.new()
		name_label.text = BlockRegistry.get_block_name(bt as BlockRegistry.BlockType)
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		# Quantité
		var count_label = Label.new()
		count_label.text = "x%d" % count
		count_label.add_theme_font_size_override("font_size", 15)
		count_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		row.add_child(count_label)

		stockpile_container.add_child(row)
