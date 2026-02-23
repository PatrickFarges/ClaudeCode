extends CanvasLayer

# Inventaire du village — ouvert avec F1
# Affiche le stockpile partagé du village, la phase actuelle, le tier d'outils,
# la population, la faim, les fermes, les bâtiments et le prochain objectif.

var is_open: bool = false
var village_manager = null
var village_id: int = 0  # Pour supporter plusieurs villages à l'avenir

var background: ColorRect
var panel: PanelContainer
var title_label: Label
var phase_label: Label
var tier_label: Label
var pop_label: Label
var tasks_label: Label
var farm_label: Label
var buildings_label: Label
var objective_label: Label
var stockpile_container: VBoxContainer
var villager_container: VBoxContainer
var scroll: ScrollContainer
var scroll_villagers: ScrollContainer
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

	# Panneau à droite, occupant toute la hauteur utile
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(420, 20)
	panel.size = Vector2(560, 760)
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
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Titre
	title_label = Label.new()
	title_label.text = "Gestion du Village"
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	# Séparateur
	vbox.add_child(_make_separator())

	# Phase
	phase_label = Label.new()
	phase_label.add_theme_font_size_override("font_size", 16)
	phase_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(phase_label)

	# Tier
	tier_label = Label.new()
	tier_label.add_theme_font_size_override("font_size", 15)
	tier_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(tier_label)

	# Population
	pop_label = Label.new()
	pop_label.add_theme_font_size_override("font_size", 15)
	pop_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	vbox.add_child(pop_label)

	# Tâches
	tasks_label = Label.new()
	tasks_label.add_theme_font_size_override("font_size", 14)
	tasks_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7))
	vbox.add_child(tasks_label)

	# Fermes
	farm_label = Label.new()
	farm_label.add_theme_font_size_override("font_size", 14)
	farm_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.4))
	vbox.add_child(farm_label)

	# Bâtiments
	buildings_label = Label.new()
	buildings_label.add_theme_font_size_override("font_size", 14)
	buildings_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.9))
	buildings_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(buildings_label)

	# Prochain objectif
	objective_label = Label.new()
	objective_label.add_theme_font_size_override("font_size", 14)
	objective_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(objective_label)

	vbox.add_child(_make_separator())

	# Label "Ressources"
	var res_label = Label.new()
	res_label.text = "Ressources"
	res_label.add_theme_font_size_override("font_size", 17)
	res_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	vbox.add_child(res_label)

	# Scroll pour la liste des ressources
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	stockpile_container = VBoxContainer.new()
	stockpile_container.add_theme_constant_override("separation", 3)
	scroll.add_child(stockpile_container)

	vbox.add_child(_make_separator())

	# Label "Villageois"
	var vill_label = Label.new()
	vill_label.text = "Villageois"
	vill_label.add_theme_font_size_override("font_size", 17)
	vill_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	vbox.add_child(vill_label)

	# Scroll pour la liste des villageois
	scroll_villagers = ScrollContainer.new()
	scroll_villagers.custom_minimum_size = Vector2(0, 200)
	scroll_villagers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll_villagers)

	villager_container = VBoxContainer.new()
	villager_container.add_theme_constant_override("separation", 3)
	scroll_villagers.add_child(villager_container)

	# Hint
	var hint = Label.new()
	hint.text = "F1 pour fermer"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

