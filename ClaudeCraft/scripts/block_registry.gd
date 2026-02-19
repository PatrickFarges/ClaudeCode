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
		"hardness": 0.0,
		"faces": {}
	},
	BlockType.GRASS: {
		"name": "Grass",
		"solid": true,
		"color": Color(0.6, 0.9, 0.6, 1.0),
		"hardness": 0.6,
		"faces": { "top": "grass_block_top", "side": "grass_block_side", "bottom": "dirt" }
	},
	BlockType.DIRT: {
		"name": "Dirt",
		"solid": true,
		"color": Color(0.75, 0.6, 0.5, 1.0),
		"hardness": 0.5,
		"faces": { "all": "dirt" }
	},
	BlockType.STONE: {
		"name": "Stone",
		"solid": true,
		"color": Color(0.7, 0.7, 0.75, 1.0),
		"hardness": 1.5,
		"faces": { "all": "stone" }
	},
	BlockType.SAND: {
		"name": "Sand",
		"solid": true,
		"color": Color(0.95, 0.9, 0.7, 1.0),
		"hardness": 0.4,
		"faces": { "all": "sand" }
	},
	BlockType.WOOD: {
		"name": "Wood",
		"solid": true,
		"color": Color(0.8, 0.65, 0.5, 1.0),
		"hardness": 1.0,
		"faces": { "top": "oak_log_top", "bottom": "oak_log_top", "side": "oak_log" }
	},
	BlockType.LEAVES: {
		"name": "Leaves",
		"solid": true,
		"color": Color(0.65, 0.85, 0.65, 1.0),
		"hardness": 0.2,
		"faces": { "all": "oak_leaves" }
	},
	BlockType.SNOW: {
		"name": "Snow",
		"solid": true,
		"color": Color(0.95, 0.95, 1.0, 1.0),
		"hardness": 0.3,
		"faces": { "all": "snow" }
	},
	BlockType.CACTUS: {
		"name": "Cactus",
		"solid": true,
		"color": Color(0.5, 0.75, 0.5, 1.0),
		"hardness": 0.3,
		"faces": { "top": "cactus_top", "bottom": "cactus_bottom", "side": "cactus_side" }
	},
	BlockType.DARK_GRASS: {
		"name": "Dark Grass",
		"solid": true,
		"color": Color(0.4, 0.7, 0.4, 1.0),
		"hardness": 0.6,
		"faces": { "top": "grass_block_top", "side": "grass_block_side", "bottom": "dirt" }
	},
	BlockType.GRAVEL: {
		"name": "Gravel",
		"solid": true,
		"color": Color(0.5, 0.5, 0.55, 1.0),
		"hardness": 0.7,
		"faces": { "all": "gravel" }
	},
	# === BLOCS CRAFTABLES ===
	BlockType.PLANKS: {
		"name": "Planks",
		"solid": true,
		"color": Color(0.85, 0.72, 0.5, 1.0),
		"hardness": 0.8,
		"faces": { "all": "oak_planks" }
	},
	BlockType.CRAFTING_TABLE: {
		"name": "Craft Table",
		"solid": true,
		"color": Color(0.55, 0.35, 0.2, 1.0),
		"hardness": 1.0,
		"faces": { "top": "crafting_table_top", "front": "crafting_table_front", "side": "crafting_table_side", "bottom": "oak_planks" }
	},
	BlockType.BRICK: {
		"name": "Brick",
		"solid": true,
		"color": Color(0.8, 0.5, 0.4, 1.0),
		"hardness": 2.0,
		"faces": { "all": "bricks" }
	},
	BlockType.SANDSTONE: {
		"name": "Sandstone",
		"solid": true,
		"color": Color(0.9, 0.82, 0.6, 1.0),
		"hardness": 1.2,
		"faces": { "top": "sandstone_top", "bottom": "sandstone_bottom", "side": "sandstone_side" }
	},
	# === BLOCS NATURELS ===
	BlockType.WATER: {
		"name": "Water",
		"solid": false,
		"color": Color(0.3, 0.5, 0.9, 0.6),
		"hardness": 0.0,
		"faces": {}
	},
	BlockType.COAL_ORE: {
		"name": "Coal Ore",
		"solid": true,
		"color": Color(0.25, 0.25, 0.3, 1.0),
		"hardness": 1.8,
		"faces": { "all": "coal_ore" }
	},
	BlockType.IRON_ORE: {
		"name": "Iron Ore",
		"solid": true,
		"color": Color(0.75, 0.6, 0.55, 1.0),
		"hardness": 2.0,
		"faces": { "all": "iron_ore" }
	},
	BlockType.GOLD_ORE: {
		"name": "Gold Ore",
		"solid": true,
		"color": Color(0.85, 0.75, 0.3, 1.0),
		"hardness": 2.5,
		"faces": { "all": "gold_ore" }
	},
	# === BLOCS FONDUS ===
	BlockType.IRON_INGOT: {
		"name": "Iron Ingot",
		"solid": true,
		"color": Color(0.8, 0.8, 0.85, 1.0),
		"hardness": 1.5,
		"faces": { "all": "iron_block" }
	},
	BlockType.GOLD_INGOT: {
		"name": "Gold Ingot",
		"solid": true,
		"color": Color(0.95, 0.85, 0.3, 1.0),
		"hardness": 1.0,
		"faces": { "all": "gold_block" }
	},
	# === STATIONS DE CRAFT ===
	BlockType.FURNACE: {
		"name": "Furnace",
		"solid": true,
		"color": Color(0.45, 0.45, 0.5, 1.0),
		"hardness": 2.0,
		"faces": { "top": "furnace_top", "bottom": "furnace_top", "front": "furnace_front", "side": "furnace_side" }
	},
	BlockType.STONE_TABLE: {
		"name": "Stone Table",
		"solid": true,
		"color": Color(0.6, 0.55, 0.5, 1.0),
		"hardness": 1.8,
		"faces": { "all": "stone_bricks" }
	},
	BlockType.IRON_TABLE: {
		"name": "Iron Table",
		"solid": true,
		"color": Color(0.65, 0.6, 0.6, 1.0),
		"hardness": 2.5,
		"faces": { "all": "iron_block" }
	},
	BlockType.GOLD_TABLE: {
		"name": "Gold Table",
		"solid": true,
		"color": Color(0.75, 0.65, 0.3, 1.0),
		"hardness": 2.0,
		"faces": { "all": "gold_block" }
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

static func get_face_texture(block_type: BlockType, face: String) -> String:
	var faces: Dictionary = BLOCK_DATA[block_type].get("faces", {})
	if faces.has(face):
		return faces[face]
	if face in ["front", "back", "left", "right"] and faces.has("side"):
		return faces["side"]
	if faces.has("all"):
		return faces["all"]
	return "dirt"

static func is_workstation(block_type) -> bool:
	return block_type in [BlockType.CRAFTING_TABLE, BlockType.FURNACE,
		BlockType.STONE_TABLE, BlockType.IRON_TABLE, BlockType.GOLD_TABLE]

static func get_block_tint(block_type: BlockType, face: String = "all") -> Color:
	match block_type:
		BlockType.GRASS:
			if face == "top":
				return Color(0.55, 0.9, 0.4, 1.0)
			return Color(1.0, 1.0, 1.0, 1.0)
		BlockType.DARK_GRASS:
			if face == "top":
				return Color(0.35, 0.65, 0.3, 1.0)
			return Color(0.75, 0.85, 0.75, 1.0)
		BlockType.LEAVES:
			return Color(0.47, 0.82, 0.35, 1.0)
		_:
			return Color(1.0, 1.0, 1.0, 1.0)
