extends Node
## fluid_flow_manager.gd v1.0.0 — Autoload, moteur de propagation de fluides
##
## Phase 1 de l'opération "Eau Vivante" :
##  - Tick-based BFS (200ms par étape) → visuel "eau qui coule"
##  - Gravité d'abord (l'eau descend), puis propagation horizontale
##  - Extension max 7 blocs depuis la source → anti-Waterworld naturel
##  - Détection "plaine ouverte 3x3" → arrêt net si on atteint un grand plat
##  - L'eau ne remonte JAMAIS (on ne scanne jamais vers +Y)
##  - Système générique : fonctionnera pour lave en Phase 3 (changer fluid_type)
##
## API publique :
##  - schedule_break_fill_check(broken_pos) → appelée par world_manager quand
##    un bloc est cassé ; scanne les voisins et lance le flow si eau adjacente
##  - schedule_source(pos, fluid_type) → pour placement bucket (Phase 2)
##
## Changelog :
##  v1.0.0 — Phase 1 : propagation eau via break events, BFS tick-based
##  v1.0.1 — Tick 0.2 → 0.4s, délai 2 ticks avant apparition break fill
##  v1.0.2 — Scan -Y inclus dans break_fill_check (fix : trou au niveau d'une
##           surface d'eau ne se remplissait pas si l'eau n'était qu'en dessous)
##  v1.1.0 — Phase 2 : bucket (seau) — schedule_source() utilisé par player.gd
##           quand on verse de l'eau depuis un BUCKET_WATER

const APP_VERSION := "1.1.0"

# ============================================================
# CONFIG
# ============================================================
const TICK_INTERVAL := 0.4          # 400ms entre chaque étape de propagation
const MAX_FLOW_LEVEL := 8           # niveau "source", décrémenté à chaque spread
const MAX_FLOWS_PER_TICK := 200     # cap pour éviter stutters
const BREAK_FILL_DELAY_TICKS := 2   # 2 ticks d'attente avant qu'un fill break apparaisse (→ ~0.8s)
const DEBUG_FLOW := false           # true = log chaque étape dans la console

# ============================================================
# ÉTAT INTERNE
# ============================================================
var _world_manager: Node = null
# Queue BFS : chaque item est un Dictionary { pos: Vector3i, level: int, fluid: int }
var _queue: Array = []
var _tick_timer: float = 0.0

func _ready():
	set_process(true)
	if DEBUG_FLOW:
		print("[FluidFlow] Ready — tick %s ms, max_level %d" % [TICK_INTERVAL * 1000.0, MAX_FLOW_LEVEL])

func _process(delta: float):
	# Résoudre world_manager une seule fois (il n'existe pas au _ready de l'autoload)
	if _world_manager == null:
		_world_manager = get_tree().get_first_node_in_group("world_manager")
		if _world_manager == null:
			return

	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	_tick_timer = 0.0
	_process_tick()

# ============================================================
# API PUBLIQUE
# ============================================================

## Appelée par world_manager.break_block_at_position quand un bloc est cassé.
## Scanne les voisins (4 horizontaux + dessus) du bloc cassé. Si l'un est
## de l'eau, on schedule un remplissage de la position cassée.
func schedule_break_fill_check(broken_pos: Vector3i):
	if _world_manager == null:
		_world_manager = get_tree().get_first_node_in_group("world_manager")
		if _world_manager == null:
			return

	# On scanne les 6 voisins. -Y inclus : si de l'eau est juste en dessous du
	# bloc cassé, c'est que le bloc cassé était au niveau (ou juste au-dessus)
	# d'une surface d'eau → intuitivement le trou doit se remplir.
	# Ça ne viole PAS la règle "l'eau ne remonte pas" parce que :
	#   - Le fill déclenché ici ne se produit qu'UNE SEULE FOIS au point cassé
	#   - La propagation dans _try_flow ne scanne JAMAIS vers +Y
	#     (pas de cascade ascendante, pas d'effet Waterworld vertical)
	var neighbors := [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	]
	for offset in neighbors:
		var n_pos: Vector3i = broken_pos + offset
		var n_type: int = _world_manager.get_block_at_position(Vector3(n_pos))
		if n_type == BlockRegistry.BlockType.WATER:
			# Un voisin est de l'eau → le trou peut se remplir.
			# Niveau = MAX - 1 (7) : on réserve 1 cran comme "coût" du flow
			# initial, mais il reste 6 crans pour propager plus loin.
			# `delay` = nb de ticks d'attente avant l'apparition visuelle (~0.8s)
			_queue.append({
				"pos": broken_pos,
				"level": MAX_FLOW_LEVEL - 1,
				"fluid": BlockRegistry.BlockType.WATER,
				"delay": BREAK_FILL_DELAY_TICKS,
			})
			if DEBUG_FLOW:
				print("[FluidFlow] Break fill schedulé à ", broken_pos)
			return  # Un seul trigger suffit

