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

# Mapping profession -> data
# models: 2 indices parmi les 18 modèles character-a (0) à character-r (17)
const PROFESSION_DATA = {
	Profession.NONE: {
		"workstation": -1,
		"models": [0, 1],
		"work_anim": "idle",
		"name_fr": "Villageois",
		"name_en": "Villager",
	},
	Profession.BUCHERON: {
		"workstation": BT_CRAFTING_TABLE,
		"models": [2, 3],
		"work_anim": "attack",
		"name_fr": "Bûcheron",
		"name_en": "Lumberjack",
	},
	Profession.MENUISIER: {
		"workstation": BT_CRAFTING_TABLE,
		"models": [4, 5],
		"work_anim": "idle",
		"name_fr": "Menuisier",
		"name_en": "Carpenter",
	},
	Profession.FORGERON: {
		"workstation": BT_FURNACE,
		"models": [6, 7],
		"work_anim": "attack",
		"name_fr": "Forgeron",
		"name_en": "Blacksmith",
	},
	Profession.BATISSEUR: {
		"workstation": BT_STONE_TABLE,
		"models": [8, 9],
		"work_anim": "idle",
		"name_fr": "Bâtisseur",
		"name_en": "Builder",
	},
	Profession.FERMIER: {
		"workstation": BT_CRAFTING_TABLE,
		"models": [10, 11],
		"work_anim": "idle",
		"name_fr": "Fermier",
		"name_en": "Farmer",
	},
	Profession.BOULANGER: {
		"workstation": BT_FURNACE,
		"models": [12, 13],
		"work_anim": "attack",
		"name_fr": "Boulanger",
		"name_en": "Baker",
	},
	Profession.CHAMAN: {
		"workstation": BT_GOLD_TABLE,
		"models": [14, 15],
		"work_anim": "idle",
		"name_fr": "Chaman",
		"name_en": "Shaman",
	},
	Profession.MINEUR: {
		"workstation": BT_IRON_TABLE,
		"models": [16, 17],
		"work_anim": "attack",
		"name_fr": "Mineur",
		"name_en": "Miner",
	},
}

# Emploi du temps : plages horaires -> activité
# Utilise day_night_cycle.get_hour() qui retourne 0.0-24.0
# 11h de travail total (6-12, 13-18) pour une progression village agréable
const SCHEDULE = [
	{"start": 0.0, "end": 6.0, "activity": Activity.SLEEP},
	{"start": 6.0, "end": 12.0, "activity": Activity.WORK},
	{"start": 12.0, "end": 13.0, "activity": Activity.GATHER},
	{"start": 13.0, "end": 18.0, "activity": Activity.WORK},
	{"start": 18.0, "end": 19.0, "activity": Activity.GATHER},
	{"start": 19.0, "end": 20.0, "activity": Activity.GO_HOME},
	{"start": 20.0, "end": 24.0, "activity": Activity.SLEEP},
]

static func get_activity_for_hour(hour: float) -> Activity:
	for slot in SCHEDULE:
		if hour >= slot["start"] and hour < slot["end"]:
			return slot["activity"]
	return Activity.SLEEP

static func get_workstation_block(prof: int) -> int:
	if PROFESSION_DATA.has(prof):
		return PROFESSION_DATA[prof]["workstation"]
	return -1

static func get_model_for_profession(prof: int, seed_val: int) -> int:
	if PROFESSION_DATA.has(prof):
		var models = PROFESSION_DATA[prof]["models"]
		return models[seed_val % models.size()]
	return 0

static func get_profession_name(prof: int) -> String:
	if PROFESSION_DATA.has(prof):
		return PROFESSION_DATA[prof]["name_fr"]
	return "Villageois"

static func get_work_anim(prof: int) -> String:
	if PROFESSION_DATA.has(prof):
		return PROFESSION_DATA[prof]["work_anim"]
	return "idle"
