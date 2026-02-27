extends CanvasLayer

# Inventaire du village — ouvert avec F1
# Affiche le stockpile partagé du village, la phase actuelle, le tier d'outils,
# la population, la faim, les fermes, les bâtiments et le prochain objectif.
# Clic sur un villageois = téléportation du joueur à côté de lui.

var is_open: bool = false
var village_manager = null
var village_id: int = 0

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

	# Panneau centré à l'écran
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -330
	panel.offset_top = -420
	panel.offset_right = 330
	panel.offset_bottom = 420
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
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	# Titre
	title_label = Label.new()
	title_label.text = "Gestion du Village"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

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
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	stockpile_container = VBoxContainer.new()
	stockpile_container.add_theme_constant_override("separation", 3)
	scroll.add_child(stockpile_container)

	vbox.add_child(_make_separator())

	# Label "Villageois" + instruction
	var vill_header = HBoxContainer.new()
	var vill_label = Label.new()
	vill_label.text = "Villageois"
	vill_label.add_theme_font_size_override("font_size", 17)
	vill_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	vill_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vill_header.add_child(vill_label)
	var tp_hint = Label.new()
	tp_hint.text = "(clic = teleport)"
	tp_hint.add_theme_font_size_override("font_size", 12)
	tp_hint.add_theme_color_override("font_color", Color(0.5, 0.6, 0.8))
	vill_header.add_child(tp_hint)
	vbox.add_child(vill_header)

	# Scroll pour la liste des villageois
	scroll_villagers = ScrollContainer.new()
	scroll_villagers.custom_minimum_size = Vector2(0, 280)
	scroll_villagers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll_villagers)

	villager_container = VBoxContainer.new()
	villager_container.add_theme_constant_override("separation", 4)
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
		if village_manager._farm_initialized:
			farm_label.text = "Ferme : planifiée (en attente de construction)"
		else:
			farm_label.text = "Ferme : non construite"

	# Bâtiments — comptés par type + en construction
	var built_count = village_manager.built_structures.size()
	var total_blueprints = village_manager.BLUEPRINTS.size()
	if built_count > 0:
		# Compter par type
		var name_counts: Dictionary = {}
		for built in village_manager.built_structures:
			var n = built["name"]
			name_counts[n] = name_counts.get(n, 0) + 1
		var parts = []
		for n in name_counts:
			if name_counts[n] > 1:
				parts.append("%s x%d" % [n, name_counts[n]])
			else:
				parts.append(n)
		buildings_label.text = "Bâtiments (%d/%d) : %s" % [built_count, total_blueprints, ", ".join(parts)]
	else:
		# Vérifier si un bâtiment est en construction
		var building_in_progress = ""
		for npc in village_manager.villagers:
			if is_instance_valid(npc) and npc.current_task.get("type", "") == "build":
				var bp_idx = npc.current_task.get("blueprint_index", -1)
				if bp_idx >= 0 and bp_idx < total_blueprints:
					var bp = village_manager.BLUEPRINTS[bp_idx]
					var progress = npc.current_task.get("block_index", 0)
					var total = npc.current_task.get("block_list", []).size()
					building_in_progress = "%s (%d/%d blocs)" % [bp["name"], progress, total]
					break
		if building_in_progress != "":
			buildings_label.text = "Bâtiments (0/%d) : en construction — %s" % [total_blueprints, building_in_progress]
		else:
			# Montrer ce qui manque pour le prochain bâtiment
			var next_bp = _get_next_building_info()
			if next_bp != "":
				buildings_label.text = "Bâtiments (0/%d) : %s" % [total_blueprints, next_bp]
			else:
				buildings_label.text = "Bâtiments (0/%d) : aucun" % total_blueprints

	# Objectif + aplanissement + mine
	var obj_text = _get_next_objective()
	if not village_manager._flatten_complete and village_manager.flatten_plan.size() > 0:
		var done = village_manager.flatten_index
		var total_flatten = village_manager.flatten_plan.size()
		var pct = int(float(done) / float(total_flatten) * 100.0) if total_flatten > 0 else 0
		obj_text += "\nAplanissement : %d/%d blocs (%d%%)" % [done, total_flatten, pct]
	if village_manager._mine_initialized:
		var mined = village_manager.mine_front_index
		var total = village_manager.mine_plan.size()
		obj_text += "\nMine : %d/%d blocs creusés" % [mined, total]
	objective_label.text = obj_text

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

	# Compter les professions pour numéroter (Mineur 1, Mineur 2, etc.)
	var prof_counts: Dictionary = {}
	var prof_numbers: Array = []
	for npc in village_manager.villagers:
		if not is_instance_valid(npc):
			prof_numbers.append(0)
			continue
		var p = npc.profession
		prof_counts[p] = prof_counts.get(p, 0) + 1
		prof_numbers.append(prof_counts[p])

	# Compter le nombre total par profession pour savoir si on doit numéroter
	var prof_totals: Dictionary = {}
	for npc in village_manager.villagers:
		if is_instance_valid(npc):
			prof_totals[npc.profession] = prof_totals.get(npc.profession, 0) + 1

	for i in range(village_manager.villagers.size()):
		var npc = village_manager.villagers[i]
		if not is_instance_valid(npc):
			continue

		# Bouton cliquable pour téléportation
		var btn = Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		# Style du bouton
		var btn_style_normal = StyleBoxFlat.new()
		btn_style_normal.bg_color = Color(0.15, 0.15, 0.22, 0.3)
		btn_style_normal.corner_radius_top_left = 4
		btn_style_normal.corner_radius_top_right = 4
		btn_style_normal.corner_radius_bottom_left = 4
		btn_style_normal.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", btn_style_normal)
		var btn_style_hover = StyleBoxFlat.new()
		btn_style_hover.bg_color = Color(0.25, 0.3, 0.45, 0.6)
		btn_style_hover.corner_radius_top_left = 4
		btn_style_hover.corner_radius_top_right = 4
		btn_style_hover.corner_radius_bottom_left = 4
		btn_style_hover.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("hover", btn_style_hover)

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		# Pastille couleur selon activité
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
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

		# Nom : Profession + numéro
		var prof_name = VProfession.get_profession_name(npc.profession)
		if prof_totals.get(npc.profession, 1) > 1:
			prof_name += " %d" % prof_numbers[i]

		var prof_label = Label.new()
		prof_label.text = prof_name
		prof_label.add_theme_font_size_override("font_size", 14)
		prof_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
		prof_label.custom_minimum_size = Vector2(110, 0)
		row.add_child(prof_label)

		# Barre de faim
		var hunger_bar = ProgressBar.new()
		hunger_bar.custom_minimum_size = Vector2(50, 12)
		hunger_bar.max_value = npc.HUNGER_MAX
		hunger_bar.value = npc.hunger
		hunger_bar.show_percentage = false
		var bar_style = StyleBoxFlat.new()
		if npc.hunger > 60:
			bar_style.bg_color = Color(0.3, 0.8, 0.3)
		elif npc.hunger > 30:
			bar_style.bg_color = Color(0.9, 0.8, 0.2)
		else:
			bar_style.bg_color = Color(0.9, 0.2, 0.2)
		hunger_bar.add_theme_stylebox_override("fill", bar_style)
		var bar_bg = StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.2, 0.2, 0.2)
		hunger_bar.add_theme_stylebox_override("background", bar_bg)
		row.add_child(hunger_bar)

		# Tâche en cours (activité temps réel)
		var task_label = Label.new()
		var task_text = ""
		if npc._is_starving:
			task_text = "[Faim!]"
		elif npc._task_status != "":
			task_text = npc._task_status
		else:
			match npc.current_activity:
				VProfession.Activity.WANDER:
					task_text = "Se promène"
				VProfession.Activity.WORK:
					if npc.current_task.is_empty():
						task_text = "Cherche tâche..."
					else:
						task_text = "Travaille"
				VProfession.Activity.GATHER:
					task_text = "Socialise"
				VProfession.Activity.GO_HOME:
					task_text = "Rentre"
				VProfession.Activity.SLEEP:
					task_text = "Dort"
				_:
					task_text = "Idle"
		task_label.text = task_text
		task_label.add_theme_font_size_override("font_size", 13)
		task_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		task_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(task_label)

		# Icône téléport
		var tp_label = Label.new()
		tp_label.text = ">"
		tp_label.add_theme_font_size_override("font_size", 14)
		tp_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.9))
		row.add_child(tp_label)

		btn.add_child(row)
		btn.custom_minimum_size = Vector2(650, 28)

		# Connecter le clic au téléport
		var npc_ref = npc
		btn.pressed.connect(func(): _teleport_to_villager(npc_ref))

		villager_container.add_child(btn)

