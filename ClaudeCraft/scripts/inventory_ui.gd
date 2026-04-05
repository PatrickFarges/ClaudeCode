# inventory_ui.gd v3.5.0
# Inventaire MC drag & drop + grille craft 2x2
# Rangee du bas = hotbar (reference, pas de stockage)
# Rangees du haut = inventaire reel (27 slots, pagine)
# Meme comportement que crafting_ui.gd

extends CanvasLayer

const GC = preload("res://scripts/game_config.gd")
const GUI_DIR = "res://TexturesPack/Faithful32/assets/minecraft/textures/gui/"
const GUI_SCALE = 2
const MAX_STACK = 64

var player: CharacterBody3D = null
var is_open: bool = false
var _icon_cache: Dictionary = {}

var _inv_slots_data: Array = []
var _inv_page: int = 0
const INV_SLOTS_PER_PAGE = 27

var _grid_contents: Array = []
var _held_item: Dictionary = {}
var _held_source: String = ""
var _held_hotbar_idx: int = -1
var _matched_recipe: Dictionary = {}
var _available_recipes: Array = []

var _background: ColorRect = null
var _inv_texture: TextureRect = null
var _title_label: Label = null
var _grid_ui: Array = []
var _output_btn: Button = null
var _output_tex: TextureRect = null
var _output_count_lbl: Label = null
var _inv_ui: Array = []
var _hotbar_ui: Array = []
var _cursor_tex: TextureRect = null
var _cursor_count: Label = null
var _hover_name_label: Label = null
var _hint_label: Label = null
var _page_label: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null

# Steve preview + armor slots
var _preview_dragging: bool = false
var _steve_viewport: SubViewport = null
var _steve_model: Node3D = null
var _steve_skeleton: Skeleton3D = null
var _steve_preview_rect: TextureRect = null
var _armor_slot_icons: Array = []  # 4 TextureRect pour icônes placeholder
const SLOT_DIR = "res://TexturesPack/Faithful32/assets/minecraft/textures/gui/sprites/container/slot/"
const STEVE_GLB = "res://assets/PlayerModel/steve.glb"
const STEVE_SKIN = "res://assets/PlayerModel/steve_skin.png"
# Coords texture inventaire (en pixels texture 352x332)
const ARMOR_SLOTS_X = 15; const ARMOR_SLOTS = [15, 51, 87, 123]  # Y de chaque slot
const PREVIEW_X = 52; const PREVIEW_Y = 16; const PREVIEW_W = 98; const PREVIEW_H = 140
const OFFHAND_X = 153; const OFFHAND_Y = 123
static var _steve_packed: PackedScene = null

# Recipe book
var _recipe_book: Control = null
var _recipe_book_btn: Button = null
const RB_DIR = GUI_DIR + "sprites/recipe_book/"

const TEX_W = 352
const TEX_H = 332
const CRAFT_2X2_X = 196
const CRAFT_2X2_Y = 36
const CRAFT_STEP = 36
const OUT_X = 306
const OUT_Y = 56
const INV_X = 14
const INV_Y = 166
const HOTBAR_Y = 282
const SLOT_SZ = 36
const GRID_SIZE = 4

func _ready():
	layer = 10; visible = false
	_grid_contents.resize(GRID_SIZE)
	for i in range(GRID_SIZE): _grid_contents[i] = {}
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	_available_recipes = []
	for recipe in CraftRegistry.get_all_recipes():
		if recipe.has("_tool_tier") or recipe.get("output_count", 0) <= 0: continue
		if CraftRegistry.is_recipe_available(recipe, 0, false):
			_available_recipes.append(recipe)
	_build_ui()

