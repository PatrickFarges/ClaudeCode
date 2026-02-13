extends CanvasLayer

# Menu pause avec sauvegarde/chargement

var is_open: bool = false
var save_manager: Node = null

var background: ColorRect
var panel: PanelContainer
var title_label: Label
var status_label: Label
var btn_resume: Button
var btn_save: Button
var btn_load: Button
var btn_quit: Button

func _ready():
	layer = 11
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")

	await get_tree().process_frame
	save_manager = get_tree().get_first_node_in_group("save_manager")

	_build_ui()

func _build_ui():
	background = ColorRect.new()
	background.color = Color(0, 0, 0, 0.7)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.2, 0.95)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 40
	panel_style.content_margin_right = 40
	panel_style.content_margin_top = 30
	panel_style.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	# Titre
	title_label = Label.new()
	title_label.text = Locale.tr_ui("pause_title")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color(1, 1, 1))
	vbox.add_child(title_label)

	# Separateur
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	vbox.add_child(sep)

	# Bouton Reprendre
	btn_resume = _create_button(Locale.tr_ui("pause_resume"), Color(0.2, 0.65, 0.3))
	btn_resume.pressed.connect(_on_resume)
	vbox.add_child(btn_resume)

	# Bouton Sauvegarder
	btn_save = _create_button(Locale.tr_ui("pause_save"), Color(0.25, 0.5, 0.8))
	btn_save.pressed.connect(_on_save)
	vbox.add_child(btn_save)

	# Bouton Charger
	btn_load = _create_button(Locale.tr_ui("pause_load"), Color(0.8, 0.55, 0.2))
	btn_load.pressed.connect(_on_load)
	vbox.add_child(btn_load)

	# Separateur
	var sep2 = HSeparator.new()
	sep2.add_theme_constant_override("separation", 4)
	vbox.add_child(sep2)

	# Bouton Quitter
	btn_quit = _create_button(Locale.tr_ui("pause_quit"), Color(0.75, 0.2, 0.2))
	btn_quit.pressed.connect(_on_quit)
	vbox.add_child(btn_quit)

	# Label de statut
	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	vbox.add_child(status_label)

func _create_button(text: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 48)

	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = color
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.corner_radius_bottom_right = 8
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = color.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(1, 1, 1))

	return btn

func open_pause():
	if is_open:
		return
	is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status_label.text = ""
	_update_load_button()

func close_pause():
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _update_load_button():
	if save_manager and not save_manager.has_save("World1"):
		btn_load.disabled = true
		btn_load.modulate = Color(0.5, 0.5, 0.5)
	else:
		btn_load.disabled = false
		btn_load.modulate = Color(1, 1, 1)

func _on_resume():
	close_pause()

func _on_save():
	if not save_manager:
		return
	status_label.text = Locale.tr_ui("saving")
	# Defer pour laisser le label se mettre a jour
	await get_tree().process_frame
	var success = save_manager.save_world("World1")
	if success:
		status_label.text = Locale.tr_ui("save_success")
	else:
		status_label.text = Locale.tr_ui("save_error")
	_update_load_button()

func _on_load():
	if not save_manager:
		return
	if not save_manager.has_save("World1"):
		status_label.text = Locale.tr_ui("load_no_save")
		return
	status_label.text = Locale.tr_ui("loading")
	await get_tree().process_frame
	var success = save_manager.load_world("World1")
	if success:
		close_pause()
	else:
		status_label.text = Locale.tr_ui("save_error")

func _on_quit():
	# Sauvegarder avant de quitter
	if save_manager:
		save_manager.save_world("World1")
	get_tree().quit()
