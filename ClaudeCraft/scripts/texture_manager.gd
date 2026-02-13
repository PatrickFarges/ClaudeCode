extends Node

const TEXTURE_PATH = "res://TexturesPack/Aurore Stone/assets/minecraft/textures/block/"

# Liste ordonnée des textures — chaque entrée = une couche du Texture2DArray
const TEXTURE_LIST: Array[String] = [
	"grass_block_top",   # 0
	"grass_block_side",  # 1
	"dirt",              # 2
	"stone",             # 3
	"sand",              # 4
	"oak_log",           # 5
	"oak_log_top",       # 6
	"oak_leaves",        # 7
	"snow",              # 8
	"cactus_side",       # 9
	"cactus_top",        # 10
	"cactus_bottom",     # 11
	"gravel",            # 12
	"oak_planks",        # 13
	"crafting_table_top", # 14
	"crafting_table_side", # 15
	"crafting_table_front", # 16
	"bricks",            # 17
	"sandstone_top",     # 18
	"sandstone_side",    # 19
	"sandstone_bottom",  # 20
	"coal_ore",          # 21
	"iron_ore",          # 22
	"gold_ore",          # 23
	"iron_block",        # 24
	"gold_block",        # 25
	"furnace_front",     # 26
	"furnace_side",      # 27
	"furnace_top",       # 28
	"stone_bricks",      # 29
]

var _texture_array: Texture2DArray
var _layer_map: Dictionary = {}
var _shared_material: ShaderMaterial

func _ready():
	# Construire le lookup name → index
	for i in range(TEXTURE_LIST.size()):
		_layer_map[TEXTURE_LIST[i]] = i

	# Charger les images (Image.load_from_file bypasse le système d'import Godot)
	var images: Array[Image] = []
	for tex_name in TEXTURE_LIST:
		var path = TEXTURE_PATH + tex_name + ".png"
		var abs_path = ProjectSettings.globalize_path(path)
		var img := Image.new()
		var err = img.load(abs_path)
		if err != OK:
			img = _fallback_color_image(tex_name)
			print("[TextureManager] Fallback pour: ", tex_name)
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != 16 or img.get_height() != 16:
			img.resize(16, 16, Image.INTERPOLATE_NEAREST)
		images.append(img)

	# Construire le Texture2DArray
	_texture_array = Texture2DArray.new()
	_texture_array.create_from_images(images)

	# Créer le ShaderMaterial partagé
	var shader = load("res://shaders/block_texture_array.gdshader") as Shader
	_shared_material = ShaderMaterial.new()
	_shared_material.shader = shader
	_shared_material.set_shader_parameter("block_textures", _texture_array)

func get_layer_index(texture_name: String) -> int:
	if _layer_map.has(texture_name):
		return _layer_map[texture_name]
	return 2  # fallback: dirt

func get_shared_material() -> ShaderMaterial:
	return _shared_material

func _fallback_color_image(tex_name: String) -> Image:
	var color := Color(0.75, 0.6, 0.5, 1.0)  # dirt par défaut
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img