func _build_ui():
	var disp_w = TEX_W * GUI_SCALE; var disp_h = TEX_H * GUI_SCALE
	var tex_left = -disp_w / 2.0; var tex_top = -disp_h / 2.0
	var icon_sz = 28 * GUI_SCALE; var slot_px = SLOT_SZ * GUI_SCALE; var pad = (slot_px - icon_sz) / 2.0

	_background = ColorRect.new(); _background.color = Color(0, 0, 0, 0.65)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_background.gui_input.connect(_on_bg_input); add_child(_background)

	var inv_img = Image.load_from_file(GUI_DIR + "container/inventory.png")
	var inv_tex: ImageTexture = null
	if inv_img: inv_tex = ImageTexture.create_from_image(inv_img.get_region(Rect2i(0, 0, TEX_W, TEX_H)))
	_inv_texture = TextureRect.new(); _inv_texture.texture = inv_tex
	_inv_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_inv_texture.set_anchors_preset(Control.PRESET_CENTER)
	_inv_texture.offset_left = tex_left; _inv_texture.offset_right = -tex_left
	_inv_texture.offset_top = tex_top; _inv_texture.offset_bottom = -tex_top
	_inv_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_inv_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_inv_texture)

	# --- Steve 3D preview dans le rectangle noir ---
	_setup_steve_preview(tex_left, tex_top)
	# --- Icônes placeholder dans les 4 slots armure + offhand ---
	_setup_armor_slot_icons(tex_left, tex_top)

	_title_label = _make_label("Inventaire", 20, Color(1, 1, 0.9), true)
	_title_label.set_anchors_preset(Control.PRESET_CENTER)
	_title_label.offset_left = -150; _title_label.offset_right = 150
	_title_label.offset_top = tex_top - 30; _title_label.offset_bottom = tex_top - 4
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_title_label)

	# Grille craft 2x2
	for r in range(2):
		for c in range(2):
			var idx = r * 2 + c
			var sx = tex_left + (CRAFT_2X2_X + c * CRAFT_STEP) * GUI_SCALE
			var sy = tex_top + (CRAFT_2X2_Y + r * CRAFT_STEP) * GUI_SCALE
			var d = _make_slot(sx, sy, slot_px, icon_sz, pad)
			d["btn"].gui_input.connect(_on_grid_input.bind(idx))
			d["btn"].mouse_entered.connect(_on_grid_hover.bind(idx))
			d["btn"].mouse_exited.connect(_on_hover_exit); _grid_ui.append(d)

	# Output
	var ox = tex_left + OUT_X * GUI_SCALE; var oy = tex_top + OUT_Y * GUI_SCALE
	_output_btn = Button.new(); _output_btn.flat = true
	_output_btn.set_anchors_preset(Control.PRESET_CENTER)
	_output_btn.offset_left = ox; _output_btn.offset_right = ox + slot_px
	_output_btn.offset_top = oy; _output_btn.offset_bottom = oy + slot_px
	_output_btn.gui_input.connect(_on_output_input)
	_output_btn.mouse_entered.connect(_on_output_hover)
	_output_btn.mouse_exited.connect(_on_hover_exit); add_child(_output_btn)
	_output_tex = _make_tex_rect(ox + pad, oy + pad, icon_sz); add_child(_output_tex)
	_output_count_lbl = _make_count_label(ox, oy, slot_px); add_child(_output_count_lbl)

	# 27 slots inventaire
	for row in range(3):
		for col in range(9):
			var sx = tex_left + (INV_X + col * SLOT_SZ) * GUI_SCALE
			var sy = tex_top + (INV_Y + row * SLOT_SZ) * GUI_SCALE
			var d = _make_inv_slot(sx, sy, slot_px, icon_sz, pad)
			d["btn"].gui_input.connect(_on_inv_input.bind(_inv_ui.size()))
			d["btn"].mouse_entered.connect(_on_inv_hover.bind(_inv_ui.size()))
			d["btn"].mouse_exited.connect(_on_hover_exit); _inv_ui.append(d)

	# 9 slots hotbar
	for col in range(9):
		var sx = tex_left + (INV_X + col * SLOT_SZ) * GUI_SCALE
		var sy = tex_top + HOTBAR_Y * GUI_SCALE
		var d = _make_inv_slot(sx, sy, slot_px, icon_sz, pad)
		d["btn"].gui_input.connect(_on_hotbar_input.bind(col))
		d["btn"].mouse_entered.connect(_on_hotbar_hover.bind(col))
		d["btn"].mouse_exited.connect(_on_hover_exit); _hotbar_ui.append(d)

	# Pagination
	var nav_y = disp_h / 2 + 10
	var bs = StyleBoxFlat.new(); bs.bg_color = Color(0.2, 0.15, 0.3, 0.85)
	bs.border_color = Color(0.5, 0.3, 0.7, 0.9); bs.set_border_width_all(2); bs.set_corner_radius_all(4)
	_prev_btn = Button.new(); _prev_btn.text = "< Prec."
	_prev_btn.set_anchors_preset(Control.PRESET_CENTER)
	_prev_btn.offset_left = -120; _prev_btn.offset_right = -30
	_prev_btn.offset_top = nav_y; _prev_btn.offset_bottom = nav_y + 30
	_prev_btn.add_theme_stylebox_override("normal", bs)
	_prev_btn.add_theme_color_override("font_color", Color.WHITE)
	_prev_btn.pressed.connect(_on_prev_page); add_child(_prev_btn)
	_page_label = _make_label("1/1", 14, Color(1, 1, 0.9))
	_page_label.set_anchors_preset(Control.PRESET_CENTER)
	_page_label.offset_left = -30; _page_label.offset_right = 30
	_page_label.offset_top = nav_y + 4; _page_label.offset_bottom = nav_y + 30
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_page_label)
	_next_btn = Button.new(); _next_btn.text = "Suiv. >"
	_next_btn.set_anchors_preset(Control.PRESET_CENTER)
	_next_btn.offset_left = 30; _next_btn.offset_right = 120
	_next_btn.offset_top = nav_y; _next_btn.offset_bottom = nav_y + 30
	_next_btn.add_theme_stylebox_override("normal", bs)
	_next_btn.add_theme_color_override("font_color", Color.WHITE)
	_next_btn.pressed.connect(_on_next_page); add_child(_next_btn)

	# Label nom de l'objet survolé (fixe, centré entre grille et inventaire)
	_hover_name_label = Label.new(); _hover_name_label.set_anchors_preset(Control.PRESET_CENTER)
	_hover_name_label.add_theme_font_size_override("font_size", 15)
	_hover_name_label.add_theme_color_override("font_color", Color.WHITE)
	_hover_name_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 1))
	_hover_name_label.add_theme_constant_override("shadow_offset_x", 2)
	_hover_name_label.add_theme_constant_override("shadow_offset_y", 2)
	_hover_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_name_label.offset_left = tex_left + 155 * GUI_SCALE; _hover_name_label.offset_right = -tex_left
	_hover_name_label.offset_top = tex_top + 148 * GUI_SCALE; _hover_name_label.offset_bottom = tex_top + 165 * GUI_SCALE
	_hover_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; _hover_name_label.visible = false
	add_child(_hover_name_label)

	_hint_label = _make_label("", 13, Color(0.8, 0.8, 0.7, 0.8), true)
	_hint_label.set_anchors_preset(Control.PRESET_CENTER)
	_hint_label.offset_left = -disp_w / 2; _hint_label.offset_right = disp_w / 2
	_hint_label.offset_top = disp_h / 2 + 6; _hint_label.offset_bottom = disp_h / 2 + 24
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_hint_label)

	# --- Recipe book toggle button ---
	var rb_btn_img = Image.load_from_file(RB_DIR + "button.png")
	if rb_btn_img:
		var rb_icon_tex = ImageTexture.create_from_image(rb_btn_img)
		# Bouton livre vert — coin supérieur droit du panneau, sur le cadre
		var rb_w = 20 * GUI_SCALE  # taille affichée
		var rb_h = 18 * GUI_SCALE
		# Position en haut à droite du panneau (dans la bordure)
		var rb_x = tex_left + (TEX_W - 24) * GUI_SCALE
		var rb_y = tex_top + 3 * GUI_SCALE
		_recipe_book_btn = Button.new()
		_recipe_book_btn.set_anchors_preset(Control.PRESET_CENTER)
		_recipe_book_btn.offset_left = rb_x; _recipe_book_btn.offset_right = rb_x + rb_w
		_recipe_book_btn.offset_top = rb_y; _recipe_book_btn.offset_bottom = rb_y + rb_h
		_recipe_book_btn.icon = rb_icon_tex
		_recipe_book_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_recipe_book_btn.expand_icon = true
		_recipe_book_btn.flat = true
		_recipe_book_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_recipe_book_btn.pressed.connect(_on_recipe_book_toggle)
		add_child(_recipe_book_btn)

	# --- Recipe book panel (hidden by default) ---
	var RecipeBookUI = load("res://scripts/recipe_book_ui.gd")
	_recipe_book = RecipeBookUI.new()
	_recipe_book.set_anchors_preset(Control.PRESET_CENTER)
	# Position to the left of the inventory panel
	var rb_panel_w = 294 * GUI_SCALE  # PANEL_ATLAS_W * GUI_SCALE
	_recipe_book.offset_left = tex_left - rb_panel_w - 4
	_recipe_book.offset_right = tex_left - 4
	_recipe_book.offset_top = tex_top
	_recipe_book.offset_bottom = tex_top + 332 * GUI_SCALE
	add_child(_recipe_book)

	_cursor_tex = TextureRect.new(); _cursor_tex.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cursor_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cursor_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cursor_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE; _cursor_tex.visible = false
	_cursor_tex.z_index = 200; _cursor_tex.top_level = true
	add_child(_cursor_tex)
	_cursor_count = Label.new(); _cursor_count.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cursor_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cursor_count.add_theme_font_size_override("font_size", 14)
	_cursor_count.add_theme_color_override("font_color", Color.WHITE)
	_cursor_count.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
	_cursor_count.add_theme_constant_override("shadow_offset_x", 2)
	_cursor_count.add_theme_constant_override("shadow_offset_y", 2)
	_cursor_count.mouse_filter = Control.MOUSE_FILTER_IGNORE; _cursor_count.visible = false
	_cursor_count.z_index = 200; _cursor_count.top_level = true
	add_child(_cursor_count)

