extends Node

# EnemyVillage — Village ennemi simulé (pas de chunks réels)
# Progresse abstraitement Phase 0→3 avec des timers.
# Quand le joueur/soldats approchent, instancie les bâtiments réels.

const VProfession = preload("res://scripts/villager_profession.gd")

# === POSITION ===
var village_center: Vector3 = Vector3.ZERO
var village_ref_y: int = 70  # altitude estimée

# === PROGRESSION SIMULÉE ===
var village_phase: int = 0
var village_tool_tier: int = 0
var population: int = 5  # démarre avec 5 villageois
var max_population: int = 25

# === STOCKPILE VIRTUEL ===
var stockpile: Dictionary = {}

# === BÂTIMENTS CONSTRUITS (compteur par type) ===
var buildings: Dictionary = {
	"Cabane": 0,
	"Ferme": 0,
	"Forge": 0,
	"Maison": 0,
	"Entrepôt": 0,
	"Taverne": 0,
	"Moulin": 0,
	"Chapelle": 0,
	"Caserne": 0,
	"Donjon": 0,
	"Rempart": 0,
	"Tour de défense": 0,
}
var total_buildings: int = 0

# === ARMÉE ===
var swords_count: int = 0
var shields_count: int = 0
var soldiers_count: int = 0
var guards_count: int = 0
var army_ready: bool = false

# === TIMERS ===
var _phase_timer: float = 0.0
var _build_timer: float = 0.0
var _production_timer: float = 0.0
var _cached_dnc = null  # cached day_night_cycle reference

# Vitesse de progression (secondes de jeu par unité de production)
const PHASE_ADVANCE_TIME = 300.0   # 5 minutes pour avancer de phase
const BUILD_INTERVAL = 45.0        # nouveau bâtiment toutes les 45s
const PRODUCTION_INTERVAL = 10.0   # production de ressources toutes les 10s

# === ÉTAT ===
var is_discovered: bool = false    # le joueur a trouvé ce village
var is_destroyed: bool = false     # le village a été détruit
var _initialized: bool = false

# Référence monde (pour instancier les chunks quand nécessaire)
var world_manager = null

func initialize(center: Vector3, ref_y: int = 70):
	village_center = center
	village_ref_y = ref_y
	_initialized = true
	# Stockpile de départ
	stockpile = {
		5: 20,    # WOOD
		11: 40,   # PLANKS
		3: 10,    # STONE
		25: 20,   # COBBLESTONE
		16: 5,    # COAL_ORE
	}
	#print("EnemyVillage: initialisé à %s (ref_y=%d)" % [str(center), ref_y])

func _process(delta):
	if not _initialized or is_destroyed:
		return

	var game_speed = _get_game_speed()
	var dt = delta * game_speed

	# Production de ressources (simulée)
	_production_timer += dt
	if _production_timer >= PRODUCTION_INTERVAL:
		_production_timer = 0.0
		_simulate_production()

	# Construction de bâtiments
	_build_timer += dt
	if _build_timer >= BUILD_INTERVAL:
		_build_timer = 0.0
		_simulate_build()

	# Progression de phase
	_phase_timer += dt
	if _phase_timer >= PHASE_ADVANCE_TIME:
		_phase_timer = 0.0
		_try_advance_phase()

func _get_game_speed() -> float:
	if _cached_dnc == null or not is_instance_valid(_cached_dnc):
		_cached_dnc = get_tree().get_first_node_in_group("day_night_cycle")
	if _cached_dnc and _cached_dnc.has_method("get_speed_multiplier"):
		return _cached_dnc.get_speed_multiplier()
	return 1.0

func _simulate_production():
	# Simuler la récolte/production selon la phase
	match village_phase:
		0:
			_add_stock(5, randi_range(2, 4))   # bois
			_add_stock(11, randi_range(4, 8))   # planches
		1:
			_add_stock(5, randi_range(3, 6))
			_add_stock(11, randi_range(6, 12))
			_add_stock(25, randi_range(2, 5))   # cobblestone
			_add_stock(16, randi_range(1, 2))   # charbon
		2:
			_add_stock(5, randi_range(4, 8))
			_add_stock(11, randi_range(8, 16))
			_add_stock(25, randi_range(4, 8))
			_add_stock(16, randi_range(2, 4))
			_add_stock(17, randi_range(1, 2))   # fer ore
			_add_stock(19, randi_range(0, 1))   # fer ingot
			_add_stock(71, randi_range(1, 3))   # pain
		3:
			_add_stock(5, randi_range(5, 10))
			_add_stock(11, randi_range(10, 20))
			_add_stock(25, randi_range(6, 12))
			_add_stock(16, randi_range(3, 6))
			_add_stock(17, randi_range(2, 4))
			_add_stock(19, randi_range(1, 3))
			_add_stock(71, randi_range(2, 5))   # pain
			# Production militaire Phase 3+
			if village_phase >= 3 and total_buildings >= 5:
				_simulate_military_production()

