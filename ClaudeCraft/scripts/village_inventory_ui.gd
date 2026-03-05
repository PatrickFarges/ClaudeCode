extends CanvasLayer

# Inventaire du village — ouvert avec F1
# Deux panneaux côte à côte :
#   Gauche : statut village + liste villageois (clic = téléport)
#   Droite : toutes les ressources (stockpile 2 colonnes) + stockage bâtiments

var is_open: bool = false
var village_manager = null
var village_id: int = 0

var background: ColorRect
var panel_left: PanelContainer
var panel_right: PanelContainer
var title_label: Label
var phase_label: Label
var tier_label: Label
var pop_label: Label
var tasks_label: Label
var farm_label: Label
var buildings_label: Label
var objective_label: Label
var stockpile_container: GridContainer
var storage_container: VBoxContainer
var villager_container: VBoxContainer
var scroll_right: ScrollContainer
var scroll_villagers: ScrollContainer
var _update_timer: float = 0.0

# Largeurs des panneaux
const LEFT_W = 460
const RIGHT_W = 560
const PANEL_H = 760
const GAP = 12

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

func _make_panel_style() -> StyleBoxFlat:
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
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _build_ui():
	# Fond semi-transparent
	background = ColorRect.new()
	background.color = Color(0, 0, 0, 0.6)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# Calcul position : les deux panneaux centrés ensemble
	var total_w = LEFT_W + GAP + RIGHT_W
	var start_x = -total_w / 2

	# === PANNEAU GAUCHE : Statut + Villageois ===
	panel_left = PanelContainer.new()
	panel_left.set_anchors_preset(Control.PRESET_CENTER)
	panel_left.anchor_left = 0.5
	panel_left.anchor_top = 0.5
	panel_left.anchor_right = 0.5
	panel_left.anchor_bottom = 0.5
	panel_left.offset_left = start_x
	panel_left.offset_top = -PANEL_H / 2
	panel_left.offset_right = start_x + LEFT_W
	panel_left.offset_bottom = PANEL_H / 2
	panel_left.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(panel_left)

	var vbox_left = VBoxContainer.new()
	vbox_left.add_theme_constant_override("separation", 4)
	panel_left.add_child(vbox_left)

	# Titre
	title_label = Label.new()
	title_label.text = "Gestion du Village"
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox_left.add_child(title_label)

	vbox_left.add_child(_make_separator())

	# Phase
	phase_label = Label.new()
	phase_label.add_theme_font_size_override("font_size", 15)
	phase_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox_left.add_child(phase_label)

	# Tier
	tier_label = Label.new()
	tier_label.add_theme_font_size_override("font_size", 14)
	tier_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox_left.add_child(tier_label)

	# Population
	pop_label = Label.new()
	pop_label.add_theme_font_size_override("font_size", 14)
	pop_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	vbox_left.add_child(pop_label)

	# Tâches
	tasks_label = Label.new()
	tasks_label.add_theme_font_size_override("font_size", 13)
	tasks_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7))
	vbox_left.add_child(tasks_label)

	# Fermes
	farm_label = Label.new()
	farm_label.add_theme_font_size_override("font_size", 13)
	farm_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.4))
	vbox_left.add_child(farm_label)

	# Bâtiments
	buildings_label = Label.new()
	buildings_label.add_theme_font_size_override("font_size", 13)
	buildings_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.9))
	buildings_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox_left.add_child(buildings_label)

	# Prochain objectif
	objective_label = Label.new()
	objective_label.add_theme_font_size_override("font_size", 13)
	objective_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox_left.add_child(objective_label)

	vbox_left.add_child(_make_separator())

	# Label "Villageois" + instruction
	var vill_header = HBoxContainer.new()
	var vill_label = Label.new()
	vill_label.text = "Villageois"
	vill_label.add_theme_font_size_override("font_size", 16)
	vill_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	vill_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vill_header.add_child(vill_label)
	var tp_hint = Label.new()
	tp_hint.text = "(clic = teleport)"
	tp_hint.add_theme_font_size_override("font_size", 11)
	tp_hint.add_theme_color_override("font_color", Color(0.5, 0.6, 0.8))
	vill_header.add_child(tp_hint)
	vbox_left.add_child(vill_header)

	# Scroll pour la liste des villageois
	scroll_villagers = ScrollContainer.new()
	scroll_villagers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox_left.add_child(scroll_villagers)

	villager_container = VBoxContainer.new()
	villager_container.add_theme_constant_override("separation", 3)
	scroll_villagers.add_child(villager_container)

	# Hint
	var hint = Label.new()
	hint.text = "F1 pour fermer"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox_left.add_child(hint)

	# === PANNEAU DROIT : Ressources + Stockage ===
	panel_right = PanelContainer.new()
	panel_right.set_anchors_preset(Control.PRESET_CENTER)
	panel_right.anchor_left = 0.5
	panel_right.anchor_top = 0.5
	panel_right.anchor_right = 0.5
	panel_right.anchor_bottom = 0.5
	panel_right.offset_left = start_x + LEFT_W + GAP
	panel_right.offset_top = -PANEL_H / 2
	panel_right.offset_right = start_x + LEFT_W + GAP + RIGHT_W
	panel_right.offset_bottom = PANEL_H / 2
	panel_right.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(panel_right)

	# Scroll global pour tout le panneau droit
	scroll_right = ScrollContainer.new()
	scroll_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_right.add_child(scroll_right)

	var vbox_right = VBoxContainer.new()
	vbox_right.add_theme_constant_override("separation", 6)
	vbox_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_right.add_child(vbox_right)

	# Titre ressources
	var res_title = Label.new()
	res_title.text = "Ressources du Village"
	res_title.add_theme_font_size_override("font_size", 22)
	res_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	res_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox_right.add_child(res_title)

	vbox_right.add_child(_make_separator())

	# Label section stockpile
	var stockpile_label = Label.new()
	stockpile_label.text = "Stockpile"
	stockpile_label.add_theme_font_size_override("font_size", 16)
	stockpile_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	vbox_right.add_child(stockpile_label)

	# Grid 2 colonnes pour les ressources
	stockpile_container = GridContainer.new()
	stockpile_container.columns = 2
	stockpile_container.add_theme_constant_override("h_separation", 16)
	stockpile_container.add_theme_constant_override("v_separation", 3)
	stockpile_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_right.add_child(stockpile_container)

	vbox_right.add_child(_make_separator())

	# Label section stockage bâtiments
	var storage_label = Label.new()
	storage_label.text = "Stockage bâtiments"
	storage_label.add_theme_font_size_override("font_size", 16)
	storage_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	vbox_right.add_child(storage_label)

	storage_container = VBoxContainer.new()
	storage_container.add_theme_constant_override("separation", 3)
	storage_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_right.add_child(storage_container)

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

	var phase_names = ["Phase 0 — Bootstrap", "Phase 1 — Age du Bois", "Phase 2 — Age de la Pierre", "Phase 3 — Age du Fer", "Phase 4 — Age Médiéval"]
	var phase_idx = clampi(village_manager.village_phase, 0, phase_names.size() - 1)
	phase_label.text = phase_names[phase_idx]

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
			var next_bp = _get_next_building_info()
			if next_bp != "":
				buildings_label.text = "Bâtiments (0/%d) : %s" % [total_blueprints, next_bp]
			else:
				buildings_label.text = "Bâtiments (0/%d) : aucun" % total_blueprints

	# Objectif + aplanissement + mine
	var obj_text = _get_next_objective()
	if village_manager._waiting_for_chunks:
		obj_text += "\nChargement du terrain..."
	elif not village_manager._flatten_complete and village_manager.flatten_plan.size() > 0:
		var done = village_manager.flatten_index
		var total_flatten = village_manager.flatten_plan.size()
		var pct = int(float(done) / float(total_flatten) * 100.0) if total_flatten > 0 else 0
		obj_text += "\nAplanissement : %d/%d colonnes (%d%%)" % [done, total_flatten, pct]
	if not village_manager._path_built and village_manager._path_blocks.size() > 0:
		var path_done = village_manager._path_index
		var path_total = village_manager._path_blocks.size()
		var path_pct = int(float(path_done) / float(path_total) * 100.0) if path_total > 0 else 0
		obj_text += "\nPlace du village : %d/%d blocs (%d%%)" % [path_done, path_total, path_pct]
	if village_manager._mine_initialized:
		var mined = village_manager.mine_front_index
		var total = village_manager.mine_plan.size()
		obj_text += "\nMine : %d/%d blocs creusés" % [mined, total]
	# Section militaire (Phase 4+)
	if village_manager.village_phase >= 4:
		var war_mgr = get_tree().get_first_node_in_group("war_manager")
		if war_mgr:
			obj_text += "\n--- Militaire ---"
			obj_text += "\nGuerre : " + war_mgr.get_war_status_text()
			obj_text += "\nEnnemi : " + war_mgr.get_enemy_status_text()
			var swords = village_manager.get_total_resource(BlockRegistry.BlockType.IRON_SWORD)
			var shields = village_manager.get_total_resource(BlockRegistry.BlockType.SHIELD)
			obj_text += "\nÉpées : %d | Boucliers : %d" % [swords, shields]

	objective_label.text = obj_text

	# === PANNEAU DROIT : Ressources ===
	_refresh_stockpile()
	_refresh_storage()

	# === Villageois ===
	_refresh_villagers()