# ============================================================
# STEVE PREVIEW + ARMOR SLOTS
# ============================================================
func _setup_steve_preview(tex_left: float, tex_top: float):
	# SubViewport pour rendre Steve en 3D
	_steve_viewport = SubViewport.new()
	_steve_viewport.size = Vector2i(PREVIEW_W * GUI_SCALE, PREVIEW_H * GUI_SCALE)
	_steve_viewport.transparent_bg = true
	_steve_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_steve_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_steve_viewport)
	# Lumières
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, -45, 0)
	light.light_energy = 1.2
	_steve_viewport.add_child(light)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 135, 0)
	fill.light_energy = 0.4
	_steve_viewport.add_child(fill)
	# Caméra
	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.2
	cam.position = Vector3(0, 1.12, 3)
	cam.rotation_degrees = Vector3(0, 0, 0)
	cam.current = true
	_steve_viewport.add_child(cam)
	# Charger Steve
	if not _steve_packed:
		_steve_packed = load(STEVE_GLB) as PackedScene
	if _steve_packed:
		_steve_model = _steve_packed.instantiate()
		_steve_model.scale = Vector3(1, 1, 1)
		_steve_model.rotation_degrees = Vector3(0, -160, 0)
		_steve_viewport.add_child(_steve_model)
		_apply_preview_skin()
		_steve_skeleton = NodeUtils.find_skeleton(_steve_model)
		# Appliquer l'armure du joueur
		_refresh_preview_armor()
		# Jouer idle
		var anim = NodeUtils.find_animation_player(_steve_model)
		if anim and anim.has_animation("idle"):
			anim.play("idle")
	# TextureRect pour afficher le rendu
	_steve_preview_rect = TextureRect.new()
	_steve_preview_rect.set_anchors_preset(Control.PRESET_CENTER)
	_steve_preview_rect.offset_left = tex_left + PREVIEW_X * GUI_SCALE
	_steve_preview_rect.offset_right = tex_left + (PREVIEW_X + PREVIEW_W) * GUI_SCALE
	_steve_preview_rect.offset_top = tex_top + PREVIEW_Y * GUI_SCALE
	_steve_preview_rect.offset_bottom = tex_top + (PREVIEW_Y + PREVIEW_H) * GUI_SCALE
	_steve_preview_rect.texture = _steve_viewport.get_texture()
	_steve_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_steve_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_steve_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_steve_preview_rect)
	# Zone cliquable pour rotation souris
	var drag_area = Button.new(); drag_area.flat = true
	drag_area.set_anchors_preset(Control.PRESET_CENTER)
	drag_area.offset_left = _steve_preview_rect.offset_left
	drag_area.offset_right = _steve_preview_rect.offset_right
	drag_area.offset_top = _steve_preview_rect.offset_top
	drag_area.offset_bottom = _steve_preview_rect.offset_bottom
	drag_area.gui_input.connect(_on_preview_input)
	add_child(drag_area)

