extends Node
class_name BlockRegistry

enum BlockType {
	AIR,
	GRASS,
	DIRT,
	STONE,
	SAND,
	WOOD,
	LEAVES,
	SNOW,
	CACTUS,
	DARK_GRASS,
	GRAVEL,
	# Nouveaux blocs craftables
	PLANKS,
	CRAFTING_TABLE,
	BRICK,
	SANDSTONE,
	# Blocs naturels supplémentaires
	WATER,
	COAL_ORE,
	IRON_ORE,
	GOLD_ORE,
	# Blocs fondus
	IRON_INGOT,
	GOLD_INGOT,
	# Stations de craft
	FURNACE,
	STONE_TABLE,
	IRON_TABLE,
	GOLD_TABLE
}

const BLOCK_DATA = {
	BlockType.AIR: {
		"name": "Air",
		"solid": false,
		"color": Color(0, 0, 0, 0),
		"hardness": 0.0
	},
	BlockType.GRASS: {
		"name": "Grass",
		"solid": true,
		"color": Color(0.6, 0.9, 0.6, 1.0),
		"hardness": 0.6
	},
	BlockType.DIRT: {
		"name": "Dirt",
		"solid": true,
		"color": Color(0.75, 0.6, 0.5, 1.0),
		"hardness": 0.5
	},
	BlockType.STONE: {
		"name": "Stone",
		"solid": true,
		"color": Color(0.7, 0.7, 0.75, 1.0),
		"hardness": 1.5
	},
	BlockType.SAND: {
		"name": "Sand",
		"solid": true,
		"color": Color(0.95, 0.9, 0.7, 1.0),
		"hardness": 0.4
	},
	BlockType.WOOD: {
		"name": "Wood",
		"solid": true,
		"color": Color(0.8, 0.65, 0.5, 1.0),
		"hardness": 1.0
	},
	BlockType.LEAVES: {
		"name": "Leaves",
		"solid": true,
		"color": Color(0.65, 0.85, 0.65, 1.0),
		"hardness": 0.2
	},
	BlockType.SNOW: {
		"name": "Snow",
		"solid": true,
		"color": Color(0.95, 0.95, 1.0, 1.0),
		"hardness": 0.3
	},
	BlockType.CACTUS: {
		"name": "Cactus",
		"solid": true,
		"color": Color(0.5, 0.75, 0.5, 1.0),
		"hardness": 0.3
	},
	BlockType.DARK_GRASS: {
		"name": "Dark Grass",
		"solid": true,
		"color": Color(0.4, 0.7, 0.4, 1.0),
		"hardness": 0.6
	},
	BlockType.GRAVEL: {
		"name": "Gravel",
		"solid": true,
		"color": Color(0.5, 0.5, 0.55, 1.0),
		"hardness": 0.7
	},
	# === BLOCS CRAFTABLES ===
	BlockType.PLANKS: {
		"name": "Planks",
		"solid": true,
		"color": Color(0.85, 0.72, 0.5, 1.0),
		"hardness": 0.8
	},
	BlockType.CRAFTING_TABLE: {
		"name": "Craft Table",
		"solid": true,
		"color": Color(0.55, 0.35, 0.2, 1.0),
		"hardness": 1.0
	},
	BlockType.BRICK: {
		"name": "Brick",
		"solid": true,
		"color": Color(0.8, 0.5, 0.4, 1.0),
		"hardness": 2.0
	},
	BlockType.SANDSTONE: {
		"name": "Sandstone",
		"solid": true,
		"color": Color(0.9, 0.82, 0.6, 1.0),
		"hardness": 1.2
	},
	# === BLOCS NATURELS ===
	BlockType.WATER: {
		"name": "Water",
		"solid": false,
		"color": Color(0.3, 0.5, 0.9, 0.6),
		"hardness": 0.0
	},
	BlockType.COAL_ORE: {
		"name": "Coal Ore",
		"solid": true,
		"color": Color(0.25, 0.25, 0.3, 1.0),
		"hardness": 1.8
	},
	BlockType.IRON_ORE: {
		"name": "Iron Ore",
		"solid": true,
		"color": Color(0.75, 0.6, 0.55, 1.0),
		"hardness": 2.0
	},
	BlockType.GOLD_ORE: {
		"name": "Gold Ore",
		"solid": true,
		"color": Color(0.85, 0.75, 0.3, 1.0),
		"hardness": 2.5
	},
	# === BLOCS FONDUS ===
	BlockType.IRON_INGOT: {
		"name": "Iron Ingot",
		"solid": true,
		"color": Color(0.8, 0.8, 0.85, 1.0),
		"hardness": 1.5
	},
	BlockType.GOLD_INGOT: {
		"name": "Gold Ingot",
		"solid": true,
		"color": Color(0.95, 0.85, 0.3, 1.0),
		"hardness": 1.0
	},
	# === STATIONS DE CRAFT ===
	BlockType.FURNACE: {
		"name": "Furnace",
		"solid": true,
		"color": Color(0.45, 0.45, 0.5, 1.0),
		"hardness": 2.0
	},
	BlockType.STONE_TABLE: {
		"name": "Stone Table",
		"solid": true,
		"color": Color(0.6, 0.55, 0.5, 1.0),
		"hardness": 1.8
	},
	BlockType.IRON_TABLE: {
		"name": "Iron Table",
		"solid": true,
		"color": Color(0.65, 0.6, 0.6, 1.0),
		"hardness": 2.5
	},
	BlockType.GOLD_TABLE: {
		"name": "Gold Table",
		"solid": true,
		"color": Color(0.75, 0.65, 0.3, 1.0),
		"hardness": 2.0
	}
}

static func get_block_color(block_type: BlockType) -> Color:
	return BLOCK_DATA[block_type]["color"]

static func is_solid(block_type: BlockType) -> bool:
	return BLOCK_DATA[block_type]["solid"]

static func get_block_name(block_type: BlockType) -> String:
	var key = BLOCK_DATA[block_type]["name"]
	return Locale.tr_block(key)

static func get_block_hardness(block_type: BlockType) -> float:
	return BLOCK_DATA[block_type]["hardness"]
