extends RefCounted
class_name VillagerProfession

enum Profession {
	NONE = 0,
	BUCHERON = 1,
	MENUISIER = 2,
	FORGERON = 3,
	BATISSEUR = 4,
	FERMIER = 5,
	BOULANGER = 6,
	CHAMAN = 7,
	MINEUR = 8,
	# === Phase 4 — Militaire ===
	ESPION = 9,
	SOLDAT = 10,
	GARDE = 11,
	CAPITAINE = 12,
}

enum Activity {
	WANDER,
	WORK,
	GATHER,
	GO_HOME,
	SLEEP,
}

# BlockType values (evite les references cross-script dans les const)
# AIR=0, GRASS=1, DIRT=2, STONE=3, SAND=4, WOOD=5, LEAVES=6, SNOW=7, CACTUS=8,
# DARK_GRASS=9, GRAVEL=10, PLANKS=11, CRAFTING_TABLE=12, BRICK=13, SANDSTONE=14,
# WATER=15, COAL_ORE=16, IRON_ORE=17, GOLD_ORE=18, IRON_INGOT=19, GOLD_INGOT=20,
# FURNACE=21, STONE_TABLE=22, IRON_TABLE=23, GOLD_TABLE=24, ..., BARREL=64
const BT_CRAFTING_TABLE = 12
const BT_FURNACE = 21
const BT_STONE_TABLE = 22
const BT_IRON_TABLE = 23
const BT_GOLD_TABLE = 24
const BT_BARREL = 64

# Chemin des skins de professions (textures 64×64 appliquées au modèle Steve)
const SKINS_PATH = "res://assets/PlayerModel/skins/"
const PROF_SKINS_PATH = "res://assets/PlayerModel/skins/professions/"

# Mapping profession -> data
# skin: fichier PNG dans professions/ (appliqué au modèle Steve GLB)
const PROFESSION_DATA = {
	Profession.NONE: {
		"workstation": -1,
		"skin": "steve.png",  # skin de base dans skins/
		"work_anim": "idle",
		"name_fr": "Villageois",
		"name_en": "Villager",
	},
	Profession.BUCHERON: {
		"workstation": BT_CRAFTING_TABLE,
		"skin": "lumberjack.png",
		"work_anim": "attack",
		"name_fr": "Bûcheron",
		"name_en": "Lumberjack",
	},
	Profession.MENUISIER: {
		"workstation": BT_CRAFTING_TABLE,
		"skin": "carpenter.png",
		"work_anim": "idle",
		"name_fr": "Menuisier",
		"name_en": "Carpenter",
	},
	Profession.FORGERON: {
		"workstation": BT_FURNACE,
		"skin": "blacksmith.png",
		"work_anim": "attack",
		"name_fr": "Forgeron",
		"name_en": "Blacksmith",
	},
	Profession.BATISSEUR: {
		"workstation": BT_STONE_TABLE,
		"skin": "builder.png",
		"work_anim": "idle",
		"name_fr": "Bâtisseur",
		"name_en": "Builder",
	},
	Profession.FERMIER: {
		"workstation": BT_CRAFTING_TABLE,
		"skin": "farmer.png",
		"work_anim": "idle",
		"name_fr": "Fermier",
		"name_en": "Farmer",
	},
	Profession.BOULANGER: {
		"workstation": BT_FURNACE,
		"skin": "baker.png",
		"work_anim": "attack",
		"name_fr": "Boulanger",
		"name_en": "Baker",
	},
	Profession.CHAMAN: {
		"workstation": BT_GOLD_TABLE,
		"skin": "shaman.png",
		"work_anim": "idle",
		"name_fr": "Chaman",
		"name_en": "Shaman",
	},
	Profession.MINEUR: {
		"workstation": BT_IRON_TABLE,
		"skin": "miner.png",
		"work_anim": "attack",
		"name_fr": "Mineur",
		"name_en": "Miner",
	},
	# === Phase 4 — Militaire ===
	Profession.ESPION: {
		"workstation": -1,
		"skin": "spy.png",
		"work_anim": "idle",
		"name_fr": "Espion",
		"name_en": "Spy",
	},
	Profession.SOLDAT: {
		"workstation": -1,
		"skin": "soldier.png",
		"work_anim": "attack",
		"name_fr": "Soldat",
		"name_en": "Soldier",
	},
	Profession.GARDE: {
		"workstation": -1,
		"skin": "guard.png",
		"work_anim": "attack",
		"name_fr": "Garde",
		"name_en": "Guard",
	},
	Profession.CAPITAINE: {
		"workstation": -1,
		"skin": "captain.png",
		"work_anim": "attack",
		"name_fr": "Capitaine",
		"name_en": "Captain",
	},
}