func _setup_armor_slot_icons(tex_left: float, tex_top: float):
	var slot_names = ["helmet", "chestplate", "leggings", "boots"]
	var slot_px = SLOT_SZ * GUI_SCALE
	var icon_inner = 28 * GUI_SCALE
	var pad = (slot_px - icon_inner) / 2.0
	for i in range(4):
		var sx = tex_left + ARMOR_SLOTS_X * GUI_SCALE + pad
		var sy = tex_top + ARMOR_SLOTS[i] * GUI_SCALE + pad
		var tr = TextureRect.new()
		tr.set_anchors_preset(Control.PRESET_CENTER)
		tr.offset_left = sx; tr.offset_right = sx + icon_inner
		tr.offset_top = sy; tr.offset_bottom = sy + icon_inner
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate = Color(1, 1, 1, 0.4)
		# Charger l'icône placeholder
		var img = Image.new()
		if img.load(SLOT_DIR + slot_names[i] + ".png") == OK:
			tr.texture = ImageTexture.create_from_image(img)
		add_child(tr)
		_armor_slot_icons.append(tr)
	# Slot offhand (bouclier)
	var osx = tex_left + OFFHAND_X * GUI_SCALE + pad
	var osy = tex_top + OFFHAND_Y * GUI_SCALE + pad
	var otr = TextureRect.new()
	otr.set_anchors_preset(Control.PRESET_CENTER)
	otr.offset_left = osx; otr.offset_right = osx + icon_inner
	otr.offset_top = osy; otr.offset_bottom = osy + icon_inner
	otr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	otr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	otr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	otr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	otr.modulate = Color(1, 1, 1, 0.4)
	var shield_img = Image.new()
	if shield_img.load(SLOT_DIR + "shield.png") == OK:
		otr.texture = ImageTexture.create_from_image(shield_img)
	add_child(otr)

func _apply_preview_skin():
	if not _steve_model: return
	var img = Image.new()
	if img.load(STEVE_SKIN) != OK: return
	var tex = ImageTexture.create_from_image(img)
	_apply_skin_recursive_preview(_steve_model, tex)

func _apply_skin_recursive_preview(node: Node, tex: Texture2D):
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				var base_mat = mi.mesh.surface_get_material(i)
				if base_mat is StandardMaterial3D:
					var mat = base_mat.duplicate() as StandardMaterial3D
					mat.albedo_texture = tex
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_skin_recursive_preview(child, tex)

func _refresh_preview_armor():
	if not _steve_skeleton or not player: return
	var ArmorMgr = load("res://scripts/armor_manager.gd")
	if not ArmorMgr: return
	ArmorMgr.unequip_all(_steve_skeleton)
	for piece in ["helmet", "chestplate", "leggings", "boots"]:
		if player.equipped_armor.has(piece) and not player.equipped_armor[piece].is_empty():
			ArmorMgr.equip(_steve_skeleton, piece, player.equipped_armor[piece])

func _on_preview_input(event: InputEvent):
	if event is InputEventMouseButton:
		_preview_dragging = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventMouseMotion and _preview_dragging and _steve_model:
		_steve_model.rotation_degrees.y -= event.relative.x * 0.8

# ============================================================
# HELPERS
# ============================================================
func _make_label(text, size, color, shadow = false) -> Label:
	var l = Label.new(); l.text = text; l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0.15, 0.15, 0.15, 1))
		l.add_theme_constant_override("shadow_offset_x", 2); l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; return l

func _make_tex_rect(x, y, sz) -> TextureRect:
	var t = TextureRect.new(); t.set_anchors_preset(Control.PRESET_CENTER)
	t.offset_left = x; t.offset_right = x + sz; t.offset_top = y; t.offset_bottom = y + sz
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; t.mouse_filter = Control.MOUSE_FILTER_IGNORE; return t

func _make_count_label(sx, sy, slot_px) -> Label:
	var l = Label.new(); l.set_anchors_preset(Control.PRESET_CENTER)
	l.offset_left = sx + slot_px - 26 * GUI_SCALE; l.offset_right = sx + slot_px - 2
	l.offset_top = sy + slot_px - 14 * GUI_SCALE; l.offset_bottom = sy + slot_px
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0.2, 0.2, 0.2, 1))
	l.add_theme_constant_override("shadow_offset_x", 2); l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; return l

func _make_slot(sx, sy, slot_px, icon_sz, pad) -> Dictionary:
	var b = Button.new(); b.flat = true; b.set_anchors_preset(Control.PRESET_CENTER)
	b.offset_left = sx; b.offset_right = sx + slot_px; b.offset_top = sy; b.offset_bottom = sy + slot_px
	var hs = StyleBoxFlat.new(); hs.bg_color = Color(1, 1, 1, 0.12); b.add_theme_stylebox_override("hover", hs)
	add_child(b); var t = _make_tex_rect(sx + pad, sy + pad, icon_sz); add_child(t)
	var c = _make_count_label(sx, sy, slot_px); add_child(c)
	return {"btn": b, "tex": t, "count_lbl": c}

func _make_inv_slot(sx, sy, slot_px, icon_sz, pad) -> Dictionary:
	return _make_slot(sx, sy, slot_px, icon_sz, pad)

# ============================================================
# OPEN / CLOSE
# ============================================================
func open_inventory():
	is_open = true; _inv_page = 0; _held_item = {}; _held_source = ""
	for i in range(GRID_SIZE): _grid_contents[i] = {}
	_matched_recipe = {}
	_refresh_preview_armor()
	_build_inv_slots(); visible = true; _refresh_all()
	set_process(true)
	if _steve_viewport:
		_steve_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Restaurer l'état du recipe book (ouvert/fermé depuis la dernière fois)
	if _recipe_book:
		var RecipeBookUI = load("res://scripts/recipe_book_ui.gd")
		if RecipeBookUI._was_open:
			_recipe_book.setup(player, 0, false, self, Callable(self, "_on_recipe_book_craft"))
			_recipe_book.visible = true
		else:
			_recipe_book.visible = false

