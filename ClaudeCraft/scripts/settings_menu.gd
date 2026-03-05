extends CanvasLayer

# Menu Settings — ouvert avec F3
# Permet de changer : vitesse du temps, style d'éclairage, seed du monde
# Affiche un récap des contrôles

var is_open: bool = false
var background: ColorRect
var panel: PanelContainer
var _speed_buttons: Array = []
var _render_buttons: Array = []
var _seed_input: LineEdit
var _saved_mouse_mode: int = 0

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			if is_open:
				close_menu()
			else:
				open_menu()
			get_viewport().set_input_as_handled()

func open_menu():
	is_open = true
	visible = true
	_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()

func close_menu():
	is_open = false
	visible = true
	# Nettoyer
	for child in get_children():
		child.queue_free()
	visible = false
	Input.mouse_mode = _saved_mouse_mode

func _make_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.16, 0.97)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.5, 0.9, 0.8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _build_ui():
	# Fond semi-transparent
	background = ColorRect.new()
	background.color = Color(0, 0, 0, 0.7)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# Panneau centré
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -420
	panel.offset_top = -380
	panel.offset_right = 420
	panel.offset_bottom = 380
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(panel)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Titre
	var title = Label.new()
	title.text = "Paramètres"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_make_separator())

	# === Vitesse du temps ===
	_add_section_label(vbox, "Vitesse du temps")

	var speed_row = HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 8)
	var speed_names = ["Lent (x0.5)", "Normal (x1)", "Rapide (x2)", "Très rapide (x10)"]
	var day_night = get_tree().get_first_node_in_group("day_night_cycle")
	var current_speed = day_night.speed_index if day_night else 1
	_speed_buttons = []
	for i in range(4):
		var btn = Button.new()
		btn.text = speed_names[i]
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size = Vector2(170, 32)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if i == current_speed:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
			btn.add_theme_stylebox_override("normal", _make_btn_style_active())
		else:
			btn.add_theme_stylebox_override("normal", _make_btn_style())
		var idx = i
		btn.pressed.connect(func(): _set_speed(idx))
		speed_row.add_child(btn)
		_speed_buttons.append(btn)
	vbox.add_child(speed_row)

	vbox.add_child(_make_separator())

	# === Style d'éclairage ===
	_add_section_label(vbox, "Style d'éclairage")

	var render_row = HBoxContainer.new()
	render_row.add_theme_constant_override("separation", 8)
	var render_names = ["Vanilla", "Global Illumination", "Cloclo Style"]
	var hud = get_tree().current_scene.get_node_or_null("VersionHUD")
	var current_render = hud._render_preset if hud else 2
	_render_buttons = []
	for i in range(3):
		var btn = Button.new()
		btn.text = render_names[i]
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size = Vector2(200, 32)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if i == current_render:
			btn.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
			btn.add_theme_stylebox_override("normal", _make_btn_style_active())
		else:
			btn.add_theme_stylebox_override("normal", _make_btn_style())
		var idx = i
		btn.pressed.connect(func(): _set_render(idx))
		render_row.add_child(btn)
		_render_buttons.append(btn)
	vbox.add_child(render_row)

	vbox.add_child(_make_separator())

	# === Seed ===
	_add_section_label(vbox, "Seed du monde")

	var seed_row = HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	var world_mgr = get_tree().get_first_node_in_group("world_manager")
	var chunk_gen = world_mgr.chunk_generator if world_mgr else null
	var current_seed = chunk_gen.get_world_seed() if chunk_gen else 0

	var seed_info = Label.new()
	seed_info.text = "Seed actuel : %d" % current_seed
	seed_info.add_theme_font_size_override("font_size", 14)
	seed_info.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	seed_row.add_child(seed_info)

	var seed_note = Label.new()
	seed_note.text = "(modifiable au prochain lancement)"
	seed_note.add_theme_font_size_override("font_size", 12)
	seed_note.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	seed_row.add_child(seed_note)
	vbox.add_child(seed_row)

	vbox.add_child(_make_separator())

	# === Contrôles ===
	_add_section_label(vbox, "Contrôles")

	var controls = GridContainer.new()
	controls.columns = 2
	controls.add_theme_constant_override("h_separation", 20)
	controls.add_theme_constant_override("v_separation", 4)

	var bindings = [
		["ZQSD / WASD", "Se déplacer"],
		["Souris", "Regarder autour"],
		["Clic gauche", "Miner / Attaquer"],
		["Clic droit", "Placer un bloc"],
		["Espace", "Sauter"],
		["Shift", "Sprinter"],
		["Molette", "Changer slot hotbar"],
		["1-9", "Sélectionner slot"],
		["I", "Inventaire"],
		["C", "Table de craft"],
		["F1", "Gestion du village"],
		["F2", "Changer style éclairage"],
		["F3", "Ce menu"],
		["Ctrl + Molette", "Vitesse du temps"],
		["Alt + Molette", "Zoom FOV (70°-110°)"],
		["Echap", "Pause"],
	]

	for binding in bindings:
		var key_label = Label.new()
		key_label.text = binding[0]
		key_label.add_theme_font_size_override("font_size", 14)
		key_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
		key_label.custom_minimum_size = Vector2(180, 0)
		controls.add_child(key_label)

		var desc_label = Label.new()
		desc_label.text = binding[1]
		desc_label.add_theme_font_size_override("font_size", 14)
		desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		controls.add_child(desc_label)

	vbox.add_child(controls)

	vbox.add_child(_make_separator())

	# Hint fermer
	var hint = Label.new()
	hint.text = "F3 pour fermer"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

