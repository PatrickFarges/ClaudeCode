extends Node
class_name ToolRegistry

## Registre des outils disponibles : modèles 3D, vitesses de minage, durabilité

enum ToolType {
	NONE,
	STONE_AXE,
	STONE_PICKAXE,
	STONE_SHOVEL,
	STONE_HOE,
	STONE_HAMMER,
	DIAMOND_AXE,
	DIAMOND_PICKAXE,
	IRON_PICKAXE,
	STONE_SWORD,
	DIAMOND_SWORD,
	NETHERITE_SWORD,
	BOW,
	SHIELD,
}

const TOOL_DATA = {
	ToolType.STONE_AXE: {
		"name": "Hache en pierre",
		"model_path": "res://assets/Weapon/Stone Tools/models/Stone_Axe.json",
		"texture_path": "res://assets/Weapon/Stone Tools/textures/",
		"mining_speed": {
			"WOOD": 2.0, "PLANKS": 2.0, "LEAVES": 1.5, "CRAFTING_TABLE": 1.5,
			"SPRUCE_LOG": 2.0, "BIRCH_LOG": 2.0, "JUNGLE_LOG": 2.0,
			"ACACIA_LOG": 2.0, "DARK_OAK_LOG": 2.0, "CHERRY_LOG": 2.0,
			"SPRUCE_PLANKS": 2.0, "BIRCH_PLANKS": 2.0, "JUNGLE_PLANKS": 2.0,
			"ACACIA_PLANKS": 2.0, "DARK_OAK_PLANKS": 2.0, "CHERRY_PLANKS": 2.0,
			"BOOKSHELF": 2.0, "BARREL": 2.0,
		},
		"durability": 132
	},
	ToolType.STONE_PICKAXE: {
		"name": "Pioche en pierre",
		"model_path": "res://assets/Weapon/Stone Tools/models/Stone_Pickaxe.json",
		"texture_path": "res://assets/Weapon/Stone Tools/textures/",
		"mining_speed": {
			"STONE": 2.0, "BRICK": 2.0, "SANDSTONE": 2.0,
			"COAL_ORE": 2.0, "IRON_ORE": 2.0, "GOLD_ORE": 2.0,
			"COPPER_ORE": 2.0, "DIAMOND_ORE": 2.0, "FURNACE": 1.5,
			"COBBLESTONE": 2.0, "MOSSY_COBBLESTONE": 2.0,
			"ANDESITE": 2.0, "GRANITE": 2.0, "DIORITE": 2.0,
			"DEEPSLATE": 2.0, "SMOOTH_STONE": 2.0,
		},
		"durability": 132
	},
	ToolType.STONE_SHOVEL: {
		"name": "Pelle en pierre",
		"model_path": "res://assets/Weapon/Stone Tools/models/Stone_Shovel.json",
		"texture_path": "res://assets/Weapon/Stone Tools/textures/",
		"mining_speed": {
			"DIRT": 2.0, "GRASS": 2.0, "DARK_GRASS": 2.0,
			"SAND": 2.0, "GRAVEL": 2.0, "SNOW": 2.0,
			"CLAY": 2.0, "PODZOL": 2.0, "MOSS_BLOCK": 2.0,
		},
		"durability": 132
	},
	ToolType.STONE_HOE: {
		"name": "Houe en pierre",
		"model_path": "res://assets/Weapon/Stone Tools/models/Stone_Hoe.json",
		"texture_path": "res://assets/Weapon/Stone Tools/textures/",
		"mining_speed": {
			"LEAVES": 3.0, "SPRUCE_LEAVES": 3.0, "BIRCH_LEAVES": 3.0,
			"JUNGLE_LEAVES": 3.0, "ACACIA_LEAVES": 3.0, "DARK_OAK_LEAVES": 3.0,
			"CHERRY_LEAVES": 3.0, "HAY_BLOCK": 3.0,
		},
		"durability": 132
	},
	ToolType.STONE_HAMMER: {
		"name": "Marteau en pierre",
		"model_path": "res://assets/Weapon/Stone Tools/models/Stone_Hammer.json",
		"texture_path": "res://assets/Weapon/Stone Tools/textures/",
		"mining_speed": {
			"STONE": 1.5,
			"BRICK": 1.5,
		},
		"durability": 132
	},
	ToolType.DIAMOND_AXE: {
		"name": "Hache en diamant",
		"model_path": "res://assets/Weapon/GLB/diamond_axe_minecraft.glb",
		"texture_path": "",
		"mining_speed": {
			"WOOD": 4.0, "PLANKS": 4.0, "LEAVES": 3.0, "CRAFTING_TABLE": 3.0,
			"SPRUCE_LOG": 4.0, "BIRCH_LOG": 4.0, "JUNGLE_LOG": 4.0,
			"ACACIA_LOG": 4.0, "DARK_OAK_LOG": 4.0, "CHERRY_LOG": 4.0,
			"SPRUCE_PLANKS": 4.0, "BIRCH_PLANKS": 4.0, "JUNGLE_PLANKS": 4.0,
			"ACACIA_PLANKS": 4.0, "DARK_OAK_PLANKS": 4.0, "CHERRY_PLANKS": 4.0,
			"BOOKSHELF": 4.0, "BARREL": 4.0,
		},
		"durability": 1561,
		"hand_rotation": Vector3(-25, -135, 45),
		"hand_scale": 0.35,
	},
	ToolType.DIAMOND_PICKAXE: {
		"name": "Pioche en diamant",
		"model_path": "res://assets/Weapon/GLB/minecraft_diamond-pickaxe.glb",
		"texture_path": "",
		"mining_speed": {
			"STONE": 4.0, "BRICK": 4.0, "SANDSTONE": 4.0,
			"COAL_ORE": 4.0, "IRON_ORE": 4.0, "GOLD_ORE": 4.0,
			"COPPER_ORE": 4.0, "DIAMOND_ORE": 4.0, "FURNACE": 3.0,
			"COBBLESTONE": 4.0, "MOSSY_COBBLESTONE": 4.0,
			"ANDESITE": 4.0, "GRANITE": 4.0, "DIORITE": 4.0,
			"DEEPSLATE": 4.0, "SMOOTH_STONE": 4.0,
		},
		"durability": 1561,
		"hand_rotation": Vector3(-25, -135, 45),
		"hand_scale": 0.35,
	},
	ToolType.IRON_PICKAXE: {
		"name": "Pioche en fer",
		"model_path": "res://assets/Weapon/GLB/minecraft_iron_pickaxe.glb",
		"texture_path": "",
		"mining_speed": {
			"STONE": 3.0, "BRICK": 3.0, "SANDSTONE": 3.0,
			"COAL_ORE": 3.0, "IRON_ORE": 3.0, "GOLD_ORE": 3.0,
			"COPPER_ORE": 3.0, "DIAMOND_ORE": 3.0, "FURNACE": 2.0,
			"COBBLESTONE": 3.0, "MOSSY_COBBLESTONE": 3.0,
			"ANDESITE": 3.0, "GRANITE": 3.0, "DIORITE": 3.0,
			"DEEPSLATE": 3.0, "SMOOTH_STONE": 3.0,
		},
		"durability": 250,
		"hand_rotation": Vector3(-25, -135, 45),
		"hand_scale": 0.35,
	},
	ToolType.STONE_SWORD: {
		"name": "Épée en pierre",
		"model_path": "res://assets/Weapon/GLB/minecraft_stone_sword.glb",
		"texture_path": "",
		"mining_speed": {},
		"durability": 132,
		"hand_rotation": Vector3(-25, -135, 45),
		"hand_scale": 0.35,
	},
	ToolType.DIAMOND_SWORD: {
		"name": "Épée en diamant",
		"model_path": "res://assets/Weapon/GLB/minecraft_diamond_sword_pre1.14.glb",
		"texture_path": "",
		"mining_speed": {},
		"durability": 1561,
		"hand_rotation": Vector3(-25, -135, 45),
		"hand_scale": 0.35,
	},
	ToolType.NETHERITE_SWORD: {
		"name": "Épée en Netherite",
		"model_path": "res://assets/Weapon/GLB/mincraft_nethrite_sword.glb",
		"texture_path": "",
		"mining_speed": {},
		"durability": 2031,
		"hand_rotation": Vector3(-25, -135, 45),
		"hand_scale": 0.35,
	},
	ToolType.BOW: {
		"name": "Arc",
		"model_path": "res://assets/Weapon/GLB/minecraft_bow.glb",
		"texture_path": "",
		"mining_speed": {},
		"durability": 384,
		"hand_rotation": Vector3(0, -90, 15),
		"hand_scale": 0.35,
	},
	ToolType.SHIELD: {
		"name": "Bouclier",
		"model_path": "res://assets/Weapon/GLB/minecraft_shield.glb",
		"texture_path": "",
		"mining_speed": {},
		"durability": 336,
		"hand_rotation": Vector3(10, 0, 0),
		"hand_scale": 0.42,
	},
}