func _simulate_military_production():
	var iron = _get_stock(19)
	var planks = _get_stock(11)
	var bread = _get_stock(71)

	# Forger des épées (2 fer + 1 planche)
	if iron >= 2 and planks >= 1 and swords_count < 10:
		_consume_stock(19, 2)
		_consume_stock(11, 1)
		swords_count += 1

	# Recruter des soldats (1 épée + 2 pains)
	if swords_count > soldiers_count and bread >= 2 and soldiers_count < 8:
		swords_count -= 1
		_consume_stock(71, 2)
		soldiers_count += 1

	# L'armée est prête quand on a 5+ soldats
	army_ready = soldiers_count >= 5

func _simulate_build():
	if village_phase == 0:
		return

	# Construire des bâtiments selon la phase
	var to_build = ""
	match village_phase:
		1:
			if buildings["Cabane"] < 2:
				to_build = "Cabane"
			elif buildings["Ferme"] < 1:
				to_build = "Ferme"
		2:
			if buildings["Forge"] < 1:
				to_build = "Forge"
			elif buildings["Maison"] < 2:
				to_build = "Maison"
			elif buildings["Entrepôt"] < 1:
				to_build = "Entrepôt"
		3:
			if buildings["Taverne"] < 1:
				to_build = "Taverne"
			elif buildings["Moulin"] < 1:
				to_build = "Moulin"
			elif buildings["Chapelle"] < 1:
				to_build = "Chapelle"
			elif buildings["Caserne"] < 1:
				to_build = "Caserne"
			elif buildings["Donjon"] < 1:
				to_build = "Donjon"
			elif buildings["Rempart"] < 4:
				to_build = "Rempart"
			elif buildings["Tour de défense"] < 4:
				to_build = "Tour de défense"

	if to_build != "":
		buildings[to_build] += 1
		total_buildings += 1
		# Augmenter la population
		if population < max_population and total_buildings % 2 == 0:
			population += 1

func _try_advance_phase():
	if village_phase >= 3:
		return  # Max phase pour l'IA

	match village_phase:
		0:
			if _get_stock(11) >= 20:  # 20 planches
				village_phase = 1
				village_tool_tier = 1
				#print("EnemyVillage: === PHASE 1 — ÂGE DU BOIS ===")
		1:
			if _get_stock(25) >= 30 and total_buildings >= 2:
				village_phase = 2
				village_tool_tier = 2
				#print("EnemyVillage: === PHASE 2 — ÂGE DE LA PIERRE ===")
		2:
			if _get_stock(19) >= 5 and total_buildings >= 5:
				village_phase = 3
				village_tool_tier = 3
				#print("EnemyVillage: === PHASE 3 — ÂGE DU FER ===")

func _add_stock(bt: int, amount: int):
	stockpile[bt] = stockpile.get(bt, 0) + amount

func _consume_stock(bt: int, amount: int) -> bool:
	var have = stockpile.get(bt, 0)
	if have >= amount:
		stockpile[bt] = have - amount
		return true
	return false

func _get_stock(bt: int) -> int:
	return stockpile.get(bt, 0)

# === INTERFACE POUR LE WAR MANAGER ===

func get_defense_strength() -> int:
	# Force défensive = soldats + gardes + murs
	return soldiers_count + guards_count + buildings.get("Rempart", 0) * 2 + buildings.get("Tour de défense", 0) * 3

func take_damage(attack_strength: int) -> bool:
	# Retourne true si le village est détruit
	var defense = get_defense_strength()
	if attack_strength > defense:
		is_destroyed = true
		#print("EnemyVillage: DÉTRUIT ! (attaque %d vs défense %d)" % [attack_strength, defense])
		return true
	else:
		# Pertes
		var losses = attack_strength / 3
		soldiers_count = maxi(0, soldiers_count - losses)
		#print("EnemyVillage: attaque repoussée (attaque %d vs défense %d, pertes: %d)" % [attack_strength, defense, losses])
		return false

func get_status_text() -> String:
	if is_destroyed:
		return "Détruit"
	return "Phase %d — Pop: %d — Soldats: %d — Bâtiments: %d" % [village_phase, population, soldiers_count, total_buildings]