func _refresh_stockpile():
	for child in stockpile_container.get_children():
		child.queue_free()

	# Collecter toutes les ressources (stockpile + bâtiments agrégés)
	var all_resources: Dictionary = {}

	# Stockpile virtuel
	for bt in village_manager.stockpile:
		var count = village_manager.stockpile[bt]
		if count > 0:
			all_resources[bt] = all_resources.get(bt, 0) + count

	# Trier par quantité décroissante
	var sorted_resources = []
	for bt in all_resources:
		sorted_resources.append([bt, all_resources[bt]])

	if sorted_resources.size() == 0:
		var empty_label = Label.new()
		empty_label.text = "  (aucune ressource)"
		empty_label.add_theme_font_size_override("font_size", 13)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		stockpile_container.add_child(empty_label)
	else:
		sorted_resources.sort_custom(func(a, b): return a[1] > b[1])

		for res in sorted_resources:
			var bt = res[0]
			var count = res[1]
			var row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			row.custom_minimum_size = Vector2(240, 0)

			# Icône couleur du bloc
			var color_rect = ColorRect.new()
			color_rect.custom_minimum_size = Vector2(14, 14)
			color_rect.color = BlockRegistry.get_block_color(bt as BlockRegistry.BlockType)
			row.add_child(color_rect)

			# Nom du bloc
			var name_label = Label.new()
			name_label.text = BlockRegistry.get_block_name(bt as BlockRegistry.BlockType)
			name_label.add_theme_font_size_override("font_size", 13)
			name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)

			# Quantité
			var count_label = Label.new()
			count_label.text = "x%d" % count
			count_label.add_theme_font_size_override("font_size", 13)
			count_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
			row.add_child(count_label)

			stockpile_container.add_child(row)

