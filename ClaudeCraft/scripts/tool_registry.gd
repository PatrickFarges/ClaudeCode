extends Node
class_name ToolRegistry

## Registre des outils — utilise les textures d'items du pack actif (flat sprites Minecraft-style)

const GC = preload("res://scripts/game_config.gd")

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
	WOOD_AXE,
	WOOD_PICKAXE,
	IRON_AXE,
}

# ============================================================
# TIERS DE MINAGE — Modifier ces valeurs pour ajuster la vitesse
# Formule : temps = (dureté_bloc × BASE_MINING_TIME) / multiplicateur
# BASE_MINING_TIME = 10.0 (défini dans player.gd)
# ============================================================
# Tier      | Const       | Mult  | Tronc (d=1.0) | Pierre (d=1.5)
# Main nue  | (aucun)     | 1.0   | 10.0s          | 15.0s
# Bois      | TIER_WOOD   | 1.667 |  6.0s          |  9.0s
# Pierre    | TIER_STONE  | 2.0   |  5.0s          |  7.5s
# Fer       | TIER_IRON   | 2.5   |  4.0s          |  6.0s
# Diamant   | TIER_DIAMOND| 3.333 |  3.0s          |  4.5s
# Netherite | TIER_NETHER | 4.0   |  2.5s          |  3.75s
# ============================================================
const TIER_WOOD     = 1.667  # 10/6
const TIER_STONE    = 2.0    # 10/5
const TIER_IRON     = 2.5    # 10/4
const TIER_DIAMOND  = 3.333  # 10/3
const TIER_NETHER   = 4.0    # 10/2.5

# Blocs affectés par les haches (bois et dérivés)
const AXE_BLOCKS = {
	"WOOD": true, "PLANKS": true, "CRAFTING_TABLE": true,
	"SPRUCE_LOG": true, "BIRCH_LOG": true, "JUNGLE_LOG": true,
	"ACACIA_LOG": true, "DARK_OAK_LOG": true, "CHERRY_LOG": true,
	"SPRUCE_PLANKS": true, "BIRCH_PLANKS": true, "JUNGLE_PLANKS": true,
	"ACACIA_PLANKS": true, "DARK_OAK_PLANKS": true, "CHERRY_PLANKS": true,
	"BOOKSHELF": true, "BARREL": true,
}

# Blocs affectés par les pioches (pierre et minerais)
const PICK_BLOCKS = {
	"STONE": true, "BRICK": true, "SANDSTONE": true,
	"COAL_ORE": true, "IRON_ORE": true, "GOLD_ORE": true,
	"COPPER_ORE": true, "DIAMOND_ORE": true, "FURNACE": true,
	"COBBLESTONE": true, "MOSSY_COBBLESTONE": true,
	"ANDESITE": true, "GRANITE": true, "DIORITE": true,
	"DEEPSLATE": true, "SMOOTH_STONE": true,
}

# Blocs affectés par les pelles (terre et meubles)
const SHOVEL_BLOCKS = {
	"DIRT": true, "GRASS": true, "DARK_GRASS": true,
	"SAND": true, "GRAVEL": true, "SNOW": true,
	"CLAY": true, "PODZOL": true, "MOSS_BLOCK": true,
}

# Blocs affectés par les houes (feuilles et végétation)
const HOE_BLOCKS = {
	"LEAVES": true, "SPRUCE_LEAVES": true, "BIRCH_LEAVES": true,
	"JUNGLE_LEAVES": true, "ACACIA_LEAVES": true, "DARK_OAK_LEAVES": true,
	"CHERRY_LEAVES": true, "HAY_BLOCK": true,
}

static func _make_speed(blocks: Dictionary, mult: float) -> Dictionary:
	var result = {}
	for block_name in blocks:
		result[block_name] = mult
	return result