# Emploi du temps : plages horaires -> activité
# Utilise day_night_cycle.get_hour() qui retourne 0.0-24.0
# 14h de travail total (5-12, 13-20) pour une progression village agréable
const SCHEDULE = [
	{"start": 0.0, "end": 5.0, "activity": Activity.SLEEP},
	{"start": 5.0, "end": 12.0, "activity": Activity.WORK},
	{"start": 12.0, "end": 13.0, "activity": Activity.GATHER},
	{"start": 13.0, "end": 20.0, "activity": Activity.WORK},
	{"start": 20.0, "end": 21.0, "activity": Activity.GO_HOME},
	{"start": 21.0, "end": 24.0, "activity": Activity.SLEEP},
]

# Schedule militaire : garde/soldat travaillent 18h (4h-22h), pas de pause déjeuner
const MILITARY_SCHEDULE = [
	{"start": 0.0, "end": 4.0, "activity": Activity.SLEEP},
	{"start": 4.0, "end": 22.0, "activity": Activity.WORK},
	{"start": 22.0, "end": 24.0, "activity": Activity.SLEEP},
]

# Schedule espion : toujours en mission (travail 24/7)
const SPY_SCHEDULE = [
	{"start": 0.0, "end": 24.0, "activity": Activity.WORK},
]

static func get_activity_for_hour(hour: float, profession: int = -1) -> Activity:
	var sched = SCHEDULE
	if profession == Profession.ESPION:
		sched = SPY_SCHEDULE
	elif profession in [Profession.SOLDAT, Profession.GARDE, Profession.CAPITAINE]:
		sched = MILITARY_SCHEDULE
	for slot in sched:
		if hour >= slot["start"] and hour < slot["end"]:
			return slot["activity"]
	return Activity.SLEEP

static func get_workstation_block(prof: int) -> int:
	if PROFESSION_DATA.has(prof):
		return PROFESSION_DATA[prof]["workstation"]
	return -1

static func get_skin_for_profession(prof: int) -> String:
	if PROFESSION_DATA.has(prof):
		var skin_file = PROFESSION_DATA[prof]["skin"]
		# NONE utilise le skin de base dans skins/, les autres dans professions/
		if prof == Profession.NONE:
			return SKINS_PATH + skin_file
		return PROF_SKINS_PATH + skin_file
	return SKINS_PATH + "steve.png"

static func get_profession_name(prof: int) -> String:
	if PROFESSION_DATA.has(prof):
		return PROFESSION_DATA[prof]["name_fr"]
	return "Villageois"

static func get_work_anim(prof: int) -> String:
	if PROFESSION_DATA.has(prof):
		return PROFESSION_DATA[prof]["work_anim"]
	return "idle"

# Mapping profession → outil tenu en main
# right/left: nom de texture item (sans .png, dans TexturesPack/.../item/)
# left "shield" = cas spécial (entity texture)
const PROFESSION_TOOLS = {
	Profession.BUCHERON: {"right": "iron_axe"},
	Profession.MENUISIER: {"right": "stone_axe"},
	Profession.MINEUR: {"right": "iron_pickaxe"},
	Profession.FERMIER: {"right": "stone_hoe"},
	Profession.FORGERON: {"right": "stone_pickaxe"},
	Profession.BATISSEUR: {"right": "stone_pickaxe"},
	Profession.SOLDAT: {"right": "iron_sword"},
	Profession.GARDE: {"right": "iron_sword"},
	Profession.CAPITAINE: {"right": "iron_sword", "left": "shield"},
}

static func get_held_tools(prof: int) -> Dictionary:
	if PROFESSION_TOOLS.has(prof):
		return PROFESSION_TOOLS[prof]
	return {}
