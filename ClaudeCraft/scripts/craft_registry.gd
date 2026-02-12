extends Node
class_name CraftRegistry

# Registre de toutes les recettes de crafting
#
# Chaque recette :
#   name: nom affiché
#   inputs: [[BlockType, count], ...] — ingrédients requis
#   output_type: BlockType produit
#   output_count: nombre produit
#   station: "hand" (touche C) ou "table" (near crafting table)

static func get_all_recipes() -> Array:
	return [
		# ============================================================
		# RECETTES À LA MAIN (touche C)
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
			"name": "Briques",
			"inputs": [[BlockRegistry.BlockType.STONE, 2]],
			"output_type": BlockRegistry.BlockType.BRICK,
			"output_count": 4,
			"station": "hand"
		},
		{
			"name": "Grès",
			"inputs": [[BlockRegistry.BlockType.SAND, 4]],
			"output_type": BlockRegistry.BlockType.SANDSTONE,
			"output_count": 4,
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
		# RECETTES TABLE DE CRAFT (à proximité d'une Craft Table)
		# ============================================================
		{
			"name": "Briques (lot)",
			"inputs": [[BlockRegistry.BlockType.STONE, 8]],
			"output_type": BlockRegistry.BlockType.BRICK,
			"output_count": 12,
			"station": "table"
		},
		{
			"name": "Grès (lot)",
			"inputs": [[BlockRegistry.BlockType.SAND, 8]],
			"output_type": BlockRegistry.BlockType.SANDSTONE,
			"output_count": 12,
			"station": "table"
		},
		{
			"name": "Planches (lot)",
			"inputs": [[BlockRegistry.BlockType.WOOD, 4]],
			"output_type": BlockRegistry.BlockType.PLANKS,
			"output_count": 20,
			"station": "table"
		},
	]

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