const TOOL_DATA = {
	ToolType.WOOD_AXE: {
		"name": "Hache en bois",
		"item_texture": "wooden_axe",
		"mining_speed": {},  # rempli dans _init_tool_speeds()
		"durability": 60,
		"_tier": "WOOD", "_type": "AXE",
	},
	ToolType.WOOD_PICKAXE: {
		"name": "Pioche en bois",
		"item_texture": "wooden_pickaxe",
		"mining_speed": {},
		"durability": 60,
		"_tier": "WOOD", "_type": "PICK",
	},
	ToolType.STONE_AXE: {
		"name": "Hache en pierre",
		"item_texture": "stone_axe",
		"mining_speed": {},
		"durability": 132,
		"_tier": "STONE", "_type": "AXE",
	},
	ToolType.STONE_PICKAXE: {
		"name": "Pioche en pierre",
		"item_texture": "stone_pickaxe",
		"mining_speed": {},
		"durability": 132,
		"_tier": "STONE", "_type": "PICK",
	},
	ToolType.STONE_SHOVEL: {
		"name": "Pelle en pierre",
		"item_texture": "stone_shovel",
		"mining_speed": {},
		"durability": 132,
		"_tier": "STONE", "_type": "SHOVEL",
	},
	ToolType.STONE_HOE: {
		"name": "Houe en pierre",
		"item_texture": "stone_hoe",
		"mining_speed": {},
		"durability": 132,
		"_tier": "STONE", "_type": "HOE",
	},
	ToolType.STONE_HAMMER: {
		"name": "Marteau en pierre",
		"item_texture": "stone_pickaxe",
		"mining_speed": {"STONE": 1.5, "BRICK": 1.5},
		"durability": 132,
	},
	ToolType.STONE_SWORD: {
		"name": "Epee en pierre",
		"item_texture": "stone_sword",
		"mining_speed": {},
		"durability": 132,
	},
	ToolType.IRON_AXE: {
		"name": "Hache en fer",
		"item_texture": "iron_axe",
		"mining_speed": {},
		"durability": 250,
		"_tier": "IRON", "_type": "AXE",
	},
	ToolType.IRON_PICKAXE: {
		"name": "Pioche en fer",
		"item_texture": "iron_pickaxe",
		"mining_speed": {},
		"durability": 250,
		"_tier": "IRON", "_type": "PICK",
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
		"mining_speed": {},
		"durability": 1561,
		"_tier": "DIAMOND", "_type": "AXE",
	},
	ToolType.DIAMOND_PICKAXE: {
		"name": "Pioche en diamant",
		"item_texture": "diamond_pickaxe",
		"mining_speed": {},
		"durability": 1561,
		"_tier": "DIAMOND", "_type": "PICK",
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
		"item_texture_folder": "entity",
		"mining_speed": {},
		"durability": 336,
	},
}

# Remplissage automatique des mining_speed depuis les tiers
static var _speeds_initialized := false

static func _ensure_speeds():
	if _speeds_initialized:
		return
	_speeds_initialized = true
	var tier_map = {"WOOD": TIER_WOOD, "STONE": TIER_STONE, "IRON": TIER_IRON, "DIAMOND": TIER_DIAMOND, "NETHER": TIER_NETHER}
	var type_map = {"AXE": AXE_BLOCKS, "PICK": PICK_BLOCKS, "SHOVEL": SHOVEL_BLOCKS, "HOE": HOE_BLOCKS}
	for tool_type in TOOL_DATA:
		var data = TOOL_DATA[tool_type]
		if data.has("_tier") and data.has("_type"):
			var mult = tier_map.get(data["_tier"], 1.0)
			var blocks = type_map.get(data["_type"], {})
			for block_name in blocks:
				data["mining_speed"][block_name] = mult

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
			base_path = GC.get_entity_texture_path()
		_:
			base_path = GC.get_item_texture_path()
	return base_path + data["item_texture"] + ".png"

static func get_mining_multiplier(tool_type: ToolType, block_type: BlockRegistry.BlockType) -> float:
	_ensure_speeds()
	if tool_type == ToolType.NONE:
		return 1.0
	if not TOOL_DATA.has(tool_type):
		return 1.0
	var speeds: Dictionary = TOOL_DATA[tool_type]["mining_speed"]
	var block_name = BlockRegistry.BlockType.keys()[block_type]
	if speeds.has(block_name):
		return speeds[block_name]
	return 1.0
