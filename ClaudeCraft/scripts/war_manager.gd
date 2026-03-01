extends Node

# WarManager — Gère l'espionnage, le recrutement et la guerre
# Coordonne les interactions entre le village du joueur et le village ennemi.

const VProfession = preload("res://scripts/villager_profession.gd")

# === RÉFÉRENCES ===
var village_manager = null   # VillageManager du joueur
var enemy_village = null     # EnemyVillage
var world_manager = null

# === ESPIONNAGE ===
enum SpyState { IDLE, TRAVELING, SCOUTING, RETURNING, REPORTED }

var spies: Array = []  # Liste de { "direction": Vector3, "state": SpyState, "timer": float, "found": bool }
var enemy_discovered: bool = false
var enemy_position: Vector3 = Vector3.ZERO

const SPY_TRAVEL_SPEED = 8.0       # blocs par seconde (rapide, furtif)
const SPY_MAX_RANGE = 1200.0       # portée max de recherche
const SPY_SCOUT_TIME = 30.0        # temps de reconnaissance sur place

# === ARMÉE ===
enum ArmyState { NONE, ASSEMBLING, MARCHING, FIGHTING, RETURNING_VICTORY, RETURNING_DEFEAT }

var army_state: ArmyState = ArmyState.NONE
var army_soldiers: int = 0         # soldats dans l'armée en marche
var army_timer: float = 0.0        # timer de marche
var army_march_duration: float = 0.0  # durée totale de marche
var army_strength: int = 0         # force d'attaque

# === DÉFENSE VILLAGE JOUEUR ===
var guards_count: int = 0
var enemy_army_incoming: bool = false
var enemy_army_timer: float = 0.0
var enemy_attack_strength: int = 0

# === TIMERS ===
var _update_timer: float = 0.0
const UPDATE_INTERVAL = 2.0  # évaluation toutes les 2 secondes

# === PHASE DE GUERRE ===
enum WarPhase { PEACE, ESPIONAGE, PREPARATION, WAR, VICTORY, DEFEAT }
var war_phase: WarPhase = WarPhase.PEACE

func _ready():
	add_to_group("war_manager")

func _process(delta):
	if not village_manager or not enemy_village:
		# Chercher les références
		village_manager = get_tree().get_first_node_in_group("village_manager")
		enemy_village = get_tree().get_first_node_in_group("enemy_village")
		world_manager = get_tree().get_first_node_in_group("world_manager")
		return

	if enemy_village.is_destroyed:
		war_phase = WarPhase.VICTORY
		return

	var game_speed = _get_game_speed()
	var dt = delta * game_speed

	# Mettre à jour les espions
	_update_spies(dt)

	# Mettre à jour l'armée en marche
	_update_army(dt)

	# Mettre à jour l'armée ennemie
	_update_enemy_attack(dt)

	# Évaluation périodique
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_evaluate_war_status()

func _get_game_speed() -> float:
	var dnc = get_tree().get_first_node_in_group("day_night_cycle")
	if dnc and dnc.has_method("get_speed_multiplier"):
		return dnc.get_speed_multiplier()
	return 1.0

# ============================================================
# ESPIONNAGE
# ============================================================

func send_spies():
	"""Envoie 4 espions dans les 4 directions cardinales."""
	if spies.size() >= 4:
		return  # Déjà envoyés

	var directions = [
		Vector3(1, 0, 0),   # Est
		Vector3(-1, 0, 0),  # Ouest
		Vector3(0, 0, 1),   # Sud
		Vector3(0, 0, -1),  # Nord
	]

	for dir in directions:
		spies.append({
			"direction": dir,
			"state": SpyState.TRAVELING,
			"timer": 0.0,
			"distance_traveled": 0.0,
			"found": false,
		})

	war_phase = WarPhase.ESPIONAGE
	print("WarManager: 4 espions envoyés en reconnaissance")

