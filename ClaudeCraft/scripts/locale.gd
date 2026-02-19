extends Node
class_name Locale

# Systeme de localisation FR/EN
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
	"Sandstone":  {"fr": "Gres",          "en": "Sandstone"},
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
	# === NOUVEAUX BLOCS ===
	"Cobblestone":       {"fr": "Pave",                   "en": "Cobblestone"},
	"Mossy Cobblestone": {"fr": "Pave mousseux",          "en": "Mossy Cobblestone"},
	"Andesite":          {"fr": "Andesite",               "en": "Andesite"},
	"Granite":           {"fr": "Granite",                "en": "Granite"},
	"Diorite":           {"fr": "Diorite",                "en": "Diorite"},
	"Deepslate":         {"fr": "Ardoise des abimes",     "en": "Deepslate"},
	"Smooth Stone":      {"fr": "Pierre lisse",           "en": "Smooth Stone"},
	"Spruce Log":        {"fr": "Bois de sapin",          "en": "Spruce Log"},
	"Birch Log":         {"fr": "Bois de bouleau",        "en": "Birch Log"},
	"Jungle Log":        {"fr": "Bois de jungle",         "en": "Jungle Log"},
	"Acacia Log":        {"fr": "Bois d'acacia",          "en": "Acacia Log"},
	"Dark Oak Log":      {"fr": "Bois de chene noir",     "en": "Dark Oak Log"},
	"Cherry Log":        {"fr": "Bois de cerisier",       "en": "Cherry Log"},
	"Spruce Planks":     {"fr": "Planches de sapin",      "en": "Spruce Planks"},
	"Birch Planks":      {"fr": "Planches de bouleau",    "en": "Birch Planks"},
	"Jungle Planks":     {"fr": "Planches de jungle",     "en": "Jungle Planks"},
	"Acacia Planks":     {"fr": "Planches d'acacia",      "en": "Acacia Planks"},
	"Dark Oak Planks":   {"fr": "Planches de chene noir",  "en": "Dark Oak Planks"},
	"Cherry Planks":     {"fr": "Planches de cerisier",   "en": "Cherry Planks"},
	"Spruce Leaves":     {"fr": "Feuilles de sapin",      "en": "Spruce Leaves"},
	"Birch Leaves":      {"fr": "Feuilles de bouleau",    "en": "Birch Leaves"},
	"Jungle Leaves":     {"fr": "Feuilles de jungle",     "en": "Jungle Leaves"},
	"Acacia Leaves":     {"fr": "Feuilles d'acacia",      "en": "Acacia Leaves"},
	"Dark Oak Leaves":   {"fr": "Feuilles de chene noir",  "en": "Dark Oak Leaves"},
	"Cherry Leaves":     {"fr": "Feuilles de cerisier",   "en": "Cherry Leaves"},
	"Diamond Ore":       {"fr": "Minerai de diamant",     "en": "Diamond Ore"},
	"Copper Ore":        {"fr": "Minerai de cuivre",      "en": "Copper Ore"},
	"Diamond Block":     {"fr": "Bloc de diamant",        "en": "Diamond Block"},
	"Copper Block":      {"fr": "Bloc de cuivre",         "en": "Copper Block"},
	"Copper Ingot":      {"fr": "Lingot de cuivre",       "en": "Copper Ingot"},
	"Coal Block":        {"fr": "Bloc de charbon",        "en": "Coal Block"},
	"Clay":              {"fr": "Argile",                  "en": "Clay"},
	"Podzol":            {"fr": "Podzol",                  "en": "Podzol"},
	"Ice":               {"fr": "Glace",                   "en": "Ice"},
	"Packed Ice":        {"fr": "Glace compactee",         "en": "Packed Ice"},
	"Moss Block":        {"fr": "Bloc de mousse",          "en": "Moss Block"},
	"Glass":             {"fr": "Verre",                   "en": "Glass"},
	"Bookshelf":         {"fr": "Bibliotheque",            "en": "Bookshelf"},
	"Hay Block":         {"fr": "Botte de foin",           "en": "Hay Block"},
	"Barrel":            {"fr": "Tonneau",                 "en": "Barrel"},
}

