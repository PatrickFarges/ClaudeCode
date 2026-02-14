extends Node
class_name StructureManagerClass

# Système de "Structure Stamps" — placement de structures prédéfinies dans le monde.
#
# Fichiers structure : res://structures/*.json
# Format JSON :
#   {
#     "name": "nom_structure",
#     "size": [sx, sy, sz],
#     "palette": ["AIR", "STONE", "WOOD", "KEEP", ...],
#     "blocks_rle": [palette_idx, count, palette_idx, count, ...]
#   }
#
# Ordre de stockage : layer-first (y-major) → index = y * (sx * sz) + z * sx + x
# "KEEP" dans la palette = ne pas toucher le bloc terrain existant.
#
# Fichier de placements : user://structures_placement.json (ou res://structures/placements.json)
# Format :
#   {
#     "placements": [
#       {"structure": "nom_structure", "position": [wx, wy, wz]},
#       ...
#     ]
#   }

const KEEP_BLOCK: int = 255

var _structures: Dictionary = {}  # name -> {size: Vector3i, blocks: PackedByteArray}
var _placements: Array = []

func _ready():
	_load_all_structures()
	_load_placements()

# ============================================================
# CHARGEMENT DES STRUCTURES
# ============================================================

func _load_all_structures():
	var dir = DirAccess.open("res://structures")
	if not dir:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and file_name != "placements.json":
			_load_structure(file_name.get_basename(), "res://structures/" + file_name)
		file_name = dir.get_next()

func _load_structure(sname: String, path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("StructureManager: impossible de lire " + path)
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("StructureManager: JSON invalide dans " + path)
		return

	var data = json.data
	if not data.has("size") or not data.has("palette") or not data.has("blocks_rle"):
		push_warning("StructureManager: champs manquants dans " + path)
		return

	var size = Vector3i(int(data.size[0]), int(data.size[1]), int(data.size[2]))

	# Construire la palette : nom de bloc -> byte
	var palette_names: Array = data.palette
	var palette: PackedByteArray = PackedByteArray()
	for pname in palette_names:
		if pname == "KEEP":
			palette.append(KEEP_BLOCK)
		else:
			var resolved = _resolve_block_type(pname)
			palette.append(resolved)

	# Décoder le RLE
	var rle: Array = data.blocks_rle
	var total = size.x * size.y * size.z
	var blocks = PackedByteArray()
	blocks.resize(total)
	var pos = 0
	var i = 0
	while i + 1 < rle.size():
		var palette_idx = int(rle[i])
		var count = int(rle[i + 1])
		var block_val: int = palette[palette_idx] if palette_idx < palette.size() else 0
		for j in range(count):
			if pos < total:
				blocks[pos] = block_val
				pos += 1
		i += 2

	if pos != total:
		push_warning("StructureManager: RLE incomplet dans %s (%d/%d blocs)" % [path, pos, total])

	_structures[sname] = {"size": size, "blocks": blocks}
	print("StructureManager: '%s' chargée (%dx%dx%d)" % [sname, size.x, size.y, size.z])

func _resolve_block_type(block_name: String) -> int:
	if block_name == "AIR":
		return 0
	for key in BlockRegistry.BlockType.keys():
		if key == block_name:
			return BlockRegistry.BlockType[key]
	push_warning("StructureManager: type de bloc inconnu '%s', remplacé par AIR" % block_name)
	return 0

# ============================================================
# CHARGEMENT DES PLACEMENTS
# ============================================================

func _load_placements():
	_placements.clear()

	var path = "user://structures_placement.json"
	if not FileAccess.file_exists(path):
		path = "res://structures/placements.json"
	if not FileAccess.file_exists(path):
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("StructureManager: JSON invalide dans " + path)
		return

	var data = json.data
	if not data.has("placements"):
		return

	for p in data.placements:
		var struct_name = str(p.structure)
		if not _structures.has(struct_name):
			push_warning("StructureManager: structure '%s' introuvable, placement ignoré" % struct_name)
			continue
		var pos = Vector3i(int(p.position[0]), int(p.position[1]), int(p.position[2]))
		_placements.append({"structure": struct_name, "position": pos})

	if _placements.size() > 0:
		print("StructureManager: %d placement(s) chargé(s)" % _placements.size())

# ============================================================
# API POUR LE CHUNK GENERATOR (thread-safe, lecture seule)
# ============================================================

func get_placement_data() -> Array:
	"""Retourne un snapshot thread-safe de tous les placements avec leurs données de blocs."""
	var result = []
	for p in _placements:
		var struct = _structures[p.structure]
		var pos: Vector3i = p.position
		var size: Vector3i = struct.size
		result.append({
			"position": pos,
			"blocks": struct.blocks,
			"size_x": size.x,
			"size_y": size.y,
			"size_z": size.z,
			"aabb_min_x": pos.x,
			"aabb_min_y": pos.y,
			"aabb_min_z": pos.z,
			"aabb_max_x": pos.x + size.x - 1,
			"aabb_max_y": pos.y + size.y - 1,
			"aabb_max_z": pos.z + size.z - 1,
		})
	return result

# ============================================================
# UTILITAIRES
# ============================================================

func get_structure_names() -> Array:
	return _structures.keys()

func get_placement_count() -> int:
	return _placements.size()

func has_structures() -> bool:
	return _structures.size() > 0