func _update_spies(dt: float):
	for spy in spies:
		match spy["state"]:
			SpyState.TRAVELING:
				spy["timer"] += dt
				spy["distance_traveled"] = spy["timer"] * SPY_TRAVEL_SPEED

				# Vérifier si on a trouvé le village ennemi
				var spy_pos = village_manager.village_center + spy["direction"] * spy["distance_traveled"]
				var dist_to_enemy = spy_pos.distance_to(enemy_village.village_center)

				if dist_to_enemy < 50.0:
					spy["state"] = SpyState.SCOUTING
					spy["found"] = true
					spy["timer"] = 0.0
					print("WarManager: espion a trouvé le village ennemi ! Direction: %s" % str(spy["direction"]))
				elif spy["distance_traveled"] >= SPY_MAX_RANGE:
					# Rien trouvé, retour
					spy["state"] = SpyState.RETURNING
					spy["timer"] = 0.0

			SpyState.SCOUTING:
				spy["timer"] += dt
				if spy["timer"] >= SPY_SCOUT_TIME:
					spy["state"] = SpyState.RETURNING
					spy["timer"] = 0.0

			SpyState.RETURNING:
				spy["timer"] += dt
				var return_distance = spy["distance_traveled"]
				var return_time = return_distance / SPY_TRAVEL_SPEED
				if spy["timer"] >= return_time:
					spy["state"] = SpyState.REPORTED
					if spy["found"]:
						enemy_discovered = true
						enemy_position = enemy_village.village_center
						print("WarManager: rapport d'espion reçu ! Village ennemi à %s" % str(enemy_position))
						war_phase = WarPhase.PREPARATION

func get_spies_status() -> Dictionary:
	"""Retourne le statut des espions pour l'UI."""
	var sent = spies.size()
	var traveling = 0
	var returned = 0
	var found = false
	for spy in spies:
		if spy["state"] in [SpyState.TRAVELING, SpyState.SCOUTING]:
			traveling += 1
		elif spy["state"] == SpyState.REPORTED:
			returned += 1
			if spy["found"]:
				found = true
	return {
		"sent": sent,
		"traveling": traveling,
		"returned": returned,
		"found": found,
	}

# ============================================================
# ARMÉE
# ============================================================

func launch_attack(num_soldiers: int):
	"""Lance une attaque avec un nombre donné de soldats."""
	if army_state != ArmyState.NONE or not enemy_discovered:
		return

	army_soldiers = num_soldiers
	army_strength = num_soldiers * 6  # 6 points de force par soldat
	army_state = ArmyState.MARCHING

	# Calculer la durée de marche
	var distance = village_manager.village_center.distance_to(enemy_position)
	army_march_duration = distance / 4.0  # soldats marchent à 4 blocs/sec
	army_timer = 0.0

	war_phase = WarPhase.WAR
	print("WarManager: armée de %d soldats en marche ! Distance: %.0f blocs, durée: %.0fs" % [
		num_soldiers, distance, army_march_duration])

func _update_army(dt: float):
	match army_state:
		ArmyState.MARCHING:
			army_timer += dt
			if army_timer >= army_march_duration:
				_resolve_battle()

		ArmyState.RETURNING_VICTORY, ArmyState.RETURNING_DEFEAT:
			army_timer += dt
			if army_timer >= army_march_duration:
				army_state = ArmyState.NONE
				army_timer = 0.0
				if war_phase == WarPhase.WAR:
					war_phase = WarPhase.PEACE
				print("WarManager: armée de retour au village")

func _resolve_battle():
	"""Résoudre le combat."""
	print("WarManager: === BATAILLE ! ===")
	print("  Attaque: %d soldats (force %d)" % [army_soldiers, army_strength])
	print("  Défense ennemie: %d" % enemy_village.get_defense_strength())

	var destroyed = enemy_village.take_damage(army_strength)

	if destroyed:
		war_phase = WarPhase.VICTORY
		army_state = ArmyState.RETURNING_VICTORY
		army_timer = 0.0
		# Soldats survivants (pertes légères en cas de victoire)
		var losses = maxi(1, army_soldiers / 4)
		army_soldiers -= losses
		print("WarManager: VICTOIRE ! Pertes: %d soldats" % losses)
	else:
		# Défaite partielle — pertes lourdes
		var losses = maxi(army_soldiers / 2, 1)
		army_soldiers -= losses
		army_state = ArmyState.RETURNING_DEFEAT
		army_timer = 0.0
		print("WarManager: attaque repoussée. Pertes: %d soldats" % losses)

func get_army_progress() -> float:
	"""Retourne 0.0-1.0 progression de la marche."""
	if army_march_duration <= 0:
		return 0.0
	return clampf(army_timer / army_march_duration, 0.0, 1.0)

# ============================================================
# ATTAQUE ENNEMIE (l'IA attaque le joueur)
# ============================================================

