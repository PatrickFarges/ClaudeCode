extends Node
class_name Locale

# Système de localisation FR/EN
# Changer la langue ici :
static var current_lang: String = "fr"

# ============================================================
# NOMS DES BLOCS
# ============================================================
const BLOCK_NAMES = {
	"Air":        {"fr": "Air",           "en": "Air"},
	"Grass":      {"fr": "Herbe",         "en": "Grass"},
	"Dirt":       {"fr": "Terre",         "en": "Dirt"},
	"Stone":      {"fr": "Pierre",        "en": "Stone"},
	"Sand":       {"fr": "Sable",         "en": "Sand"},
	"Wood":       {"fr": "Bois",          "en": "Wood"},
	"Leaves":     {"fr": "Feuilles",      "en": "Leaves"},
	"Snow":       {"fr": "Neige",         "en": "Snow"},
	"Cactus":     {"fr": "Cactus",        "en": "Cactus"},
	"Dark Grass": {"fr": "Herbe sombre",  "en": "Dark Grass"},
	"Gravel":     {"fr": "Gravier",       "en": "Gravel"},
	"Planks":     {"fr": "Planches",      "en": "Planks"},
	"Craft Table":{"fr": "Table de Craft","en": "Craft Table"},
	"Brick":      {"fr": "Briques",       "en": "Bricks"},
	"Sandstone":  {"fr": "Grès",          "en": "Sandstone"},
	"Water":      {"fr": "Eau",          "en": "Water"},
	"Coal Ore":   {"fr": "Charbon",      "en": "Coal Ore"},
	"Iron Ore":   {"fr": "Fer",          "en": "Iron Ore"},
	"Gold Ore":   {"fr": "Or (minerai)", "en": "Gold Ore"},
	"Iron Ingot": {"fr": "Lingot de fer","en": "Iron Ingot"},
	"Gold Ingot": {"fr": "Lingot d'or", "en": "Gold Ingot"},
	"Furnace":    {"fr": "Fourneau",     "en": "Furnace"},
	"Stone Table":{"fr": "Table en pierre","en": "Stone Table"},
	"Iron Table": {"fr": "Table en fer", "en": "Iron Table"},
	"Gold Table": {"fr": "Table en or",  "en": "Gold Table"},
}

# ============================================================
# NOMS DES RECETTES
# ============================================================
const RECIPE_NAMES = {
	"Planches":           {"fr": "Planches",           "en": "Planks"},
	"Table de Craft":     {"fr": "Table de Craft",     "en": "Crafting Table"},
	"Briques":            {"fr": "Briques",            "en": "Bricks"},
	"Grès":               {"fr": "Grès",               "en": "Sandstone"},
	"Terre":              {"fr": "Terre",              "en": "Dirt"},
	"Terre (Dark Grass)": {"fr": "Terre (herbe sombre)","en": "Dirt (dark grass)"},
	"Briques (lot)":      {"fr": "Briques (lot)",      "en": "Bricks (bulk)"},
	"Grès (lot)":         {"fr": "Grès (lot)",         "en": "Sandstone (bulk)"},
	"Planches (lot)":     {"fr": "Planches (lot)",     "en": "Planks (bulk)"},
	"Fourneau":           {"fr": "Fourneau",           "en": "Furnace"},
	"Table en pierre":    {"fr": "Table en pierre",    "en": "Stone Table"},
	"Table en fer":       {"fr": "Table en fer",       "en": "Iron Table"},
	"Table en or":        {"fr": "Table en or",        "en": "Gold Table"},
	"Lingot de fer":      {"fr": "Lingot de fer",      "en": "Iron Ingot"},
	"Lingot d'or":        {"fr": "Lingot d'or",        "en": "Gold Ingot"},
	"Briques (batch)":    {"fr": "Briques (batch)",    "en": "Bricks (batch)"},
	"Grès (batch)":       {"fr": "Grès (batch)",       "en": "Sandstone (batch)"},
	"Planches (batch)":   {"fr": "Planches (batch)",   "en": "Planks (batch)"},
	"Briques (mega)":     {"fr": "Briques (mega)",     "en": "Bricks (mega)"},
	"Grès (mega)":        {"fr": "Grès (mega)",        "en": "Sandstone (mega)"},
	"Planches (mega)":    {"fr": "Planches (mega)",    "en": "Planks (mega)"},
	"Briques (max)":      {"fr": "Briques (max)",      "en": "Bricks (max)"},
	"Grès (max)":         {"fr": "Grès (max)",         "en": "Sandstone (max)"},
	"Planches (max)":     {"fr": "Planches (max)",     "en": "Planks (max)"},
}

