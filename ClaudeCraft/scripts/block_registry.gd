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
	# Blocs craftables
	PLANKS,
	CRAFTING_TABLE,
	BRICK,
	SANDSTONE,
	# Blocs naturels
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
	GOLD_TABLE,
	# === VARIANTES DE PIERRE (25-31) ===
	COBBLESTONE,
	MOSSY_COBBLESTONE,
	ANDESITE,
	GRANITE,
	DIORITE,
	DEEPSLATE,
	SMOOTH_STONE,
	# === TYPES DE BOIS (32-43) ===
	SPRUCE_LOG,
	BIRCH_LOG,
	JUNGLE_LOG,
	ACACIA_LOG,
	DARK_OAK_LOG,
	SPRUCE_PLANKS,
	BIRCH_PLANKS,
	JUNGLE_PLANKS,
	ACACIA_PLANKS,
	DARK_OAK_PLANKS,
	CHERRY_LOG,
	CHERRY_PLANKS,
	# === FEUILLAGES (44-49) ===
	SPRUCE_LEAVES,
	BIRCH_LEAVES,
	JUNGLE_LEAVES,
	ACACIA_LEAVES,
	DARK_OAK_LEAVES,
	CHERRY_LEAVES,
	# === MINERAIS (50-51) ===
	DIAMOND_ORE,
	COPPER_ORE,
	# === MATERIAUX RAFFINES (52-55) ===
	DIAMOND_BLOCK,
	COPPER_BLOCK,
	COPPER_INGOT,
	COAL_BLOCK,
	# === BLOCS NATURELS (56-60) ===
	CLAY,
	PODZOL,
	ICE,
	PACKED_ICE,
	MOSS_BLOCK,
	# === BLOCS FONCTIONNELS/DECORATIFS (61-64) ===
	GLASS,
	BOOKSHELF,
	HAY_BLOCK,
	BARREL,
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
	},
	# === VARIANTES DE PIERRE ===
	BlockType.COBBLESTONE: {
		"name": "Cobblestone",
		"solid": true,
		"color": Color(0.6, 0.6, 0.65, 1.0),
		"hardness": 1.5,
		"faces": { "all": "cobblestone" }
	},
	BlockType.MOSSY_COBBLESTONE: {
		"name": "Mossy Cobblestone",
		"solid": true,
		"color": Color(0.5, 0.65, 0.5, 1.0),
		"hardness": 1.5,
		"faces": { "all": "mossy_cobblestone" }
	},
	BlockType.ANDESITE: {
		"name": "Andesite",
		"solid": true,
		"color": Color(0.6, 0.6, 0.6, 1.0),
		"hardness": 1.2,
		"faces": { "all": "andesite" }
	},
	BlockType.GRANITE: {
		"name": "Granite",
		"solid": true,
		"color": Color(0.65, 0.5, 0.45, 1.0),
		"hardness": 1.2,
		"faces": { "all": "granite" }
	},
	BlockType.DIORITE: {
		"name": "Diorite",
		"solid": true,
		"color": Color(0.75, 0.75, 0.75, 1.0),
		"hardness": 1.2,
		"faces": { "all": "diorite" }
	},
	BlockType.DEEPSLATE: {
		"name": "Deepslate",
		"solid": true,
		"color": Color(0.35, 0.35, 0.4, 1.0),
		"hardness": 2.5,
		"faces": { "top": "deepslate_top", "bottom": "deepslate_top", "side": "deepslate" }
	},
	BlockType.SMOOTH_STONE: {
		"name": "Smooth Stone",
		"solid": true,
		"color": Color(0.72, 0.72, 0.76, 1.0),
		"hardness": 1.5,
		"faces": { "all": "smooth_stone" }
	},
	# === TYPES DE BOIS — LOGS ===
	BlockType.SPRUCE_LOG: {
		"name": "Spruce Log",
		"solid": true,
		"color": Color(0.45, 0.3, 0.2, 1.0),
		"hardness": 1.0,
		"faces": { "top": "spruce_log_top", "bottom": "spruce_log_top", "side": "spruce_log" }
	},
	BlockType.BIRCH_LOG: {
		"name": "Birch Log",
		"solid": true,
		"color": Color(0.85, 0.82, 0.75, 1.0),
		"hardness": 1.0,
		"faces": { "top": "birch_log_top", "bottom": "birch_log_top", "side": "birch_log" }
	},
	BlockType.JUNGLE_LOG: {
		"name": "Jungle Log",
		"solid": true,
		"color": Color(0.6, 0.45, 0.3, 1.0),
		"hardness": 1.0,
		"faces": { "top": "jungle_log_top", "bottom": "jungle_log_top", "side": "jungle_log" }
	},
	BlockType.ACACIA_LOG: {
		"name": "Acacia Log",
		"solid": true,
		"color": Color(0.6, 0.4, 0.3, 1.0),
		"hardness": 1.0,
		"faces": { "top": "acacia_log_top", "bottom": "acacia_log_top", "side": "acacia_log" }
	},
	BlockType.DARK_OAK_LOG: {
		"name": "Dark Oak Log",
		"solid": true,
		"color": Color(0.35, 0.25, 0.15, 1.0),
		"hardness": 1.0,
		"faces": { "top": "dark_oak_log_top", "bottom": "dark_oak_log_top", "side": "dark_oak_log" }
	},
	# === TYPES DE BOIS — PLANCHES ===
	BlockType.SPRUCE_PLANKS: {
		"name": "Spruce Planks",
		"solid": true,
		"color": Color(0.55, 0.4, 0.25, 1.0),
		"hardness": 0.8,
		"faces": { "all": "spruce_planks" }
	},
	BlockType.BIRCH_PLANKS: {
		"name": "Birch Planks",
		"solid": true,
		"color": Color(0.9, 0.85, 0.7, 1.0),
		"hardness": 0.8,
		"faces": { "all": "birch_planks" }
	},
	BlockType.JUNGLE_PLANKS: {
		"name": "Jungle Planks",
		"solid": true,
		"color": Color(0.7, 0.5, 0.35, 1.0),
		"hardness": 0.8,
		"faces": { "all": "jungle_planks" }
	},
	BlockType.ACACIA_PLANKS: {
		"name": "Acacia Planks",
		"solid": true,
		"color": Color(0.75, 0.45, 0.25, 1.0),
		"hardness": 0.8,
		"faces": { "all": "acacia_planks" }
	},
	BlockType.DARK_OAK_PLANKS: {
		"name": "Dark Oak Planks",
		"solid": true,
		"color": Color(0.4, 0.28, 0.15, 1.0),
		"hardness": 0.8,
		"faces": { "all": "dark_oak_planks" }
	},
	BlockType.CHERRY_LOG: {
		"name": "Cherry Log",
		"solid": true,
		"color": Color(0.7, 0.45, 0.5, 1.0),
		"hardness": 1.0,
		"faces": { "top": "cherry_log_top", "bottom": "cherry_log_top", "side": "cherry_log" }
	},
	BlockType.CHERRY_PLANKS: {
		"name": "Cherry Planks",
		"solid": true,
		"color": Color(0.85, 0.6, 0.6, 1.0),
		"hardness": 0.8,
		"faces": { "all": "cherry_planks" }
	},
	# === FEUILLAGES ===
	BlockType.SPRUCE_LEAVES: {
		"name": "Spruce Leaves",
		"solid": true,
		"color": Color(0.35, 0.55, 0.35, 1.0),
		"hardness": 0.2,
		"faces": { "all": "spruce_leaves" }
	},
	BlockType.BIRCH_LEAVES: {
		"name": "Birch Leaves",
		"solid": true,
		"color": Color(0.6, 0.8, 0.45, 1.0),
		"hardness": 0.2,
		"faces": { "all": "birch_leaves" }
	},
	BlockType.JUNGLE_LEAVES: {
		"name": "Jungle Leaves",
		"solid": true,
		"color": Color(0.3, 0.7, 0.25, 1.0),
		"hardness": 0.2,
		"faces": { "all": "jungle_leaves" }
	},
	BlockType.ACACIA_LEAVES: {
		"name": "Acacia Leaves",
		"solid": true,
		"color": Color(0.55, 0.7, 0.3, 1.0),
		"hardness": 0.2,
		"faces": { "all": "acacia_leaves" }
	},
	BlockType.DARK_OAK_LEAVES: {
		"name": "Dark Oak Leaves",
		"solid": true,
		"color": Color(0.3, 0.5, 0.25, 1.0),
		"hardness": 0.2,
		"faces": { "all": "dark_oak_leaves" }
	},
	BlockType.CHERRY_LEAVES: {
		"name": "Cherry Leaves",
		"solid": true,
		"color": Color(0.9, 0.6, 0.7, 1.0),
		"hardness": 0.2,
		"faces": { "all": "cherry_leaves" }
	},
	# === MINERAIS ===
	BlockType.DIAMOND_ORE: {
		"name": "Diamond Ore",
		"solid": true,
		"color": Color(0.5, 0.85, 0.9, 1.0),
		"hardness": 3.0,
		"faces": { "all": "diamond_ore" }
	},
	BlockType.COPPER_ORE: {
		"name": "Copper Ore",
		"solid": true,
		"color": Color(0.7, 0.55, 0.45, 1.0),
		"hardness": 2.0,
		"faces": { "all": "copper_ore" }
	},
	# === MATERIAUX RAFFINES ===
	BlockType.DIAMOND_BLOCK: {
		"name": "Diamond Block",
		"solid": true,
		"color": Color(0.55, 0.9, 0.95, 1.0),
		"hardness": 3.0,
		"faces": { "all": "diamond_block" }
	},
	BlockType.COPPER_BLOCK: {
		"name": "Copper Block",
		"solid": true,
		"color": Color(0.75, 0.55, 0.4, 1.0),
		"hardness": 2.0,
		"faces": { "all": "copper_block" }
	},
	BlockType.COPPER_INGOT: {
		"name": "Copper Ingot",
		"solid": true,
		"color": Color(0.8, 0.6, 0.45, 1.0),
		"hardness": 1.5,
		"faces": { "all": "copper_block" }
	},
	BlockType.COAL_BLOCK: {
		"name": "Coal Block",
		"solid": true,
		"color": Color(0.15, 0.15, 0.18, 1.0),
		"hardness": 1.5,
		"faces": { "all": "coal_block" }
	},
	# === BLOCS NATURELS ===
	BlockType.CLAY: {
		"name": "Clay",
		"solid": true,
		"color": Color(0.65, 0.65, 0.72, 1.0),
		"hardness": 0.6,
		"faces": { "all": "clay" }
	},
	BlockType.PODZOL: {
		"name": "Podzol",
		"solid": true,
		"color": Color(0.5, 0.38, 0.25, 1.0),
		"hardness": 0.5,
		"faces": { "top": "podzol_top", "side": "podzol_side", "bottom": "dirt" }
	},
	BlockType.ICE: {
		"name": "Ice",
		"solid": true,
		"color": Color(0.7, 0.85, 0.95, 1.0),
		"hardness": 0.5,
		"faces": { "all": "ice" }
	},
	BlockType.PACKED_ICE: {
		"name": "Packed Ice",
		"solid": true,
		"color": Color(0.6, 0.75, 0.9, 1.0),
		"hardness": 1.5,
		"faces": { "all": "packed_ice" }
	},
	BlockType.MOSS_BLOCK: {
		"name": "Moss Block",
		"solid": true,
		"color": Color(0.4, 0.6, 0.3, 1.0),
		"hardness": 0.5,
		"faces": { "all": "moss_block" }
	},
	# === BLOCS FONCTIONNELS / DECORATIFS ===
	BlockType.GLASS: {
		"name": "Glass",
		"solid": true,
		"color": Color(0.85, 0.9, 0.95, 0.8),
		"hardness": 0.3,
		"faces": { "all": "glass" }
	},
	BlockType.BOOKSHELF: {
		"name": "Bookshelf",
		"solid": true,
		"color": Color(0.55, 0.4, 0.3, 1.0),
		"hardness": 0.8,
		"faces": { "top": "oak_planks", "bottom": "oak_planks", "side": "bookshelf" }
	},
	BlockType.HAY_BLOCK: {
		"name": "Hay Block",
		"solid": true,
		"color": Color(0.85, 0.75, 0.3, 1.0),
		"hardness": 0.5,
		"faces": { "top": "hay_block_top", "bottom": "hay_block_top", "side": "hay_block_side" }
	},
	BlockType.BARREL: {
		"name": "Barrel",
		"solid": true,
		"color": Color(0.6, 0.45, 0.3, 1.0),
		"hardness": 1.0,
		"faces": { "top": "barrel_top", "bottom": "barrel_bottom", "side": "barrel_side" }
	},
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

const WORKSTATION_BLOCKS: Dictionary = {
	BlockType.CRAFTING_TABLE: true,
	BlockType.FURNACE: true,
	BlockType.STONE_TABLE: true,
	BlockType.IRON_TABLE: true,
	BlockType.GOLD_TABLE: true,
	BlockType.BARREL: true,
}

static func is_workstation(block_type) -> bool:
	return WORKSTATION_BLOCKS.has(block_type)

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
		BlockType.SPRUCE_LEAVES:
			return Color(0.35, 0.65, 0.35, 1.0)
		BlockType.BIRCH_LEAVES:
			return Color(0.6, 0.85, 0.35, 1.0)
		BlockType.JUNGLE_LEAVES:
			return Color(0.3, 0.8, 0.25, 1.0)
		BlockType.ACACIA_LEAVES:
			return Color(0.55, 0.75, 0.3, 1.0)
		BlockType.DARK_OAK_LEAVES:
			return Color(0.3, 0.55, 0.25, 1.0)
		BlockType.CHERRY_LEAVES:
			return Color(0.9, 0.6, 0.7, 1.0)
		_:
			return Color(1.0, 1.0, 1.0, 1.0)
