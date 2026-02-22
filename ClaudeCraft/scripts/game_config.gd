extends Node
class_name GameConfig

## Configuration centrale du jeu — changer ACTIVE_PACK pour switcher de texture pack

# ========================================
# PACK DE TEXTURES ACTIF
# Changer cette ligne pour switcher de pack
# ========================================
#const ACTIVE_PACK = "Aurore Stone"
#const ACTIVE_PACK = "Faithful64x64"
const ACTIVE_PACK = "Faithful32"

const PACK_BASE = "res://TexturesPack/"

static func get_block_texture_path() -> String:
	return PACK_BASE + ACTIVE_PACK + "/assets/minecraft/textures/block/"

static func get_item_texture_path() -> String:
	return PACK_BASE + ACTIVE_PACK + "/assets/minecraft/textures/item/"

static func get_entity_texture_path() -> String:
	return PACK_BASE + ACTIVE_PACK + "/assets/minecraft/textures/entity/"

static func get_pack_path() -> String:
	return PACK_BASE + ACTIVE_PACK + "/"

# Aliases pour les textures manquantes selon le pack
# Quand un nom de texture n'existe pas, on essaie l'alias
const TEXTURE_ALIASES: Dictionary = {
	"cactus_side": "cactus_bottom",
	"cactus_top": "cactus_bottom",
	"sandstone_side": "sandstone",
	"sandstone_bottom": "sandstone",
	"birch_log_top": "oak_log_top",
	"jungle_leaves": "oak_leaves",
	"coal_block": "coal_ore",
	"podzol_side": "podzol_top",
}

## Resout le chemin absolu d'une texture bloc, avec fallback alias
static func resolve_block_texture(tex_name: String) -> String:
	var base = get_block_texture_path()
	var path = base + tex_name + ".png"
	var abs_path = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		return abs_path
	if TEXTURE_ALIASES.has(tex_name):
		var alias_path = base + TEXTURE_ALIASES[tex_name] + ".png"
		var abs_alias = ProjectSettings.globalize_path(alias_path)
		if FileAccess.file_exists(abs_alias):
			return abs_alias
	return ""
