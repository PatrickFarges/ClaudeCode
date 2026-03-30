extends RefCounted
class_name NodeUtils
## Utilitaires partagés pour la recherche récursive de noeuds dans un arbre de scène.

static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found = find_skeleton(child)
		if found: return found
	return null

static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found = find_animation_player(child)
		if found: return found
	return null