# ============================================================
# TEXTES DE L'INTERFACE
# ============================================================
const UI = {
	# Crafting UI
	"crafting_title":       {"fr": "⚒️ Artisanat",            "en": "⚒️ Crafting"},
	"craft_hand":           {"fr": "🤲 Artisanat à la main",  "en": "🤲 Hand crafting"},
	"craft_tier_1":         {"fr": "🔨 Table en bois",         "en": "🔨 Wood Table"},
	"craft_tier_2":         {"fr": "⛏ Table en pierre",        "en": "⛏ Stone Table"},
	"craft_tier_3":         {"fr": "🔧 Table en fer",          "en": "🔧 Iron Table"},
	"craft_tier_4":         {"fr": "👑 Table en or (toutes)",   "en": "👑 Gold Table (all)"},
	"craft_furnace":        {"fr": "🔥 Fourneau",              "en": "🔥 Furnace"},
	"craft_btn":            {"fr": "Crafter",                  "en": "Craft"},
	"craft_missing":        {"fr": "Manque",                   "en": "Missing"},
	"craft_need_wood":      {"fr": "🔨 Table bois",            "en": "🔨 Wood Table"},
	"craft_need_stone":     {"fr": "⛏ Table pierre",           "en": "⛏ Stone Table"},
	"craft_need_iron":      {"fr": "🔧 Table fer",             "en": "🔧 Iron Table"},
	"craft_need_gold":      {"fr": "👑 Table or",              "en": "👑 Gold Table"},
	"craft_need_furnace":   {"fr": "🔥 Fourneau",              "en": "🔥 Furnace"},
	"craft_hint_hand":      {"fr": "[C] ou [Échap] pour fermer  •  Clic droit sur une table pour plus de recettes",
	                         "en": "[C] or [Esc] to close  •  Right-click a table for more recipes"},
	"craft_hint_station":   {"fr": "[Échap] pour fermer",      "en": "[Esc] to close"},
	
	# Inventory UI
	"inv_title":            {"fr": "🎒 Inventaire",            "en": "🎒 Inventory"},
	"inv_active_slot":      {"fr": "Slot actif : %d  [%s]",    "en": "Active slot: %d  [%s]"},
	"inv_hint":             {"fr": "Clic gauche → assigner au slot actif  •  [E] ou [Échap] pour fermer  •  [C] pour crafter",
	                         "en": "Left click → assign to active slot  •  [E] or [Esc] to close  •  [C] to craft"},
	
	# Version HUD
	"version":              {"fr": "ClaudeCraft",              "en": "ClaudeCraft"},
	"fps":                  {"fr": "%d IPS",                   "en": "%d FPS"},
	
	# Biomes
	"biome_desert":         {"fr": "Désert",                   "en": "Desert"},
	"biome_forest":         {"fr": "Forêt",                    "en": "Forest"},
	"biome_mountain":       {"fr": "Montagne",                 "en": "Mountain"},
	"biome_plains":         {"fr": "Plaines",                  "en": "Plains"},

	# Santé
	"health":               {"fr": "❤ %d/%d",                  "en": "❤ %d/%d"},
	"you_died":             {"fr": "Vous êtes mort !",         "en": "You died!"},

	# Menu pause
	"pause_title":          {"fr": "Pause",                    "en": "Paused"},
	"pause_resume":         {"fr": "Reprendre",                "en": "Resume"},
	"pause_save":           {"fr": "Sauvegarder",              "en": "Save"},
	"pause_load":           {"fr": "Charger",                  "en": "Load"},
	"pause_quit":           {"fr": "Quitter",                  "en": "Quit"},
	"save_success":         {"fr": "Monde sauvegardé !",       "en": "World saved!"},
	"save_error":           {"fr": "Erreur de sauvegarde",     "en": "Save error"},
	"load_no_save":         {"fr": "Aucune sauvegarde",        "en": "No save found"},
	"saving":               {"fr": "Sauvegarde...",            "en": "Saving..."},
	"loading":              {"fr": "Chargement...",            "en": "Loading..."},
}

# ============================================================
# MÉTHODES
# ============================================================

static func tr_block(block_key: String) -> String:
	"""Traduire un nom de bloc (clé = nom anglais interne de BLOCK_DATA)"""
	if BLOCK_NAMES.has(block_key):
		return BLOCK_NAMES[block_key].get(current_lang, block_key)
	return block_key

static func tr_recipe(recipe_key: String) -> String:
	"""Traduire un nom de recette"""
	if RECIPE_NAMES.has(recipe_key):
		return RECIPE_NAMES[recipe_key].get(current_lang, recipe_key)
	return recipe_key

static func tr_ui(key: String) -> String:
	"""Traduire un texte d'interface"""
	if UI.has(key):
		return UI[key].get(current_lang, key)
	return key

static func set_language(lang: String):
	"""Changer la langue ('fr' ou 'en')"""
	current_lang = lang