static func get_tool_name(tool_type: ToolType) -> String:
	if TOOL_DATA.has(tool_type):
		return TOOL_DATA[tool_type]["name"]
	return ""

static func get_model_path(tool_type: ToolType) -> String:
	if TOOL_DATA.has(tool_type):
		return TOOL_DATA[tool_type]["model_path"]
	return ""

static func get_texture_path(tool_type: ToolType) -> String:
	if TOOL_DATA.has(tool_type):
		return TOOL_DATA[tool_type]["texture_path"]
	return ""

static func get_hand_rotation(tool_type: ToolType) -> Vector3:
	if TOOL_DATA.has(tool_type) and TOOL_DATA[tool_type].has("hand_rotation"):
		return TOOL_DATA[tool_type]["hand_rotation"]
	return Vector3(-25, -135, 45)

static func get_hand_scale(tool_type: ToolType) -> float:
	if TOOL_DATA.has(tool_type) and TOOL_DATA[tool_type].has("hand_scale"):
		return TOOL_DATA[tool_type]["hand_scale"]
	return 0.35

static func get_mining_multiplier(tool_type: ToolType, block_type: BlockRegistry.BlockType) -> float:
	if tool_type == ToolType.NONE:
		return 1.0
	if not TOOL_DATA.has(tool_type):
		return 1.0
	var speeds: Dictionary = TOOL_DATA[tool_type]["mining_speed"]
	var block_name = BlockRegistry.BlockType.keys()[block_type]
	if speeds.has(block_name):
		return speeds[block_name]
	return 1.0

