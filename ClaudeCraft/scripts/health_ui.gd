extends CanvasLayer

var player: CharacterBody3D
var health_bar_bg: ColorRect
var health_bar_fill: ColorRect
var health_label: Label
var damage_overlay: ColorRect
var death_overlay: ColorRect
var death_label: Label

var _last_health: int = -1
var damage_flash_timer: float = 0.0

const BAR_WIDTH = 182
const BAR_HEIGHT = 6
const FLASH_DURATION = 0.3

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	_create_health_bar()
	_create_damage_overlay()
	_create_death_screen()

func _create_health_bar():
	# Fond de la barre
	health_bar_bg = ColorRect.new()
	health_bar_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	health_bar_bg.offset_left = -BAR_WIDTH / 2 - 2
	health_bar_bg.offset_right = BAR_WIDTH / 2 + 2
	health_bar_bg.offset_top = -116
	health_bar_bg.offset_bottom = -116 + BAR_HEIGHT + 4
	health_bar_bg.color = Color(0.08, 0.08, 0.08, 0.85)
	add_child(health_bar_bg)

	# Remplissage
	health_bar_fill = ColorRect.new()
	health_bar_fill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	health_bar_fill.offset_left = -BAR_WIDTH / 2
	health_bar_fill.offset_right = BAR_WIDTH / 2
	health_bar_fill.offset_top = -114
	health_bar_fill.offset_bottom = -114 + BAR_HEIGHT
	health_bar_fill.color = Color(0.2, 0.8, 0.2, 1.0)
	add_child(health_bar_fill)

	# Label vie
	health_label = Label.new()
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	health_label.offset_left = -100
	health_label.offset_right = 100
	health_label.offset_top = -134
	health_label.offset_bottom = -116
	health_label.add_theme_font_size_override("font_size", 14)
	health_label.add_theme_color_override("font_color", Color.WHITE)
	health_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	health_label.add_theme_constant_override("shadow_offset_x", 1)
	health_label.add_theme_constant_override("shadow_offset_y", 1)
	health_label.add_theme_constant_override("outline_size", 3)
	health_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	add_child(health_label)

func _create_damage_overlay():
	damage_overlay = ColorRect.new()
	damage_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_overlay.color = Color(0.8, 0, 0, 0)
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_overlay)

func _create_death_screen():
	death_overlay = ColorRect.new()
	death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_overlay.color = Color(0.5, 0, 0, 0.0)
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.visible = false
	add_child(death_overlay)

	death_label = Label.new()
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_label.add_theme_font_size_override("font_size", 48)
	death_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	death_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	death_label.add_theme_constant_override("shadow_offset_x", 2)
	death_label.add_theme_constant_override("shadow_offset_y", 2)
	death_label.add_theme_constant_override("outline_size", 4)
	death_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	death_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.add_child(death_label)

func _process(delta):
	if not player:
		return

	var hp = player.current_health
	var max_hp = player.max_health
	var ratio = float(hp) / float(max_hp)

	# Barre de vie — taille
	health_bar_fill.offset_right = health_bar_fill.offset_left + BAR_WIDTH * ratio

	# Couleur selon le niveau de vie
	if ratio > 0.6:
		health_bar_fill.color = Color(0.2, 0.8, 0.2)
	elif ratio > 0.3:
		health_bar_fill.color = Color(0.9, 0.8, 0.1)
	else:
		health_bar_fill.color = Color(0.9, 0.15, 0.1)

	# Label
	health_label.text = Locale.tr_ui("health") % [hp, max_hp]

	# Flash de dégâts
	if hp < _last_health and _last_health >= 0 and not player.is_dead:
		damage_flash_timer = FLASH_DURATION
	_last_health = hp

	if damage_flash_timer > 0:
		damage_flash_timer -= delta
		damage_overlay.color.a = (damage_flash_timer / FLASH_DURATION) * 0.3
	else:
		damage_overlay.color.a = 0.0

	# Écran de mort
	if player.is_dead:
		death_overlay.visible = true
		death_overlay.color.a = lerpf(death_overlay.color.a, 0.7, delta * 3.0)
		death_label.text = Locale.tr_ui("you_died")
		health_bar_bg.visible = false
		health_bar_fill.visible = false
		health_label.visible = false
	else:
		if death_overlay.visible:
			death_overlay.visible = false
			death_overlay.color.a = 0.0
		health_bar_bg.visible = true
		health_bar_fill.visible = true
		health_label.visible = true
