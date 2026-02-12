extends Node

@export var day_duration: float = 600.0  # Secondes pour un cycle complet (10 min)
@export var start_time: float = 0.3      # 0=minuit, 0.25=aube, 0.5=midi, 0.75=crépuscule

var current_time: float = 0.3
var sun: DirectionalLight3D
var env: Environment

# Couleurs du ciel
const SKY_DAY = Color(0.7, 0.85, 0.95)
const SKY_NIGHT = Color(0.05, 0.05, 0.2)
const SKY_DAWN = Color(0.95, 0.55, 0.35)

# Couleurs du soleil
const SUN_DAY = Color(1.0, 0.95, 0.9)
const SUN_DAWN = Color(1.0, 0.6, 0.35)
const SUN_NIGHT = Color(0.3, 0.35, 0.6)

func _ready():
	current_time = start_time
	sun = get_parent().get_node("DirectionalLight3D")
	var world_env: WorldEnvironment = get_parent().get_node("WorldEnvironment")
	env = world_env.environment
	add_to_group("day_night_cycle")

func _process(delta):
	current_time += delta / day_duration
	if current_time >= 1.0:
		current_time -= 1.0

	# Hauteur du soleil : -1 (minuit) à 1 (midi)
	var sun_height: float = -cos(current_time * TAU)

	_update_sun_transform()
	_update_sun_light(sun_height)
	_update_sky(sun_height)
	_update_ambient(sun_height)

func _update_sun_transform():
	# Rotation complète sur 24h, -30° en Y pour des ombres en biais
	var angle: float = current_time * 360.0 - 90.0
	sun.rotation_degrees = Vector3(-angle, -30.0, 0.0)

func _update_sun_light(sun_height: float):
	if sun_height > 0.2:
		# Jour
		sun.light_energy = 0.8
		sun.light_color = SUN_DAY
		sun.shadow_enabled = true
	elif sun_height > -0.1:
		# Aube / Crépuscule
		var t: float = (sun_height + 0.1) / 0.3
		sun.light_energy = lerpf(0.05, 0.8, t)
		sun.light_color = SUN_DAWN.lerp(SUN_DAY, t)
		sun.shadow_enabled = true
	else:
		# Nuit
		sun.light_energy = 0.05
		sun.light_color = SUN_NIGHT
		sun.shadow_enabled = false

func _update_sky(sun_height: float):
	var sky_color: Color
	if sun_height > 0.15:
		sky_color = SKY_DAY
	elif sun_height > 0.0:
		sky_color = SKY_DAWN.lerp(SKY_DAY, sun_height / 0.15)
	elif sun_height > -0.15:
		sky_color = SKY_NIGHT.lerp(SKY_DAWN, (sun_height + 0.15) / 0.15)
	else:
		sky_color = SKY_NIGHT
	env.background_color = sky_color
	env.fog_light_color = sky_color

func _update_ambient(sun_height: float):
	if sun_height > 0.1:
		# Jour
		env.ambient_light_energy = 0.8
		env.ambient_light_color = Color.WHITE
	elif sun_height > -0.1:
		# Transition
		var t: float = (sun_height + 0.1) / 0.2
		env.ambient_light_energy = lerpf(0.2, 0.8, t)
		env.ambient_light_color = Color(0.4, 0.45, 0.7).lerp(Color.WHITE, t)
	else:
		# Nuit — lumière bleutée type clair de lune
		env.ambient_light_energy = 0.2
		env.ambient_light_color = Color(0.4, 0.45, 0.7)

func get_time_string() -> String:
	var hours: int = int(current_time * 24.0) % 24
	var minutes: int = int(current_time * 24.0 * 60.0) % 60
	return "%02d:%02d" % [hours, minutes]

func get_current_time() -> float:
	return current_time
