extends RefCounted
class_name POIManager

const VProfession = preload("res://scripts/villager_profession.gd")

# Registry: Vector3i (world pos) -> {block_type: int, claimed_by: NpcVillager or null, chunk_pos: Vector3i}
var poi_registry: Dictionary = {}

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

func remove_chunk_pois(chunk_pos: Vector3i):
	var to_remove: Array[Vector3i] = []
	for pos in poi_registry:
		if poi_registry[pos]["chunk_pos"] == chunk_pos:
			to_remove.append(pos)
	for pos in to_remove:
		poi_registry.erase(pos)

func find_nearest_unclaimed(profession: int, world_pos: Vector3) -> Vector3i:
	var target_block = VProfession.get_workstation_block(profession)
	if target_block < 0:
		return Vector3i(-9999, -9999, -9999)

	var best_pos = Vector3i(-9999, -9999, -9999)
	var best_dist = INF

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
		poi_registry.erase(world_pos)

func add_poi(world_pos: Vector3i, block_type: int, chunk_pos: Vector3i):
	if WORKSTATION_TYPES.has(block_type):
		poi_registry[world_pos] = {
			"block_type": block_type,
			"claimed_by": null,
			"chunk_pos": chunk_pos,
		}
