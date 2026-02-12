extends CanvasLayer

# Crosshair (mire au centre de l'écran)

func _ready():
	# Conteneur centré
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center_container)
	
	# Container pour la croix
	var crosshair_container = Control.new()
	crosshair_container.custom_minimum_size = Vector2(20, 20)
	center_container.add_child(crosshair_container)
	
	# Ligne horizontale gauche
	var h_left = ColorRect.new()
	h_left.color = Color.WHITE
	h_left.size = Vector2(6, 2)
	h_left.position = Vector2(2, 9)
	crosshair_container.add_child(h_left)
	
	# Ligne horizontale droite
	var h_right = ColorRect.new()
	h_right.color = Color.WHITE
	h_right.size = Vector2(6, 2)
	h_right.position = Vector2(12, 9)
	crosshair_container.add_child(h_right)
	
	# Ligne verticale haut
	var v_top = ColorRect.new()
	v_top.color = Color.WHITE
	v_top.size = Vector2(2, 6)
	v_top.position = Vector2(9, 2)
	crosshair_container.add_child(v_top)
	
	# Ligne verticale bas
	var v_bottom = ColorRect.new()
	v_bottom.color = Color.WHITE
	v_bottom.size = Vector2(2, 6)
	v_bottom.position = Vector2(9, 12)
	crosshair_container.add_child(v_bottom)
	
	# Outline noir pour le contraste
	# Ligne horizontale gauche (outline)
	var h_left_outline = ColorRect.new()
	h_left_outline.color = Color(0, 0, 0, 0.5)
	h_left_outline.size = Vector2(8, 4)
	h_left_outline.position = Vector2(1, 8)
	h_left_outline.z_index = -1
	crosshair_container.add_child(h_left_outline)
	
	# Ligne horizontale droite (outline)
	var h_right_outline = ColorRect.new()
	h_right_outline.color = Color(0, 0, 0, 0.5)
	h_right_outline.size = Vector2(8, 4)
	h_right_outline.position = Vector2(11, 8)
	h_right_outline.z_index = -1
	crosshair_container.add_child(h_right_outline)
	
	# Ligne verticale haut (outline)
	var v_top_outline = ColorRect.new()
	v_top_outline.color = Color(0, 0, 0, 0.5)
	v_top_outline.size = Vector2(4, 8)
	v_top_outline.position = Vector2(8, 1)
	v_top_outline.z_index = -1
	crosshair_container.add_child(v_top_outline)
	
	# Ligne verticale bas (outline)
	var v_bottom_outline = ColorRect.new()
	v_bottom_outline.color = Color(0, 0, 0, 0.5)
	v_bottom_outline.size = Vector2(4, 8)
	v_bottom_outline.position = Vector2(8, 11)
	v_bottom_outline.z_index = -1
	crosshair_container.add_child(v_bottom_outline)