func close_inventory():
	# Mémoriser l'état du recipe book avant de fermer
	if _recipe_book:
		var RecipeBookUI = load("res://scripts/recipe_book_ui.gd")
		RecipeBookUI._was_open = _recipe_book.visible
		_recipe_book.visible = false
	_return_items_to_inventory(); is_open = false; visible = false
	set_process(false)
	if _steve_viewport:
		_steve_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _on_recipe_book_toggle():
	if _recipe_book:
		if not _recipe_book.visible:
			_recipe_book.setup(player, 0, false, self, Callable(self, "_on_recipe_book_craft"))
		_recipe_book.toggle()

func _on_recipe_book_craft():
	_build_inv_slots()
	_refresh_all()

# ============================================================
# SLOT DATA
# ============================================================
func _build_inv_slots():
	_inv_slots_data.clear()
	if not player: return
	var inv = player.get_all_inventory(); var st: Array = []
	for bt in inv:
		if inv[bt] > 0: st.append(bt)
	st.sort_custom(func(a, b): return int(a) < int(b))
	for bt in st: _inv_slots_data.append({"block_type": bt, "count": inv[bt]})
	# Outils
	var tools = player.get_all_tools()
	for tt in tools:
		if tools[tt] > 0:
			_inv_slots_data.append({"is_tool": true, "tool_type": tt, "count": tools[tt]})
	var ms = maxi(INV_SLOTS_PER_PAGE, _inv_slots_data.size() + INV_SLOTS_PER_PAGE)
	while _inv_slots_data.size() < ms: _inv_slots_data.append({})

func _add_to_inv_slot_and_dict(bt, count):
	player._add_to_inventory(bt, count)
	for i in range(_inv_slots_data.size()):
		if not _inv_slots_data[i].is_empty() and not _inv_slots_data[i].get("is_tool", false) and _inv_slots_data[i].get("block_type") == bt:
			_inv_slots_data[i]["count"] += count; return
	for i in range(_inv_slots_data.size()):
		if _inv_slots_data[i].is_empty():
			_inv_slots_data[i] = {"block_type": bt, "count": count}; return
	_inv_slots_data.append({"block_type": bt, "count": count})

func _same_inv_type(a: Dictionary, b: Dictionary) -> bool:
	if a.get("is_tool", false) != b.get("is_tool", false): return false
	if a.get("is_tool", false): return a.get("tool_type") == b.get("tool_type")
	return a.get("block_type") == b.get("block_type")

func _dict_add_held():
	if _held_item.get("is_tool", false):
		player.tool_inventory[_held_item["tool_type"]] = player.tool_inventory.get(_held_item["tool_type"], 0) + _held_item.get("count", 1)
	else:
		player._add_to_inventory(_held_item["block_type"], _held_item["count"])

func _dict_remove_slot(slot: Dictionary):
	if slot.get("is_tool", false):
		player.tool_inventory[slot["tool_type"]] = maxi(0, player.tool_inventory.get(slot["tool_type"], 0) - slot.get("count", 1))
	else:
		player._remove_from_inventory(slot["block_type"], slot["count"])

func sort_inventory(): _build_inv_slots(); _inv_page = 0; _refresh_all()

# ============================================================
# REFRESH
# ============================================================
func _refresh_all():
	_refresh_inv_slots(); _refresh_hotbar_slots(); _refresh_grid_visuals()
	_check_recipe(); _update_output(); _update_cursor(); _update_pagination()

func _refresh_inv_slots():
	var offset = _inv_page * INV_SLOTS_PER_PAGE
	for i in range(_inv_ui.size()):
		var ui = _inv_ui[i]; var idx = offset + i
		if idx < _inv_slots_data.size() and not _inv_slots_data[idx].is_empty():
			var item = _inv_slots_data[idx]
			if item.get("is_tool", false):
				ui["tex"].texture = _load_tool_icon(item["tool_type"])
			else:
				ui["tex"].texture = _load_block_icon(item["block_type"])
			ui["tex"].modulate = Color.WHITE
			ui["count_lbl"].text = str(item["count"]) if item["count"] > 1 else ""
		else:
			ui["tex"].texture = null; ui["count_lbl"].text = ""
		ui["btn"].visible = true

func _refresh_hotbar_slots():
	if not player: return
	for i in range(9):
		var ui = _hotbar_ui[i]
		var tt = player.hotbar_tool_slots[i] if i < player.hotbar_tool_slots.size() else ToolRegistry.ToolType.NONE
		if tt != ToolRegistry.ToolType.NONE:
			ui["tex"].texture = _load_tool_icon(tt); ui["tex"].modulate = Color.WHITE
			ui["count_lbl"].text = ""
		else:
			var bt = player.hotbar_slots[i] if i < player.hotbar_slots.size() else 0
			var count = player.get_inventory_count(bt)
			if count > 0:
				ui["tex"].texture = _load_block_icon(bt); ui["tex"].modulate = Color.WHITE
				ui["count_lbl"].text = str(count) if count > 1 else ""
			else:
				ui["tex"].texture = null; ui["count_lbl"].text = ""
		ui["btn"].visible = true

func _refresh_grid_visuals():
	for i in range(GRID_SIZE):
		var cell = _grid_contents[i]; var ui = _grid_ui[i]
		if not cell.is_empty():
			ui["tex"].texture = _load_block_icon(cell["block_type"]); ui["tex"].modulate = Color.WHITE
			ui["count_lbl"].text = str(cell["count"]) if cell["count"] > 1 else ""
		else: ui["tex"].texture = null; ui["count_lbl"].text = ""