func _add_section_label(parent: VBoxContainer, text: String):
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	parent.add_child(lbl)

func _make_separator() -> HSeparator:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	return sep

func _make_btn_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.18, 0.18, 0.25, 0.8)
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.3, 0.35, 0.5, 0.6)
	return s

func _make_btn_style_active() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.25, 0.25, 0.4, 0.9)
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.border_color = Color(0.5, 0.6, 1.0, 0.9)
	return s

func _set_speed(idx: int):
	var day_night = get_tree().get_first_node_in_group("day_night_cycle")
	if day_night:
		day_night.set_speed(idx)
	# Mettre à jour le HUD
	var hud = get_tree().current_scene.get_node_or_null("VersionHUD")
	if hud:
		hud._update_speed_label()
	# Refresh les boutons
	_update_speed_buttons(idx)
	# Sauvegarder
	save_settings()

func _set_render(idx: int):
	var hud = get_tree().current_scene.get_node_or_null("VersionHUD")
	if hud and hud._env:
		hud._render_preset = idx
		match idx:
			0: hud._apply_vanilla()
			1: hud._apply_gi()
			2: hud._apply_cinematic()
		hud.render_label.text = "Rendu : %s (F2)" % hud.RENDER_NAMES[idx]
		hud.render_label.add_theme_color_override("font_color", hud.RENDER_COLORS[idx])
	_update_render_buttons(idx)
	# Sauvegarder
	save_settings()

func _update_speed_buttons(active: int):
	for i in range(_speed_buttons.size()):
		var btn = _speed_buttons[i]
		if i == active:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
			btn.add_theme_stylebox_override("normal", _make_btn_style_active())
		else:
			btn.remove_theme_color_override("font_color")
			btn.add_theme_stylebox_override("normal", _make_btn_style())

func _update_render_buttons(active: int):
	for i in range(_render_buttons.size()):
		var btn = _render_buttons[i]
		if i == active:
			btn.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
			btn.add_theme_stylebox_override("normal", _make_btn_style_active())
		else:
			btn.remove_theme_color_override("font_color")
			btn.add_theme_stylebox_override("normal", _make_btn_style())

# === Persistance des settings ===

const SETTINGS_PATH = "user://settings.cfg"

func save_settings():
	var cfg = ConfigFile.new()
	var day_night = get_tree().get_first_node_in_group("day_night_cycle")
	if day_night:
		cfg.set_value("game", "speed_index", day_night.speed_index)
	var hud = get_tree().current_scene.get_node_or_null("VersionHUD")
	if hud:
		cfg.set_value("game", "render_preset", hud._render_preset)
	cfg.save(SETTINGS_PATH)

func load_settings():
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	# Vitesse du temps
	if cfg.has_section_key("game", "speed_index"):
		var idx = int(cfg.get_value("game", "speed_index"))
		var day_night = get_tree().get_first_node_in_group("day_night_cycle")
		if day_night:
			day_night.set_speed(idx)
		var hud = get_tree().current_scene.get_node_or_null("VersionHUD")
		if hud:
			hud._update_speed_label()
	# Render preset
	if cfg.has_section_key("game", "render_preset"):
		var idx = int(cfg.get_value("game", "render_preset"))
		var hud = get_tree().current_scene.get_node_or_null("VersionHUD")
		if hud and hud._env:
			hud._render_preset = idx
			match idx:
				0: hud._apply_vanilla()
				1: hud._apply_gi()
				2: hud._apply_cinematic()
			hud.render_label.text = "Rendu : %s (F2)" % hud.RENDER_NAMES[idx]
			hud.render_label.add_theme_color_override("font_color", hud.RENDER_COLORS[idx])