func _make_separator() -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 3)
	return sep

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

	# Population avec cap
	var pop = village_manager.villagers.size()
	var cap = village_manager.get_population_cap()
	pop_label.text = "Villageois : %d / %d" % [pop, cap]

	tasks_label.text = "Tâches en attente : %d" % village_manager.task_queue.size()

	# Fermes
	var farm_stats = village_manager.get_farm_stats()
	if farm_stats["total"] > 0:
		farm_label.text = "Ferme : %d parcelles (%d matures / %d max)" % [farm_stats["total"], farm_stats["mature"], farm_stats["max"]]
	else:
		farm_label.text = "Ferme : non construite"

	# Bâtiments
	if village_manager.built_structures.size() > 0:
		var names = []
		for built in village_manager.built_structures:
			names.append(built["name"])
		buildings_label.text = "Bâtiments : " + ", ".join(names)
	else:
		buildings_label.text = "Bâtiments : aucun"

	# Prochain objectif
	objective_label.text = _get_next_objective()

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
	else:
		# Trier par quantité décroissante
		sorted_resources.sort_custom(func(a, b): return a[1] > b[1])

		for res in sorted_resources:
			var bt = res[0]
			var count = res[1]
			var row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)

			# Icône couleur du bloc
			var color_rect = ColorRect.new()
			color_rect.custom_minimum_size = Vector2(14, 14)
			var block_color = BlockRegistry.get_block_color(bt as BlockRegistry.BlockType)
			color_rect.color = block_color
			row.add_child(color_rect)

			# Nom du bloc
			var name_label = Label.new()
			name_label.text = BlockRegistry.get_block_name(bt as BlockRegistry.BlockType)
			name_label.add_theme_font_size_override("font_size", 14)
			name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)

			# Quantité
			var count_label = Label.new()
			count_label.text = "x%d" % count
			count_label.add_theme_font_size_override("font_size", 14)
			count_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
			row.add_child(count_label)

			stockpile_container.add_child(row)

	# === Liste des villageois ===
	for child in villager_container.get_children():
		child.queue_free()

	var VProfession = preload("res://scripts/villager_profession.gd")
	for npc in village_manager.villagers:
		if not is_instance_valid(npc):
			continue
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		# Pastille couleur selon activité
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		match npc.current_activity:
			VProfession.Activity.WORK:
				dot.color = Color(1.0, 0.9, 0.3)  # jaune
			VProfession.Activity.SLEEP:
				dot.color = Color(0.4, 0.4, 0.8)  # bleu
			VProfession.Activity.GO_HOME:
				dot.color = Color(0.8, 0.5, 0.3)  # orange
			_:
				dot.color = Color(0.6, 0.8, 0.6)  # vert
		row.add_child(dot)

		# Nom de la profession
		var prof_label = Label.new()
		prof_label.text = VProfession.get_profession_name(npc.profession)
		prof_label.add_theme_font_size_override("font_size", 13)
		prof_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		prof_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(prof_label)

		# Barre de faim
		var hunger_bar = ProgressBar.new()
		hunger_bar.custom_minimum_size = Vector2(60, 12)
		hunger_bar.max_value = npc.HUNGER_MAX
		hunger_bar.value = npc.hunger
		hunger_bar.show_percentage = false
		# Couleur de la barre selon le niveau
		var bar_style = StyleBoxFlat.new()
		if npc.hunger > 60:
			bar_style.bg_color = Color(0.3, 0.8, 0.3)  # vert
		elif npc.hunger > 30:
			bar_style.bg_color = Color(0.9, 0.8, 0.2)  # jaune
		else:
			bar_style.bg_color = Color(0.9, 0.2, 0.2)  # rouge
		hunger_bar.add_theme_stylebox_override("fill", bar_style)
		var bar_bg = StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.2, 0.2, 0.2)
		hunger_bar.add_theme_stylebox_override("background", bar_bg)
		row.add_child(hunger_bar)

		# Tâche en cours
		var task_label = Label.new()
		var task_text = npc._task_status if npc._task_status != "" else npc.get_info_text().split(" - ")[-1]
		task_label.text = task_text
		task_label.add_theme_font_size_override("font_size", 12)
		task_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		task_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(task_label)

		villager_container.add_child(row)

func _get_next_objective() -> String:
	if not village_manager:
		return ""

	match village_manager.village_phase:
		0:
			var wood = village_manager.get_total_wood()
			if wood < 10:
				return "Prochain : récolter du bois (%d/10)" % wood
			var planks = village_manager.get_total_planks()
			if planks < 4:
				return "Prochain : crafter des planches (%d/4)" % planks
			return "Prochain : crafter une Table de Craft"
		1:
			if not village_manager.placed_workstations.has(21):  # FURNACE
				var stone = village_manager.get_resource_count(3)
				return "Prochain : Fourneau (besoin 8 pierre, a %d)" % stone
			return "Prochain : construire les premiers bâtiments"
		2:
			if not village_manager.placed_workstations.has(22):  # STONE_TABLE
				var iron = village_manager.get_resource_count(19)
				return "Prochain : Table en pierre (besoin 4 fer, a %d)" % iron
			return "Prochain : expansion du village"
		3:
			var pop = village_manager.villagers.size()
			var cap = village_manager.get_population_cap()
			if pop < cap:
				var bread = village_manager.get_resource_count(BlockRegistry.BlockType.BREAD)
				return "Prochain villageois : %d pain nécessaire (a %d)" % [village_manager.BREAD_PER_VILLAGER, bread]
			# Chercher le prochain bâtiment non construit
			var built_names: Dictionary = {}
			for built in village_manager.built_structures:
				built_names[built["name"]] = true
			for bp in village_manager.BLUEPRINTS:
				if not built_names.has(bp["name"]):
					return "Prochain : %s" % bp["name"]
			return "Village complet !"

	return ""
