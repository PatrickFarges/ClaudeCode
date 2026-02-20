extends Node
class_name ToolRegistry

## Registre des outils — utilise les textures d'items du pack actif (flat sprites Minecraft-style)

enum ToolType {
	NONE,
	STONE_AXE,
	STONE_PICKAXE,
	STONE_SHOVEL,
	STONE_HOE,
	STONE_HAMMER,
	STONE_SWORD,
	IRON_PICKAXE,
	IRON_SWORD,
	DIAMOND_AXE,
	DIAMOND_PICKAXE,
	DIAMOND_SWORD,
	NETHERITE_SWORD,
	BOW,
	SHIELD,
}

const TOOL_DATA = {
	ToolType.STONE_AXE: {
		"name": "Hache en pierre",
		"item_texture": "stone_axe",
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
		"item_texture": "stone_pickaxe",
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
		"item_texture": "stone_shovel",
		"mining_speed": {
			"DIRT": 2.0, "GRASS": 2.0, "DARK_GRASS": 2.0,
			"SAND": 2.0, "GRAVEL": 2.0, "SNOW": 2.0,
			"CLAY": 2.0, "PODZOL": 2.0, "MOSS_BLOCK": 2.0,
		},
		"durability": 132
	},
	ToolType.STONE_HOE: {
		"name": "Houe en pierre",
		"item_texture": "stone_hoe",
		"mining_speed": {
			"LEAVES": 3.0, "SPRUCE_LEAVES": 3.0, "BIRCH_LEAVES": 3.0,
			"JUNGLE_LEAVES": 3.0, "ACACIA_LEAVES": 3.0, "DARK_OAK_LEAVES": 3.0,
			"CHERRY_LEAVES": 3.0, "HAY_BLOCK": 3.0,
		},
		"durability": 132
	},
	ToolType.STONE_HAMMER: {
		"name": "Marteau en pierre",
		"item_texture": "stone_pickaxe",  # pas de texture hammer dans MC, on reutilise pickaxe
		"mining_speed": {
			"STONE": 1.5,
			"BRICK": 1.5,
		},
		"durability": 132
	},
	ToolType.STONE_SWORD: {
		"name": "Epee en pierre",
		"item_texture": "stone_sword",
		"mining_speed": {},
		"durability": 132,
	},
	ToolType.IRON_PICKAXE: {
		"name": "Pioche en fer",
		"item_texture": "iron_pickaxe",
		"mining_speed": {
			"STONE": 3.0, "BRICK": 3.0, "SANDSTONE": 3.0,
			"COAL_ORE": 3.0, "IRON_ORE": 3.0, "GOLD_ORE": 3.0,
			"COPPER_ORE": 3.0, "DIAMOND_ORE": 3.0, "FURNACE": 2.0,
			"COBBLESTONE": 3.0, "MOSSY_COBBLESTONE": 3.0,
			"ANDESITE": 3.0, "GRANITE": 3.0, "DIORITE": 3.0,
			"DEEPSLATE": 3.0, "SMOOTH_STONE": 3.0,
		},
		"durability": 250,
	},
	ToolType.IRON_SWORD: {
		"name": "Epee en fer",
		"item_texture": "iron_sword",
		"mining_speed": {},
		"durability": 250,
	},
	ToolType.DIAMOND_AXE: {
		"name": "Hache en diamant",
		"item_texture": "diamond_axe",
		"mining_speed": {
			"WOOD": 4.0, "PLANKS": 4.0, "LEAVES": 3.0, "CRAFTING_TABLE": 3.0,
			"SPRUCE_LOG": 4.0, "BIRCH_LOG": 4.0, "JUNGLE_LOG": 4.0,
			"ACACIA_LOG": 4.0, "DARK_OAK_LOG": 4.0, "CHERRY_LOG": 4.0,
			"SPRUCE_PLANKS": 4.0, "BIRCH_PLANKS": 4.0, "JUNGLE_PLANKS": 4.0,
			"ACACIA_PLANKS": 4.0, "DARK_OAK_PLANKS": 4.0, "CHERRY_PLANKS": 4.0,
			"BOOKSHELF": 4.0, "BARREL": 4.0,
		},
		"durability": 1561,
	},
	ToolType.DIAMOND_PICKAXE: {
		"name": "Pioche en diamant",
		"item_texture": "diamond_pickaxe",
		"mining_speed": {
			"STONE": 4.0, "BRICK": 4.0, "SANDSTONE": 4.0,
			"COAL_ORE": 4.0, "IRON_ORE": 4.0, "GOLD_ORE": 4.0,
			"COPPER_ORE": 4.0, "DIAMOND_ORE": 4.0, "FURNACE": 3.0,
			"COBBLESTONE": 4.0, "MOSSY_COBBLESTONE": 4.0,
			"ANDESITE": 4.0, "GRANITE": 4.0, "DIORITE": 4.0,
			"DEEPSLATE": 4.0, "SMOOTH_STONE": 4.0,
		},
		"durability": 1561,
	},
	ToolType.DIAMOND_SWORD: {
		"name": "Epee en diamant",
		"item_texture": "diamond_sword",
		"mining_speed": {},
		"durability": 1561,
	},
	ToolType.NETHERITE_SWORD: {
		"name": "Epee en Netherite",
		"item_texture": "netherite_sword",
		"mining_speed": {},
		"durability": 2031,
	},
	ToolType.BOW: {
		"name": "Arc",
		"item_texture": "bow",
		"mining_speed": {},
		"durability": 384,
	},
	ToolType.SHIELD: {
		"name": "Bouclier",
		"item_texture": "shield_base_nopattern",
		"item_texture_folder": "entity",  # shield est dans entity/, pas item/
		"mining_speed": {},
		"durability": 336,
	},
}

static func get_tool_name(tool_type: ToolType) -> String:
	if TOOL_DATA.has(tool_type):
		return TOOL_DATA[tool_type]["name"]
	return ""

static func get_item_texture_name(tool_type: ToolType) -> String:
	if TOOL_DATA.has(tool_type):
		return TOOL_DATA[tool_type]["item_texture"]
	return ""

static func get_item_texture_path(tool_type: ToolType) -> String:
	if not TOOL_DATA.has(tool_type):
		return ""
	var data = TOOL_DATA[tool_type]
	var folder = data.get("item_texture_folder", "item")
	var base_path: String
	match folder:
		"entity":
			base_path = GameConfig.get_entity_texture_path()
		_:
			base_path = GameConfig.get_item_texture_path()
	return base_path + data["item_texture"] + ".png"

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