func _update_output():
	if not _matched_recipe.is_empty():
		_output_tex.texture = _load_block_icon(_matched_recipe["output_type"]); _output_tex.modulate = Color.WHITE
		var oc = _matched_recipe.get("output_count", 1)
		_output_count_lbl.text = "x%d" % oc if oc > 1 else ""
		_hint_label.text = _matched_recipe.get("name", "")
		_hint_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 0.9))
	else:
		_output_tex.texture = null; _output_count_lbl.text = ""
		var hi = false
		for cell in _grid_contents:
			if not cell.is_empty(): hi = true; break
		if hi:
			_hint_label.text = "Aucune recette ne correspond"
			_hint_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5, 0.9))
		else:
			_hint_label.text = ""
			_hint_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7, 0.8))

func _update_cursor():
	if not _held_item.is_empty():
		if _held_item.get("is_tool", false):
			_cursor_tex.texture = _load_tool_icon(_held_item["tool_type"])
		else:
			_cursor_tex.texture = _load_block_icon(_held_item["block_type"])
		_cursor_tex.visible = true
		var c = _held_item.get("count", 0)
		_cursor_count.text = str(c) if c > 1 else ""; _cursor_count.visible = c > 1
	else: _cursor_tex.visible = false; _cursor_count.visible = false

func _update_pagination():
	var total = maxi(1, ceili(float(_inv_slots_data.size()) / INV_SLOTS_PER_PAGE))
	if _page_label: _page_label.text = "%d/%d" % [_inv_page + 1, total]
	if _prev_btn: _prev_btn.visible = total > 1; _prev_btn.disabled = _inv_page <= 0
	if _next_btn: _next_btn.visible = total > 1; _next_btn.disabled = _inv_page >= total - 1

# ============================================================
# INPUT — INVENTORY
# ============================================================
func _on_inv_input(event: InputEvent, index: int):
	if not (event is InputEventMouseButton and event.pressed): return
	var slot_idx = _inv_page * INV_SLOTS_PER_PAGE + index
	while slot_idx >= _inv_slots_data.size(): _inv_slots_data.append({})
	var slot = _inv_slots_data[slot_idx]

	if event.button_index == MOUSE_BUTTON_LEFT:
		if _held_item.is_empty():
			if not slot.is_empty():
				_held_item = slot.duplicate(); _held_source = "inv"
				_dict_remove_slot(slot)
				_inv_slots_data[slot_idx] = {}; _refresh_all()
		else:
			if _held_source == "hotbar": _restore_hotbar_held(); _refresh_all(); return
			if slot.is_empty():
				_inv_slots_data[slot_idx] = _held_item.duplicate()
				_dict_add_held()
				_held_item = {}; _held_source = ""; _refresh_all()
			elif _same_inv_type(slot, _held_item):
				slot["count"] = slot.get("count", 1) + _held_item.get("count", 1)
				_dict_add_held()
				_held_item = {}; _held_source = ""; _refresh_all()
			else:
				var temp = slot.duplicate()
				_inv_slots_data[slot_idx] = _held_item.duplicate()
				_dict_add_held()
				_dict_remove_slot(temp)
				_held_item = temp; _held_source = "inv"; _refresh_all()

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if not _held_item.is_empty() and not _held_item.get("is_tool", false) and _held_source != "hotbar":
			if slot.is_empty():
				_inv_slots_data[slot_idx] = {"block_type": _held_item["block_type"], "count": 1}
				player._add_to_inventory(_held_item["block_type"], 1)
				_held_item["count"] -= 1
				if _held_item["count"] <= 0: _held_item = {}; _held_source = ""
				_refresh_all()
			elif not slot.get("is_tool", false) and slot.get("block_type") == _held_item.get("block_type"):
				slot["count"] += 1; player._add_to_inventory(_held_item["block_type"], 1)
				_held_item["count"] -= 1
				if _held_item["count"] <= 0: _held_item = {}; _held_source = ""
				_refresh_all()
		elif _held_item.is_empty() and not slot.is_empty() and not slot.get("is_tool", false):
			var take = ceili(slot["count"] / 2.0)
			_held_item = {"is_tool": false, "block_type": slot["block_type"], "count": take}
			_held_source = "inv"; player._remove_from_inventory(slot["block_type"], take)
			slot["count"] -= take
			if slot["count"] <= 0: _inv_slots_data[slot_idx] = {}
			_refresh_all()

# ============================================================
# INPUT — HOTBAR
# ============================================================
func _on_hotbar_input(event: InputEvent, col: int):
	if not (event is InputEventMouseButton and event.pressed): return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _held_item.is_empty():
			# Prendre depuis hotbar = juste retirer le pointeur (l'item reste dans l'inventaire)
			if not player.is_hotbar_slot_empty(col):
				var tt = player.hotbar_tool_slots[col] if col < player.hotbar_tool_slots.size() else ToolRegistry.ToolType.NONE
				if tt != ToolRegistry.ToolType.NONE:
					_held_item = {"is_tool": true, "tool_type": tt, "count": 0}
				else:
					_held_item = {"is_tool": false, "block_type": player.hotbar_slots[col], "count": 0}
				_held_source = "hotbar"; _held_hotbar_idx = col
				player._clear_hotbar_slot(col); _refresh_all()
		else:
			if _held_source == "hotbar":
				# Déplacer un pointeur hotbar vers un autre slot hotbar
				if _held_item.get("is_tool", false):
					player.assign_hotbar_tool(col, _held_item["tool_type"])
				else:
					player.assign_hotbar_slot(col, _held_item["block_type"])
				_held_item = {}; _held_source = ""; _held_hotbar_idx = -1; _refresh_all()
			elif _held_source == "inv" or _held_source == "grid":
				# Poser depuis inventaire sur hotbar = créer un pointeur, remettre l'item dans l'inventaire
				if _held_item.get("is_tool", false):
					player.assign_hotbar_tool(col, _held_item["tool_type"])
				else:
					player.assign_hotbar_slot(col, _held_item["block_type"])
				# Remettre l'item dans l'inventaire (il avait été retiré quand on l'a pris)
				_dict_add_held()
				# Remettre aussi dans _inv_slots_data pour la vue
				if _held_item.get("is_tool", false):
					_readd_to_inv_slots(_held_item)
				else:
					_readd_to_inv_slots(_held_item)
				_held_item = {}; _held_source = ""; _refresh_all()

