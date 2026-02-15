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
}

const TOOL_DATA = {
	ToolType.STONE_AXE: {
		"name": "Hache en pierre",
		"model_path": "res://assets/Weapon/Stone Tools/models/Stone_Axe.json",
		"texture_path": "res://assets/Weapon/Stone Tools/textures/",
		"mining_speed": {
			"WOOD": 2.0,
			"PLANKS": 2.0,
			"LEAVES": 1.5,
			"CRAFTING_TABLE": 1.5,
		},
		"durability": 132
	},
	ToolType.STONE_PICKAXE: {
		"name": "Pioche en pierre",
		"model_path": "res://assets/Weapon/Stone Tools/models/Stone_Pickaxe.json",
		"texture_path": "res://assets/Weapon/Stone Tools/textures/",
		"mining_speed": {
			"STONE": 2.0,
			"BRICK": 2.0,
			"SANDSTONE": 2.0,
			"COAL_ORE": 2.0,
			"IRON_ORE": 2.0,
			"GOLD_ORE": 2.0,
			"FURNACE": 1.5,
		},
		"durability": 132
	},
	ToolType.STONE_SHOVEL: {
		"name": "Pelle en pierre",
		"model_path": "res://assets/Weapon/Stone Tools/models/Stone_Shovel.json",
		"texture_path": "res://assets/Weapon/Stone Tools/textures/",
		"mining_speed": {
			"DIRT": 2.0,
			"GRASS": 2.0,
			"DARK_GRASS": 2.0,
			"SAND": 2.0,
			"GRAVEL": 2.0,
			"SNOW": 2.0,
		},
		"durability": 132
	},
	ToolType.STONE_HOE: {
		"name": "Houe en pierre",
		"model_path": "res://assets/Weapon/Stone Tools/models/Stone_Hoe.json",
		"texture_path": "res://assets/Weapon/Stone Tools/textures/",
		"mining_speed": {
			"LEAVES": 3.0,
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