func _refresh_storage():
	for child in storage_container.get_children():
		child.queue_free()

	var storage_info = village_manager.get_building_storage_info()
	if storage_info.size() == 0:
		var no_storage = Label.new()
		no_storage.text = "  (aucun bâtiment avec stockage)"
		no_storage.add_theme_font_size_override("font_size", 13)
		no_storage.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		storage_container.add_child(no_storage)
	else:
		for bn in storage_info:
			var si = storage_info[bn]
			# En-tête bâtiment avec jauge
			var header = HBoxContainer.new()
			header.add_theme_constant_override("separation", 8)
			var bn_label = Label.new()
			bn_label.text = "%s" % bn
			bn_label.add_theme_font_size_override("font_size", 14)
			bn_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
			bn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			header.add_child(bn_label)
			var cap_label = Label.new()
			cap_label.text = "%d / %d" % [si["used"], si["capacity"]]
			cap_label.add_theme_font_size_override("font_size", 13)
			if si["used"] >= si["capacity"]:
				cap_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
			else:
				cap_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
			header.add_child(cap_label)
			storage_container.add_child(header)

			# Items dans ce bâtiment — en grille 2 colonnes
			var items_grid = GridContainer.new()
			items_grid.columns = 2
			items_grid.add_theme_constant_override("h_separation", 12)
			items_grid.add_theme_constant_override("v_separation", 2)
			for item_bt in si["items"]:
				var cnt = si["items"][item_bt]
				if cnt <= 0:
					continue
				var item_row = HBoxContainer.new()
				item_row.add_theme_constant_override("separation", 6)
				item_row.custom_minimum_size = Vector2(230, 0)
				var spacer = Control.new()
				spacer.custom_minimum_size = Vector2(12, 0)
				item_row.add_child(spacer)
				var cr = ColorRect.new()
				cr.custom_minimum_size = Vector2(12, 12)
				cr.color = BlockRegistry.get_block_color(item_bt as BlockRegistry.BlockType)
				item_row.add_child(cr)
				var item_name = Label.new()
				item_name.text = BlockRegistry.get_block_name(item_bt as BlockRegistry.BlockType)
				item_name.add_theme_font_size_override("font_size", 13)
				item_name.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
				item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				item_row.add_child(item_name)
				var item_count = Label.new()
				item_count.text = "x%d" % cnt
				item_count.add_theme_font_size_override("font_size", 13)
				item_count.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
				item_row.add_child(item_count)
				items_grid.add_child(item_row)
			storage_container.add_child(items_grid)