static func get_tool_mesh(tool_type: ToolType) -> ArrayMesh:
	if tool_type == ToolType.NONE:
		return null
	if not TOOL_DATA.has(tool_type):
		return null
	var model_path = TOOL_DATA[tool_type]["model_path"]
	var texture_path = TOOL_DATA[tool_type]["texture_path"]
	return ItemModelLoader.load_model(model_path, texture_path)

## Retourne un Node3D prêt à l'emploi — GLB (instantié) ou JSON (MeshInstance3D)
static func get_tool_node(tool_type: ToolType) -> Node3D:
	if tool_type == ToolType.NONE or not TOOL_DATA.has(tool_type):
		return null
	var model_path: String = TOOL_DATA[tool_type]["model_path"]

	if model_path.ends_with(".glb") or model_path.ends_with(".gltf"):
		# Charger la scène GLB directement
		var scene = load(model_path) as PackedScene
		if scene:
			return scene.instantiate()
		push_warning("[ToolRegistry] Impossible de charger GLB: " + model_path)
		return null
	else:
		# JSON Blockbench → ArrayMesh → MeshInstance3D
		var texture_path = TOOL_DATA[tool_type]["texture_path"]
		var mesh = ItemModelLoader.load_model(model_path, texture_path)
		if mesh:
			var inst = MeshInstance3D.new()
			inst.mesh = mesh
			return inst
		return null