func _update_enemy_attack(dt: float):
	if not enemy_village or enemy_village.is_destroyed:
		return

	if enemy_army_incoming:
		enemy_army_timer += dt
		var distance = village_manager.village_center.distance_to(enemy_village.village_center)
		var march_time = distance / 3.0  # ennemis marchent plus lentement
		if enemy_army_timer >= march_time:
			_resolve_enemy_attack()
			enemy_army_incoming = false

func _try_enemy_attack():
	"""L'IA décide d'attaquer si elle a assez de soldats."""
	if enemy_army_incoming or army_state != ArmyState.NONE:
		return
	if enemy_village.army_ready and enemy_village.soldiers_count >= 5:
		enemy_army_incoming = true
		enemy_army_timer = 0.0
		enemy_attack_strength = enemy_village.soldiers_count * 5
		print("WarManager: ALERTE ! Armée ennemie en approche (%d soldats)" % enemy_village.soldiers_count)

func _resolve_enemy_attack():
	var player_defense = guards_count * 6 + village_manager.built_structures.size() * 2
	print("WarManager: === ATTAQUE ENNEMIE ! ===")
	print("  Attaque ennemie: force %d" % enemy_attack_strength)
	print("  Défense joueur: %d (gardes: %d)" % [player_defense, guards_count])

	if enemy_attack_strength > player_defense:
		# Le village joueur subit des dégâts (perte de ressources, pas de destruction totale)
		print("WarManager: le village a subi des dégâts !")
		# Pertes de ressources
		var lost_resources = [11, 25, 71, 19]  # planches, pavé, pain, fer
		for bt in lost_resources:
			var have = village_manager.get_resource_count(bt)
			var loss = have / 3
			if loss > 0:
				village_manager.consume_resources(bt, loss)
		# Pertes de gardes
		guards_count = maxi(0, guards_count - enemy_attack_strength / 6)
	else:
		print("WarManager: attaque repoussée ! Pertes ennemies lourdes")
		enemy_village.soldiers_count = maxi(0, enemy_village.soldiers_count - 3)

# ============================================================
# ÉVALUATION STRATÉGIQUE
# ============================================================

func _evaluate_war_status():
	if not village_manager:
		return

	# Phase 4 du village joueur = activer la guerre
	if village_manager.village_phase >= 4:
		# Envoyer les espions si pas encore fait
		if spies.size() == 0 and war_phase == WarPhase.PEACE:
			send_spies()

		# Si ennemi découvert et assez de soldats, préparer l'attaque
		if enemy_discovered and war_phase == WarPhase.PREPARATION:
			var swords = village_manager.get_resource_count(73)  # IRON_SWORD
			var bread = village_manager.get_resource_count(71)   # BREAD
			# Auto-lancer l'attaque quand on a 5+ épées et 10+ pains
			if swords >= 5 and bread >= 10 and army_state == ArmyState.NONE:
				# Recruter les soldats
				var num_soldiers = mini(swords, bread / 2)
				num_soldiers = mini(num_soldiers, 8)  # max 8 soldats par vague
				if num_soldiers >= 3:
					village_manager.consume_resources(73, num_soldiers)  # épées
					village_manager.consume_resources(71, num_soldiers * 2)  # pain
					launch_attack(num_soldiers)

	# L'IA ennemie peut aussi attaquer
	if enemy_village and enemy_village.village_phase >= 3:
		_try_enemy_attack()

# ============================================================
# UI — INTERFACE
# ============================================================

func get_war_status_text() -> String:
	match war_phase:
		WarPhase.PEACE:
			return "Paix"
		WarPhase.ESPIONAGE:
			var spy_status = get_spies_status()
			return "Espionnage — %d/%d espions en mission" % [spy_status["traveling"], spy_status["sent"]]
		WarPhase.PREPARATION:
			return "Préparation — Village ennemi découvert !"
		WarPhase.WAR:
			if army_state == ArmyState.MARCHING:
				return "Guerre — Armée en marche (%d%%)" % int(get_army_progress() * 100)
			elif army_state == ArmyState.RETURNING_VICTORY:
				return "Victoire — Armée de retour"
			elif army_state == ArmyState.RETURNING_DEFEAT:
				return "Retraite — Armée de retour"
			return "Guerre"
		WarPhase.VICTORY:
			return "VICTOIRE — Village ennemi détruit !"
		WarPhase.DEFEAT:
			return "DÉFAITE"
	return ""

func get_enemy_status_text() -> String:
	if not enemy_village:
		return "Inconnu"
	if not enemy_discovered:
		return "Non découvert"
	return enemy_village.get_status_text()