func _refresh_villagers():
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

		# Nom : Profession + numéro
		var prof_name = VProfession.get_profession_name(npc.profession)
		if prof_totals.get(npc.profession, 1) > 1:
			prof_name += " %d" % prof_numbers[i]

		var prof_label = Label.new()
		prof_label.text = prof_name
		prof_label.add_theme_font_size_override("font_size", 13)
		prof_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
		prof_label.custom_minimum_size = Vector2(100, 0)
		row.add_child(prof_label)

		# Barre de faim
		var hunger_bar = ProgressBar.new()
		hunger_bar.custom_minimum_size = Vector2(40, 10)
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
		task_label.add_theme_font_size_override("font_size", 12)
		task_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		task_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(task_label)

		# Icône téléport
		var tp_label = Label.new()
		tp_label.text = ">"
		tp_label.add_theme_font_size_override("font_size", 13)
		tp_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.9))
		row.add_child(tp_label)

		btn.add_child(row)
		btn.custom_minimum_size = Vector2(LEFT_W - 30, 26)

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
	var npc_pos = npc.global_position
	var offset = Vector3(3, 2, 0)
	player.global_position = npc_pos + offset
	close_inventory()

func _get_next_building_info() -> String:
	if not village_manager:
		return ""
	var built_names: Dictionary = {}
	for built in village_manager.built_structures:
		built_names[built["name"]] = true
	for bp in village_manager.BLUEPRINTS:
		if built_names.has(bp["name"]):
			continue
		if bp.get("phase", 0) <= village_manager.village_phase:
			var missing = []
			for bt in bp["materials"]:
				var needed = bp["materials"][bt]
				var have = 0
				if bt == 11:  # PLANKS
					have = village_manager.get_total_planks()
				elif bt == 3 or bt == 25:  # STONE/COBBLESTONE
					have = village_manager.get_total_stone()
				else:
					have = village_manager.get_resource_count(bt)
				if have < needed:
					var bname = BlockRegistry.get_block_name(bt as BlockRegistry.BlockType)
					missing.append("%s %d/%d" % [bname, have, needed])
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
				var bread = village_manager.get_total_resource(BlockRegistry.BlockType.BREAD)
				return "Prochain villageois : %d pain nécessaire (a %d)" % [village_manager.BREAD_PER_VILLAGER, bread]
			var built_names: Dictionary = {}
			for built in village_manager.built_structures:
				built_names[built["name"]] = true
			for bp in village_manager.BLUEPRINTS:
				if not built_names.has(bp["name"]):
					return "Prochain : %s" % bp["name"]
			return "Village complet !"

	return ""
