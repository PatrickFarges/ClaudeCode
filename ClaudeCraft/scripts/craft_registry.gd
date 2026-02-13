extends Node
class_name CraftRegistry

# Registre de toutes les recettes de crafting
#
# Chaque recette :
#   name: nom affiché
#   inputs: [[BlockType, count], ...] — ingrédients requis
#   output_type: BlockType produit
#   output_count: nombre produit
#   station: "hand" | "wood_table" | "stone_table" | "iron_table" | "gold_table" | "furnace"
#
# Tier hierarchy: hand(0) < wood_table(1) < stone_table(2) < iron_table(3) < gold_table(4)
# Furnace is separate — accessible with tier 0 + furnace flag

static func get_all_recipes() -> Array:
	return [
		# ============================================================
		# RECETTES À LA MAIN (tier 0)
		# ============================================================
		{
			"name": "Planches",
			"inputs": [[BlockRegistry.BlockType.WOOD, 1]],
			"output_type": BlockRegistry.BlockType.PLANKS,
			"output_count": 4,
			"station": "hand"
		},
		{
			"name": "Table de Craft",
			"inputs": [[BlockRegistry.BlockType.PLANKS, 4]],
			"output_type": BlockRegistry.BlockType.CRAFTING_TABLE,
			"output_count": 1,
			"station": "hand"
		},
		{
			"name": "Terre",
			"inputs": [[BlockRegistry.BlockType.GRASS, 1]],
			"output_type": BlockRegistry.BlockType.DIRT,
			"output_count": 1,
			"station": "hand"
		},
		{
			"name": "Terre (Dark Grass)",
			"inputs": [[BlockRegistry.BlockType.DARK_GRASS, 1]],
			"output_type": BlockRegistry.BlockType.DIRT,
			"output_count": 1,
			"station": "hand"
		},

		# ============================================================
		# RECETTES FOURNEAU (furnace)
		# ============================================================
		{
			"name": "Lingot de fer",
			"inputs": [[BlockRegistry.BlockType.IRON_ORE, 1], [BlockRegistry.BlockType.COAL_ORE, 1]],
			"output_type": BlockRegistry.BlockType.IRON_INGOT,
			"output_count": 1,
			"station": "furnace"
		},
		{
			"name": "Lingot d'or",
			"inputs": [[BlockRegistry.BlockType.GOLD_ORE, 1], [BlockRegistry.BlockType.COAL_ORE, 1]],
			"output_type": BlockRegistry.BlockType.GOLD_INGOT,
			"output_count": 1,
			"station": "furnace"
		},

		# ============================================================
		# TABLE EN BOIS — tier 1 (CRAFTING_TABLE)
		# ============================================================
		{
			"name": "Briques",
			"inputs": [[BlockRegistry.BlockType.STONE, 2]],
			"output_type": BlockRegistry.BlockType.BRICK,
			"output_count": 4,
			"station": "wood_table"
		},
		{
			"name": "Grès",
			"inputs": [[BlockRegistry.BlockType.SAND, 4]],
			"output_type": BlockRegistry.BlockType.SANDSTONE,
			"output_count": 4,
			"station": "wood_table"
		},
		{
			"name": "Planches (lot)",
			"inputs": [[BlockRegistry.BlockType.WOOD, 4]],
			"output_type": BlockRegistry.BlockType.PLANKS,
			"output_count": 20,
			"station": "wood_table"
		},
		{
			"name": "Briques (lot)",
			"inputs": [[BlockRegistry.BlockType.STONE, 8]],
			"output_type": BlockRegistry.BlockType.BRICK,
			"output_count": 12,
			"station": "wood_table"
		},
		{
			"name": "Grès (lot)",
			"inputs": [[BlockRegistry.BlockType.SAND, 8]],
			"output_type": BlockRegistry.BlockType.SANDSTONE,
			"output_count": 12,
			"station": "wood_table"
		},
		{
			"name": "Fourneau",
			"inputs": [[BlockRegistry.BlockType.STONE, 8]],
			"output_type": BlockRegistry.BlockType.FURNACE,
			"output_count": 1,
			"station": "wood_table"
		},
		{
			"name": "Table en pierre",
			"inputs": [[BlockRegistry.BlockType.STONE, 4], [BlockRegistry.BlockType.PLANKS, 4]],
			"output_type": BlockRegistry.BlockType.STONE_TABLE,
			"output_count": 1,
			"station": "wood_table"
		},

		# ============================================================
		# TABLE EN PIERRE — tier 2 (STONE_TABLE)
		# ============================================================
		{
			"name": "Table en fer",
			"inputs": [[BlockRegistry.BlockType.IRON_INGOT, 4], [BlockRegistry.BlockType.STONE, 4]],
			"output_type": BlockRegistry.BlockType.IRON_TABLE,
			"output_count": 1,
			"station": "stone_table"
		},
		{
			"name": "Briques (batch)",
			"inputs": [[BlockRegistry.BlockType.STONE, 12]],
			"output_type": BlockRegistry.BlockType.BRICK,
			"output_count": 20,
			"station": "stone_table"
		},
		{
			"name": "Grès (batch)",
			"inputs": [[BlockRegistry.BlockType.SAND, 12]],
			"output_type": BlockRegistry.BlockType.SANDSTONE,
			"output_count": 20,
			"station": "stone_table"
		},
		{
			"name": "Planches (batch)",
			"inputs": [[BlockRegistry.BlockType.WOOD, 8]],
			"output_type": BlockRegistry.BlockType.PLANKS,
			"output_count": 40,
			"station": "stone_table"
		},

		# ============================================================
		# TABLE EN FER — tier 3 (IRON_TABLE)
		# ============================================================
		{
			"name": "Table en or",
			"inputs": [[BlockRegistry.BlockType.GOLD_INGOT, 4], [BlockRegistry.BlockType.IRON_INGOT, 4]],
			"output_type": BlockRegistry.BlockType.GOLD_TABLE,
			"output_count": 1,
			"station": "iron_table"
		},
		{
			"name": "Briques (mega)",
			"inputs": [[BlockRegistry.BlockType.STONE, 16]],
			"output_type": BlockRegistry.BlockType.BRICK,
			"output_count": 32,
			"station": "iron_table"
		},
		{
			"name": "Grès (mega)",
			"inputs": [[BlockRegistry.BlockType.SAND, 16]],
			"output_type": BlockRegistry.BlockType.SANDSTONE,
			"output_count": 32,
			"station": "iron_table"
		},
		{
			"name": "Planches (mega)",
			"inputs": [[BlockRegistry.BlockType.WOOD, 12]],
			"output_type": BlockRegistry.BlockType.PLANKS,
			"output_count": 64,
			"station": "iron_table"
		},

		# ============================================================
		# TABLE EN OR — tier 4 (GOLD_TABLE)
		# ============================================================
		{
			"name": "Briques (max)",
			"inputs": [[BlockRegistry.BlockType.STONE, 8]],
			"output_type": BlockRegistry.BlockType.BRICK,
			"output_count": 24,
			"station": "gold_table"
		},
		{
			"name": "Grès (max)",
			"inputs": [[BlockRegistry.BlockType.SAND, 8]],
			"output_type": BlockRegistry.BlockType.SANDSTONE,
			"output_count": 24,
			"station": "gold_table"
		},
		{
			"name": "Planches (max)",
			"inputs": [[BlockRegistry.BlockType.WOOD, 4]],
			"output_type": BlockRegistry.BlockType.PLANKS,
			"output_count": 32,
			"station": "gold_table"
		},
	]