func _readd_to_inv_slots(item: Dictionary):
	# Remettre un item dans _inv_slots_data (fusionner si même type existe)
	for i in range(_inv_slots_data.size()):
		if _same_inv_type(_inv_slots_data[i], item):
			_inv_slots_data[i]["count"] = _inv_slots_data[i].get("count", 1) + item.get("count", 1)
			return
	for i in range(_inv_slots_data.size()):
		if _inv_slots_data[i].is_empty():
			_inv_slots_data[i] = item.duplicate(); return
	_inv_slots_data.append(item.duplicate())

func _restore_hotbar_held():
	# Remettre l'item sur son slot hotbar d'origine (annulation)
	if _held_hotbar_idx >= 0:
		if _held_item.get("is_tool", false):
			player.assign_hotbar_tool(_held_hotbar_idx, _held_item["tool_type"])
		else:
			player.assign_hotbar_slot(_held_hotbar_idx, _held_item["block_type"])
	_held_item = {}; _held_source = ""; _held_hotbar_idx = -1

# ============================================================
# INPUT — GRID 2x2
# ============================================================
func _on_grid_input(event: InputEvent, index: int):
	if not (event is InputEventMouseButton and event.pressed): return
	var cell = _grid_contents[index]
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _held_item.is_empty():
			if not cell.is_empty():
				_held_item = cell.duplicate(); _held_item["is_tool"] = false; _held_source = "grid"
				_grid_contents[index] = {}; _refresh_all()
		else:
			if _held_item.get("is_tool", false) or _held_source == "hotbar":
				if _held_source == "hotbar": _restore_hotbar_held()
				_refresh_all(); return
			if cell.is_empty():
				_grid_contents[index] = {"block_type": _held_item["block_type"], "count": _held_item["count"]}
				_held_item = {}; _held_source = ""; _refresh_all()
			elif cell["block_type"] == _held_item["block_type"]:
				cell["count"] += _held_item["count"]; _held_item = {}; _held_source = ""; _refresh_all()
			else:
				var temp = cell.duplicate()
				_grid_contents[index] = {"block_type": _held_item["block_type"], "count": _held_item["count"]}
				_held_item = temp; _held_item["is_tool"] = false; _held_source = "grid"; _refresh_all()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if not _held_item.is_empty() and not _held_item.get("is_tool", false) and _held_source != "hotbar":
			if cell.is_empty():
				_grid_contents[index] = {"block_type": _held_item["block_type"], "count": 1}
				_held_item["count"] -= 1
				if _held_item["count"] <= 0: _held_item = {}; _held_source = ""
				_refresh_all()
			elif cell["block_type"] == _held_item["block_type"]:
				cell["count"] += 1; _held_item["count"] -= 1
				if _held_item["count"] <= 0: _held_item = {}; _held_source = ""
				_refresh_all()
		elif _held_item.is_empty() and not cell.is_empty():
			var take = ceili(cell["count"] / 2.0)
			_held_item = {"is_tool": false, "block_type": cell["block_type"], "count": take}
			_held_source = "grid"; cell["count"] -= take
			if cell["count"] <= 0: _grid_contents[index] = {}
			_refresh_all()

func _on_output_input(event: InputEvent):
	if not (event is InputEventMouseButton and event.pressed): return
	if event.button_index != MOUSE_BUTTON_LEFT or _matched_recipe.is_empty() or not player: return
	_consume_grid_for_recipe(_matched_recipe)
	_add_to_inv_slot_and_dict(_matched_recipe["output_type"], _matched_recipe["output_count"])
	var audio = get_tree().get_first_node_in_group("audio_manager")
	if audio and audio.has_method("play_craft_success"): audio.play_craft_success()
	_refresh_all()

func _on_bg_input(event: InputEvent):
	if not (event is InputEventMouseButton and event.pressed): return
	if event.button_index != MOUSE_BUTTON_LEFT or _held_item.is_empty(): return
	if _held_source == "hotbar":
		# Drop hotbar dans le vide = supprimer le pointeur (l'item reste dans l'inventaire)
		_held_item = {}; _held_source = ""; _held_hotbar_idx = -1; _refresh_all()
	else:
		# Drop inventaire dans le vide = remettre l'item dans l'inventaire
		if _held_item.get("is_tool", false):
			_dict_add_held()
		else:
			_add_to_inv_slot_and_dict(_held_item["block_type"], _held_item["count"])
		_held_item = {}; _held_source = ""; _refresh_all()

func _on_prev_page():
	if _inv_page > 0: _inv_page -= 1; _refresh_inv_slots(); _update_pagination()
func _on_next_page():
	var total = maxi(1, ceili(float(_inv_slots_data.size()) / INV_SLOTS_PER_PAGE))
	if _inv_page < total - 1: _inv_page += 1; _refresh_inv_slots(); _update_pagination()

# ============================================================
# RECIPE
# ============================================================
func _check_recipe():
	var gt: Dictionary = {}
	for cell in _grid_contents:
		if not cell.is_empty(): var bt = cell["block_type"]; gt[bt] = gt.get(bt, 0) + cell["count"]
	if gt.is_empty(): _matched_recipe = {}; return
	var best: Dictionary = {}; var bs: int = 0
	for recipe in _available_recipes:
		var inputs = recipe.get("inputs", []); var ok = true; var sc = 0
		for inp in inputs:
			if gt.get(inp[0], 0) < inp[1]: ok = false; break
			sc += inp[1]
		if ok and sc > bs: best = recipe; bs = sc
	_matched_recipe = best