## Place une source de fluide et lance le flow (pour bucket en Phase 2)
func schedule_source(pos: Vector3i, fluid_type: int = BlockRegistry.BlockType.WATER):
	_queue.append({ "pos": pos, "level": MAX_FLOW_LEVEL, "fluid": fluid_type })

# ============================================================
# TICK LOOP
# ============================================================

func _process_tick():
	if _queue.is_empty():
		return

	var next_wave: Array = []
	var processed := 0

	while processed < MAX_FLOWS_PER_TICK and not _queue.is_empty():
		var item = _queue.pop_front()
		_try_flow(item, next_wave)
		processed += 1

	# Les nouvelles positions spawnées par le tick seront traitées au tick suivant
	for item in next_wave:
		_queue.append(item)

func _try_flow(item: Dictionary, next_wave: Array):
	var pos: Vector3i = item.pos
	var level: int = item.level
	var fluid: int = item.fluid

	if level <= 0:
		return
	if _world_manager == null:
		return

	# Délai d'attente avant apparition (pour un feel moins instantané)
	if item.has("delay") and item.delay > 0:
		item.delay -= 1
		next_wave.append(item)
		return

	# La position doit être AIR (sinon un autre flow l'a déjà remplie)
	var here_type: int = _world_manager.get_block_at_position(Vector3(pos))
	if here_type != BlockRegistry.BlockType.AIR:
		return

	# Placer le fluide
	_world_manager.set_block_at_position(Vector3(pos), fluid)

	if DEBUG_FLOW:
		print("[FluidFlow] Placé à ", pos, " level=", level)

	# ─────────────────────────────────────────
	# 1) GRAVITÉ — descend en priorité
	# ─────────────────────────────────────────
	var below: Vector3i = pos + Vector3i(0, -1, 0)
	var below_type: int = _world_manager.get_block_at_position(Vector3(below))
	if below_type == BlockRegistry.BlockType.AIR:
		# Chute : niveau max, pas d'extension latérale à ce tick
		next_wave.append({
			"pos": below,
			"level": MAX_FLOW_LEVEL,
			"fluid": fluid,
		})
		return

	# ─────────────────────────────────────────
	# 2) PROPAGATION HORIZONTALE
	# ─────────────────────────────────────────
	if level <= 1:
		return  # Plus d'énergie pour s'étendre

	# ANTI-WATERWORLD : si on est au milieu d'une plaine ouverte 3x3,
	# on stoppe l'extension pour éviter l'inondation infinie.
	if _is_open_plain(pos):
		if DEBUG_FLOW:
			print("[FluidFlow] Plaine ouverte détectée à ", pos, " → arrêt")
		return

	var next_level: int = level - 1
	for offset in [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
		var n_pos: Vector3i = pos + offset
		var n_type: int = _world_manager.get_block_at_position(Vector3(n_pos))
		if n_type == BlockRegistry.BlockType.AIR:
			next_wave.append({
				"pos": n_pos,
				"level": next_level,
				"fluid": fluid,
			})

# ============================================================
# ANTI-WATERWORLD : détection plaine ouverte
# ============================================================

## Retourne true si les 8 voisins horizontaux de `center` sont TOUS
## AIR ou WATER (donc pas de mur bloquant) → on est au milieu d'une
## surface 3x3 ouverte, l'eau ne doit plus s'étendre.
## Cette règle s'ajoute à la décrémentation de niveau : elle évite
## que l'eau qui tombe d'une cascade sur une plage envahisse la plage.
func _is_open_plain(center: Vector3i) -> bool:
	if _world_manager == null:
		return false
	var open_count := 0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var p: Vector3i = center + Vector3i(dx, 0, dz)
			var t: int = _world_manager.get_block_at_position(Vector3(p))
			if t == BlockRegistry.BlockType.AIR or t == BlockRegistry.BlockType.WATER:
				open_count += 1
	# 8/8 ouverts = plaine pleine 3x3 → on stoppe
	return open_count >= 8
