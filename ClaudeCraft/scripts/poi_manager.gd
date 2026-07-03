extends RefCounted
class_name POIManager

## POIManager v2.0.0 — registre des workstations (points d'intérêt village)
##
## Changelog :
## v2.0.0 — Index spatial par chunk : find_nearest_unclaimed passe de O(n) sur
##          tous les POI du monde à une recherche en anneaux de chunks croissants
##          autour du demandeur (fallback scan complet si rien dans le rayon).
##          Élimine le coût quadratique du _evaluate_needs village (9 PNJ × 8s).
## v1.0.0 — Version initiale (scan linéaire)

const VProfession = preload("res://scripts/villager_profession.gd")

# Registry: Vector3i (world pos) -> {block_type: int, claimed_by: NpcVillager or null, chunk_pos: Vector3i}
var poi_registry: Dictionary = {}

# Index spatial : chunk_pos (Vector3i, y=0) -> Dictionary { world_pos: true }
var _by_chunk: Dictionary = {}

# Workstation block type values (valeurs de BlockRegistry.BlockType enum)
# CRAFTING_TABLE=12, FURNACE=21, STONE_TABLE=22, IRON_TABLE=23, GOLD_TABLE=24, BARREL=64
const WORKSTATION_TYPES: Dictionary = {
	12: true,
	21: true,
	22: true,
	23: true,
	24: true,
	64: true,
}

const CHUNK_SIZE = 16
const CHUNK_HEIGHT = 256
const MAX_SEARCH_RING = 12  # 12 chunks = 192 blocs de rayon avant fallback complet

func scan_chunk(chunk_pos: Vector3i, packed_blocks: PackedByteArray, y_min: int, y_max: int):
	var base_x = chunk_pos.x * CHUNK_SIZE
	var base_z = chunk_pos.z * CHUNK_SIZE

	for x in range(CHUNK_SIZE):
		var x_off = x * CHUNK_SIZE * CHUNK_HEIGHT
		for z in range(CHUNK_SIZE):
			var xz_off = x_off + z * CHUNK_HEIGHT
			for y in range(y_min, y_max + 1):
				var bt = packed_blocks[xz_off + y]
				if WORKSTATION_TYPES.has(bt):
					var world_pos = Vector3i(base_x + x, y, base_z + z)
					if not poi_registry.has(world_pos):
						poi_registry[world_pos] = {
							"block_type": bt,
							"claimed_by": null,
							"chunk_pos": chunk_pos,
						}
						_index_add(chunk_pos, world_pos)

func remove_chunk_pois(chunk_pos: Vector3i):
	# Grâce à l'index, plus besoin d'itérer tout le registre
	var key := Vector3i(chunk_pos.x, 0, chunk_pos.z)
	if not _by_chunk.has(key):
		return
	for pos in _by_chunk[key]:
		poi_registry.erase(pos)
	_by_chunk.erase(key)

func find_nearest_unclaimed(profession: int, world_pos: Vector3) -> Vector3i:
	var target_block = VProfession.get_workstation_block(profession)
	if target_block < 0:
		return Vector3i(-9999, -9999, -9999)

	var center := Vector3i(int(floor(world_pos.x / 16.0)), 0, int(floor(world_pos.z / 16.0)))
	var best_pos = Vector3i(-9999, -9999, -9999)
	var best_dist = INF

	# Recherche en anneaux de chunks croissants (chebyshev). On continue tant
	# qu'un anneau plus lointain pourrait encore contenir un POI plus proche.
	var r := 0
	while r <= MAX_SEARCH_RING:
		# Distance minimale possible d'un POI de l'anneau r : (r-1) chunks
		if best_dist < INF:
			var min_ring_dist := float(maxi(r - 1, 0) * CHUNK_SIZE)
			if min_ring_dist * min_ring_dist > best_dist:
				break
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				# Ne visiter que le pourtour de l'anneau (l'intérieur est déjà fait)
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var key := Vector3i(center.x + dx, 0, center.z + dz)
				if not _by_chunk.has(key):
					continue
				for pos in _by_chunk[key]:
					var data = poi_registry.get(pos)
					if data == null:
						continue
					if data["block_type"] == target_block and data["claimed_by"] == null:
						var dist = world_pos.distance_squared_to(Vector3(pos.x + 0.5, pos.y, pos.z + 0.5))
						if dist < best_dist:
							best_dist = dist
							best_pos = pos
		r += 1

	if best_pos.x > -9000:
		return best_pos

	# Fallback rare : rien dans le rayon indexé → scan complet (comportement v1)
	for pos in poi_registry:
		var data = poi_registry[pos]
		if data["block_type"] == target_block and data["claimed_by"] == null:
			var dist = world_pos.distance_squared_to(Vector3(pos.x + 0.5, pos.y, pos.z + 0.5))
			if dist < best_dist:
				best_dist = dist
				best_pos = pos
	return best_pos

func claim_poi(poi_pos: Vector3i, npc) -> bool:
	if poi_registry.has(poi_pos) and poi_registry[poi_pos]["claimed_by"] == null:
		poi_registry[poi_pos]["claimed_by"] = npc
		return true
	return false

func release_poi(poi_pos: Vector3i):
	if poi_registry.has(poi_pos):
		poi_registry[poi_pos]["claimed_by"] = null

func remove_poi_at(world_pos: Vector3i):
	if poi_registry.has(world_pos):
		var chunk_pos: Vector3i = poi_registry[world_pos]["chunk_pos"]
		poi_registry.erase(world_pos)
		_index_remove(chunk_pos, world_pos)

func add_poi(world_pos: Vector3i, block_type: int, chunk_pos: Vector3i):
	if WORKSTATION_TYPES.has(block_type):
		poi_registry[world_pos] = {
			"block_type": block_type,
			"claimed_by": null,
			"chunk_pos": chunk_pos,
		}
		_index_add(chunk_pos, world_pos)

# ============================================================
# INDEX SPATIAL
# ============================================================

func _index_add(chunk_pos: Vector3i, world_pos: Vector3i):
	var key := Vector3i(chunk_pos.x, 0, chunk_pos.z)
	if not _by_chunk.has(key):
		_by_chunk[key] = {}
	_by_chunk[key][world_pos] = true

func _index_remove(chunk_pos: Vector3i, world_pos: Vector3i):
	var key := Vector3i(chunk_pos.x, 0, chunk_pos.z)
	if _by_chunk.has(key):
		_by_chunk[key].erase(world_pos)
		if _by_chunk[key].is_empty():
			_by_chunk.erase(key)
