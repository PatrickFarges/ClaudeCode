extends Node
class_name GameConfig

## Configuration centrale du jeu — changer ACTIVE_PACK pour switcher de texture pack

# ========================================
# PACK DE TEXTURES ACTIF
# Changer cette ligne pour switcher de pack
# ========================================
#const ACTIVE_PACK = "Aurore Stone"
const ACTIVE_PACK = "Faithful64x64"

const PACK_BASE = "res://TexturesPack/"

static func get_block_texture_path() -> String:
	return PACK_BASE + ACTIVE_PACK + "/assets/minecraft/textures/block/"

static func get_item_texture_path() -> String:
	return PACK_BASE + ACTIVE_PACK + "/assets/minecraft/textures/item/"

static func get_entity_texture_path() -> String:
	return PACK_BASE + ACTIVE_PACK + "/assets/minecraft/textures/entity/"

static func get_pack_path() -> String:
	return PACK_BASE + ACTIVE_PACK + "/"