func _consume_grid_for_recipe(recipe):
	var req: Dictionary = {}
	for inp in recipe["inputs"]: req[inp[0]] = req.get(inp[0], 0) + inp[1]
	for bt in req:
		var rem = req[bt]
		for i in range(GRID_SIZE):
			if rem <= 0: break
			if _grid_contents[i].is_empty() or _grid_contents[i]["block_type"] != bt: continue
			var take = mini(rem, _grid_contents[i]["count"])
			_grid_contents[i]["count"] -= take; rem -= take
			if _grid_contents[i]["count"] <= 0: _grid_contents[i] = {}

func _return_items_to_inventory():
	if not player: return
	if not _held_item.is_empty():
		if _held_source == "hotbar":
			# Fermeture avec item hotbar en main = remettre le pointeur
			_restore_hotbar_held()
		elif _held_item.get("is_tool", false):
			_dict_add_held()
		else:
			_add_to_inv_slot_and_dict(_held_item["block_type"], _held_item["count"])
		_held_item = {}; _held_source = ""
	for i in range(GRID_SIZE):
		if not _grid_contents[i].is_empty():
			_add_to_inv_slot_and_dict(_grid_contents[i]["block_type"], _grid_contents[i]["count"])
			_grid_contents[i] = {}

# ============================================================
# HOVER
# ============================================================
func _set_hover_name(text: String):
	if _hover_name_label:
		_hover_name_label.text = text; _hover_name_label.visible = not text.is_empty()

func _on_inv_hover(index):
	var si = _inv_page * INV_SLOTS_PER_PAGE + index
	if si < _inv_slots_data.size() and not _inv_slots_data[si].is_empty():
		var item = _inv_slots_data[si]
		if item.get("is_tool", false):
			_set_hover_name(ToolRegistry.get_tool_name(item["tool_type"]))
		else:
			_set_hover_name(BlockRegistry.get_block_name(item["block_type"]))
	else: _set_hover_name("")

func _on_hotbar_hover(col):
	if not player: return
	var tt = player.hotbar_tool_slots[col] if col < player.hotbar_tool_slots.size() else ToolRegistry.ToolType.NONE
	if tt != ToolRegistry.ToolType.NONE:
		_set_hover_name(ToolRegistry.get_tool_name(tt))
	elif not player.is_hotbar_slot_empty(col):
		var bt = player.hotbar_slots[col]
		_set_hover_name(BlockRegistry.get_block_name(bt))
	else: _set_hover_name("")

func _on_grid_hover(index):
	if index < GRID_SIZE and not _grid_contents[index].is_empty():
		var cell = _grid_contents[index]
		_set_hover_name(BlockRegistry.get_block_name(cell["block_type"]))
	else: _set_hover_name("")

func _on_output_hover():
	if not _matched_recipe.is_empty():
		_set_hover_name(BlockRegistry.get_block_name(_matched_recipe["output_type"]))
	else: _set_hover_name("")

func _on_hover_exit():
	_set_hover_name("")

# ============================================================
# PROCESS
# ============================================================
func _process(_delta):
	if not is_open: return
	var m = get_viewport().get_mouse_position()
	if _cursor_tex and _cursor_tex.visible:
		var sz = 28 * GUI_SCALE
		_cursor_tex.offset_left = m.x - sz / 2; _cursor_tex.offset_top = m.y - sz / 2
		_cursor_tex.offset_right = m.x + sz / 2; _cursor_tex.offset_bottom = m.y + sz / 2
		if _cursor_count and _cursor_count.visible:
			_cursor_count.offset_left = m.x + sz / 2 - 24; _cursor_count.offset_top = m.y + sz / 2 - 16
			_cursor_count.offset_right = m.x + sz / 2 + 12; _cursor_count.offset_bottom = m.y + sz / 2 + 4

# ============================================================
# ICON LOADING
# ============================================================
func _load_block_icon(block_type) -> ImageTexture:
	var k = "block_" + str(block_type)
	if _icon_cache.has(k): return _icon_cache[k]
	var tn = BlockRegistry.get_face_texture(block_type, "top")
	if tn == "dirt" and block_type != BlockRegistry.BlockType.DIRT:
		tn = BlockRegistry.get_face_texture(block_type, "all")
	var ap = GC.resolve_block_texture(tn)
	if ap.is_empty(): _icon_cache[k] = null; return null
	var img = Image.new()
	if img.load(ap) != OK: _icon_cache[k] = null; return null
	img.convert(Image.FORMAT_RGBA8)
	var tint = BlockRegistry.get_block_tint(block_type, "top")
	if tint != Color(1, 1, 1, 1):
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c = img.get_pixel(x, y)
				img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	var tex = ImageTexture.create_from_image(img); _icon_cache[k] = tex; return tex

func _load_tool_icon(tool_type) -> ImageTexture:
	var k = "tool_" + str(tool_type)
	if _icon_cache.has(k): return _icon_cache[k]
	var tp = ToolRegistry.get_item_texture_path(tool_type)
	if tp.is_empty(): _icon_cache[k] = null; return null
	var ap = ProjectSettings.globalize_path(tp)
	if not FileAccess.file_exists(ap): _icon_cache[k] = null; return null
	var img = Image.new()
	if img.load(ap) != OK: _icon_cache[k] = null; return null
	img.convert(Image.FORMAT_RGBA8)
	var tex = ImageTexture.create_from_image(img); _icon_cache[k] = tex; return tex