static func get_station_tier(station: String) -> int:
	match station:
		"hand": return 0
		"wood_table": return 1
		"stone_table": return 2
		"iron_table": return 3
		"gold_table": return 4
		"furnace": return -1  # Special: not part of tier hierarchy
		_: return 0

static func is_recipe_available(recipe: Dictionary, tier: int, has_furnace: bool) -> bool:
	var station = recipe["station"]
	if station == "furnace":
		return has_furnace
	var recipe_tier = get_station_tier(station)
	return tier >= recipe_tier

static func get_recipe_station_label(recipe: Dictionary) -> String:
	"""Retourne la clé UI pour le label du tier requis"""
	match recipe["station"]:
		"hand": return ""
		"wood_table": return "craft_need_wood"
		"stone_table": return "craft_need_stone"
		"iron_table": return "craft_need_iron"
		"gold_table": return "craft_need_gold"
		"furnace": return "craft_need_furnace"
		_: return ""

static func can_craft(recipe: Dictionary, inventory: Dictionary) -> bool:
	"""Vérifier si le joueur a les ingrédients pour une recette"""
	for input_item in recipe["inputs"]:
		var block_type = input_item[0]
		var required = input_item[1]
		var have = inventory.get(block_type, 0)
		if have < required:
			return false
	return true

static func get_ingredients_text(recipe: Dictionary) -> String:
	"""Texte lisible des ingrédients"""
	var parts = []
	for input_item in recipe["inputs"]:
		var block_type = input_item[0]
		var count = input_item[1]
		var name = BlockRegistry.get_block_name(block_type)
		parts.append("%dx %s" % [count, name])
	return " + ".join(parts)
