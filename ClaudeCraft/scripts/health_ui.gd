# health_ui.gd v2.0.0
# Effets de degats (flash rouge) et ecran de mort
# Les coeurs MC sont maintenant dans hotbar_ui.gd

extends CanvasLayer

var player: CharacterBody3D
var damage_overlay: ColorRect
var death_overlay: ColorRect
var death_label: Label
var _last_health: int = -1
var damage_flash_timer: float = 0.0
const FLASH_DURATION = 0.3

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	_create_damage_overlay()
	_create_death_screen()

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

	# Flash de degats
	if hp < _last_health and _last_health >= 0 and not player.is_dead:
		damage_flash_timer = FLASH_DURATION
	_last_health = hp

	if damage_flash_timer > 0:
		damage_flash_timer -= delta
		damage_overlay.color.a = (damage_flash_timer / FLASH_DURATION) * 0.3
	else:
		damage_overlay.color.a = 0.0

	# Ecran de mort
	if player.is_dead:
		death_overlay.visible = true
		death_overlay.color.a = lerpf(death_overlay.color.a, 0.7, delta * 3.0)
		death_label.text = Locale.tr_ui("you_died")
	else:
		if death_overlay.visible:
			death_overlay.visible = false
			death_overlay.color.a = 0.0