# ============================================================
# NOMS DES RECETTES
# ============================================================
const RECIPE_NAMES = {
	"Planches":           {"fr": "Planches",           "en": "Planks"},
	"Table de Craft":     {"fr": "Table de Craft",     "en": "Crafting Table"},
	"Briques":            {"fr": "Briques",            "en": "Bricks"},
	"Gres":               {"fr": "Gres",               "en": "Sandstone"},
	"Terre":              {"fr": "Terre",              "en": "Dirt"},
	"Terre (Dark Grass)": {"fr": "Terre (herbe sombre)","en": "Dirt (dark grass)"},
	"Briques (lot)":      {"fr": "Briques (lot)",      "en": "Bricks (bulk)"},
	"Gres (lot)":         {"fr": "Gres (lot)",         "en": "Sandstone (bulk)"},
	"Planches (lot)":     {"fr": "Planches (lot)",     "en": "Planks (bulk)"},
	"Fourneau":           {"fr": "Fourneau",           "en": "Furnace"},
	"Table en pierre":    {"fr": "Table en pierre",    "en": "Stone Table"},
	"Table en fer":       {"fr": "Table en fer",       "en": "Iron Table"},
	"Table en or":        {"fr": "Table en or",        "en": "Gold Table"},
	"Lingot de fer":      {"fr": "Lingot de fer",      "en": "Iron Ingot"},
	"Lingot d'or":        {"fr": "Lingot d'or",        "en": "Gold Ingot"},
	"Briques (batch)":    {"fr": "Briques (batch)",    "en": "Bricks (batch)"},
	"Gres (batch)":       {"fr": "Gres (batch)",       "en": "Sandstone (batch)"},
	"Planches (batch)":   {"fr": "Planches (batch)",   "en": "Planks (batch)"},
	"Briques (mega)":     {"fr": "Briques (mega)",     "en": "Bricks (mega)"},
	"Gres (mega)":        {"fr": "Gres (mega)",        "en": "Sandstone (mega)"},
	"Planches (mega)":    {"fr": "Planches (mega)",    "en": "Planks (mega)"},
	"Briques (max)":      {"fr": "Briques (max)",      "en": "Bricks (max)"},
	"Gres (max)":         {"fr": "Gres (max)",         "en": "Sandstone (max)"},
	"Planches (max)":     {"fr": "Planches (max)",     "en": "Planks (max)"},
	# === NOUVELLES RECETTES ===
	"Planches de sapin":       {"fr": "Planches de sapin",       "en": "Spruce Planks"},
	"Planches de bouleau":     {"fr": "Planches de bouleau",     "en": "Birch Planks"},
	"Planches de jungle":      {"fr": "Planches de jungle",      "en": "Jungle Planks"},
	"Planches d'acacia":       {"fr": "Planches d'acacia",       "en": "Acacia Planks"},
	"Planches de chene noir":  {"fr": "Planches de chene noir",  "en": "Dark Oak Planks"},
	"Planches de cerisier":    {"fr": "Planches de cerisier",    "en": "Cherry Planks"},
	"Pierre lisse":            {"fr": "Pierre lisse",            "en": "Smooth Stone"},
	"Verre":                   {"fr": "Verre",                   "en": "Glass"},
	"Lingot de cuivre":        {"fr": "Lingot de cuivre",        "en": "Copper Ingot"},
	"Diamant":                 {"fr": "Diamant",                 "en": "Diamond"},
	"Brique (argile)":         {"fr": "Brique (argile)",         "en": "Brick (clay)"},
	"Pave":                    {"fr": "Pave",                    "en": "Cobblestone"},
	"Pave mousseux":           {"fr": "Pave mousseux",           "en": "Mossy Cobblestone"},
	"Botte de foin":           {"fr": "Botte de foin",           "en": "Hay Block"},
	"Bibliotheque":            {"fr": "Bibliotheque",            "en": "Bookshelf"},
	"Tonneau":                 {"fr": "Tonneau",                 "en": "Barrel"},
	"Bloc de charbon":         {"fr": "Bloc de charbon",         "en": "Coal Block"},
	"Bloc de cuivre":          {"fr": "Bloc de cuivre",          "en": "Copper Block"},
	"Verre (lot)":             {"fr": "Verre (lot)",             "en": "Glass (bulk)"},
	"Andesite":                {"fr": "Andesite",                "en": "Andesite"},
	"Granite":                 {"fr": "Granite",                 "en": "Granite"},
	"Diorite":                 {"fr": "Diorite",                 "en": "Diorite"},
	"Glace compactee":         {"fr": "Glace compactee",         "en": "Packed Ice"},
	"Pierre lisse (lot)":      {"fr": "Pierre lisse (lot)",      "en": "Smooth Stone (bulk)"},
	"Deepslate":               {"fr": "Ardoise des abimes",      "en": "Deepslate"},
	"Verre (mega)":            {"fr": "Verre (mega)",            "en": "Glass (mega)"},
	"Pave (mega)":             {"fr": "Pave (mega)",             "en": "Cobblestone (mega)"},
	"Botte de foin (lot)":     {"fr": "Botte de foin (lot)",     "en": "Hay Block (bulk)"},
	"Verre (max)":             {"fr": "Verre (max)",             "en": "Glass (max)"},
	"Pave (max)":              {"fr": "Pave (max)",              "en": "Cobblestone (max)"},
	"Botte de foin (max)":     {"fr": "Botte de foin (max)",     "en": "Hay Block (max)"},
}