func _teleport_to_villager(npc):
	if not is_instance_valid(npc):
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	# Téléporter le joueur à 3 blocs du PNJ, face à lui
	var npc_pos = npc.global_position
	var offset = Vector3(3, 2, 0)
	player.global_position = npc_pos + offset
	# Fermer l'UI après téléport
	close_inventory()

func _get_next_building_info() -> String:
	if not village_manager:
		return ""
	# Trouver le prochain bâtiment à construire et montrer les matériaux manquants
	var built_names: Dictionary = {}
	for built in village_manager.built_structures:
		built_names[built["name"]] = true
	for bp in village_manager.BLUEPRINTS:
		if built_names.has(bp["name"]):
			continue
		if bp.get("phase", 0) <= village_manager.village_phase:
			# Ce blueprint est le prochain — vérifier les matériaux
			var missing = []
			for bt in bp["materials"]:
				var needed = bp["materials"][bt]
				var have = 0
				if bt == 11:  # PLANKS
					have = village_manager.get_total_planks()
				else:
					have = village_manager.get_resource_count(bt)
				if have < needed:
					var name = BlockRegistry.get_block_name(bt as BlockRegistry.BlockType)
					missing.append("%s %d/%d" % [name, have, needed])
			if missing.size() > 0:
				return "prochain: %s (manque %s)" % [bp["name"], ", ".join(missing)]
			else:
				return "prochain: %s (prêt!)" % bp["name"]
	return ""

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
				var stone = village_manager.get_resource_count(3) + village_manager.get_resource_count(25)
				var planks = village_manager.get_total_planks()
				return "Prochain : Table en pierre (pierre %d/4, planches %d/4)" % [stone, planks]
			return "Prochain : expansion du village"
		3:
			var pop = village_manager.villagers.size()
			var cap = village_manager.get_population_cap()
			if pop < cap:
				var bread = village_manager.get_resource_count(BlockRegistry.BlockType.BREAD)
				return "Prochain villageois : %d pain nécessaire (a %d)" % [village_manager.BREAD_PER_VILLAGER, bread]
			var built_names: Dictionary = {}
			for built in village_manager.built_structures:
				built_names[built["name"]] = true
			for bp in village_manager.BLUEPRINTS:
				if not built_names.has(bp["name"]):
					return "Prochain : %s" % bp["name"]
			return "Village complet !"

	return ""
