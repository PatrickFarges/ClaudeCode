extends MeshInstance3D

const CLOUD_HEIGHT = 160.0
const CLOUD_PLANE_SIZE = 512.0  # Half-extent

var day_night_cycle = null
var player = null
var cloud_material: ShaderMaterial
var base_opacity: float = 0.8

# Couleurs des nuages selon l'heure
const CLOUD_DAY = Color(1.0, 1.0, 1.0)
const CLOUD_NIGHT = Color(0.12, 0.12, 0.25)
const CLOUD_DAWN = Color(1.0, 0.7, 0.45)

func _ready():
	# Créer le plan des nuages
	var plane = PlaneMesh.new()
	plane.size = Vector2(CLOUD_PLANE_SIZE * 2.0, CLOUD_PLANE_SIZE * 2.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	mesh = plane

	# Charger le shader
	var shader = load("res://shaders/clouds.gdshader")
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = shader
	cloud_material.set_shader_parameter("cloud_color", Color(1, 1, 1))
	cloud_material.set_shader_parameter("cloud_coverage", 0.45)
	cloud_material.set_shader_parameter("cloud_softness", 0.3)
	cloud_material.set_shader_parameter("cloud_opacity", 0.8)
	cloud_material.set_shader_parameter("wind_direction", Vector2(1.0, 0.3))
	cloud_material.set_shader_parameter("wind_speed", 0.01)
	cloud_material.set_shader_parameter("cloud_scale", 0.002)
	cloud_material.set_shader_parameter("edge_fade_start", 0.6)
	material_override = cloud_material

	# Pas d'ombres projetées par les nuages
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	await get_tree().process_frame
	day_night_cycle = get_tree().get_first_node_in_group("day_night_cycle")
	player = get_tree().get_first_node_in_group("player")
	add_to_group("cloud_manager")

func _process(_delta):
	# Suivre le joueur horizontalement
	if player:
		global_position = Vector3(player.global_position.x, CLOUD_HEIGHT, player.global_position.z)

	# Mettre à jour les couleurs selon l'heure
	if day_night_cycle and cloud_material:
		var sun_height: float = -cos(day_night_cycle.current_time * TAU)
		var cloud_color: Color

		if sun_height > 0.15:
			cloud_color = CLOUD_DAY
		elif sun_height > 0.0:
			cloud_color = CLOUD_DAWN.lerp(CLOUD_DAY, sun_height / 0.15)
		elif sun_height > -0.15:
			cloud_color = CLOUD_NIGHT.lerp(CLOUD_DAWN, (sun_height + 0.15) / 0.15)
		else:
			cloud_color = CLOUD_NIGHT

		cloud_material.set_shader_parameter("cloud_color", cloud_color)

		# Réduire l'opacité la nuit (nuages moins visibles dans le noir)
		var night_factor: float = clampf((sun_height + 0.1) / 0.3, 0.0, 1.0)
		var opacity: float = lerpf(base_opacity * 0.35, base_opacity, night_factor)
		cloud_material.set_shader_parameter("cloud_opacity", opacity)

## Appelé par les presets de rendu (version_hud.gd)
func set_cloud_preset(coverage: float, opacity: float, softness: float, speed: float):
	base_opacity = opacity
	if cloud_material:
		cloud_material.set_shader_parameter("cloud_coverage", coverage)
		cloud_material.set_shader_parameter("cloud_softness", softness)
		cloud_material.set_shader_parameter("wind_speed", speed)