# ============================================================
# TEXTES DE L'INTERFACE
# ============================================================
const UI = {
	# Crafting UI
	"crafting_title":       {"fr": "Artisanat",               "en": "Crafting"},
	"craft_hand":           {"fr": "Artisanat a la main",     "en": "Hand crafting"},
	"craft_tier_1":         {"fr": "Table en bois",            "en": "Wood Table"},
	"craft_tier_2":         {"fr": "Table en pierre",          "en": "Stone Table"},
	"craft_tier_3":         {"fr": "Table en fer",             "en": "Iron Table"},
	"craft_tier_4":         {"fr": "Table en or (toutes)",     "en": "Gold Table (all)"},
	"craft_furnace":        {"fr": "Fourneau",                 "en": "Furnace"},
	"craft_btn":            {"fr": "Crafter",                  "en": "Craft"},
	"craft_missing":        {"fr": "Manque",                   "en": "Missing"},
	"craft_need_wood":      {"fr": "Table bois",              "en": "Wood Table"},
	"craft_need_stone":     {"fr": "Table pierre",            "en": "Stone Table"},
	"craft_need_iron":      {"fr": "Table fer",               "en": "Iron Table"},
	"craft_need_gold":      {"fr": "Table or",                "en": "Gold Table"},
	"craft_need_furnace":   {"fr": "Fourneau",                "en": "Furnace"},
	"craft_hint_hand":      {"fr": "[C] ou [Echap] pour fermer  -  Clic droit sur une table pour plus de recettes",
	                         "en": "[C] or [Esc] to close  -  Right-click a table for more recipes"},
	"craft_hint_station":   {"fr": "[Echap] pour fermer",      "en": "[Esc] to close"},

	# Inventory UI
	"inv_title":            {"fr": "Inventaire",               "en": "Inventory"},
	"inv_active_slot":      {"fr": "Slot actif : %d  [%s]",    "en": "Active slot: %d  [%s]"},
	"inv_hint":             {"fr": "Clic gauche/droit = assigner au slot actif  -  [1-9] changer de slot  -  [I]/[Echap] fermer  -  [C] crafter",
	                         "en": "Left/Right click = assign to active slot  -  [1-9] change slot  -  [I]/[Esc] close  -  [C] craft"},
	"inv_tab_all":          {"fr": "TOUT",                    "en": "ALL"},
	"inv_tab_terrain":      {"fr": "Terrain",                 "en": "Terrain"},
	"inv_tab_wood":         {"fr": "Bois",                    "en": "Wood"},
	"inv_tab_stone":        {"fr": "Pierre",                  "en": "Stone"},
	"inv_tab_ores":         {"fr": "Minerais",                "en": "Ores"},
	"inv_tab_deco":         {"fr": "Deco",                    "en": "Deco"},
	"inv_tab_stations":     {"fr": "Stations",                "en": "Stations"},
	"inv_sort":             {"fr": "Trier",                   "en": "Sort"},
	"inv_sort_active":      {"fr": "Trie",                    "en": "Sorted"},
	"inv_coming_soon":      {"fr": "Bientot disponible",      "en": "Coming soon"},

	# Version HUD
	"version":              {"fr": "ClaudeCraft",              "en": "ClaudeCraft"},
	"fps":                  {"fr": "%d IPS",                   "en": "%d FPS"},

	# Biomes
	"biome_desert":         {"fr": "Desert",                   "en": "Desert"},
	"biome_forest":         {"fr": "Foret",                    "en": "Forest"},
	"biome_mountain":       {"fr": "Montagne",                 "en": "Mountain"},
	"biome_plains":         {"fr": "Plaines",                  "en": "Plains"},

	# Sante
	"health":               {"fr": "%d/%d",                    "en": "%d/%d"},
	"you_died":             {"fr": "Vous etes mort !",         "en": "You died!"},

	# Menu pause
	"pause_title":          {"fr": "Pause",                    "en": "Paused"},
	"pause_resume":         {"fr": "Reprendre",                "en": "Resume"},
	"pause_save":           {"fr": "Sauvegarder",              "en": "Save"},
	"pause_load":           {"fr": "Charger",                  "en": "Load"},
	"pause_quit":           {"fr": "Quitter",                  "en": "Quit"},
	"save_success":         {"fr": "Monde sauvegarde !",       "en": "World saved!"},
	"save_error":           {"fr": "Erreur de sauvegarde",     "en": "Save error"},
	"load_no_save":         {"fr": "Aucune sauvegarde",        "en": "No save found"},
	"saving":               {"fr": "Sauvegarde...",            "en": "Saving..."},
	"loading":              {"fr": "Chargement...",            "en": "Loading..."},
}

# ============================================================
# METHODES
# ============================================================

static func tr_block(block_key: String) -> String:
	if BLOCK_NAMES.has(block_key):
		return BLOCK_NAMES[block_key].get(current_lang, block_key)
	return block_key

static func tr_recipe(recipe_key: String) -> String:
	if RECIPE_NAMES.has(recipe_key):
		return RECIPE_NAMES[recipe_key].get(current_lang, recipe_key)
	return recipe_key

static func tr_ui(key: String) -> String:
	if UI.has(key):
		return UI[key].get(current_lang, key)
	return key

static func set_language(lang: String):
	current_lang = lang
