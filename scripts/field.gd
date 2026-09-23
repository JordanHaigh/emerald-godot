extends Node2D
## Connected Hoenn field maps, imported from the source decompilation.

const TILE := 16
const WORLD_MAPS := [
	{"name": "Route103", "x": 30, "y": 0},
	{"name": "OldaleTown", "x": 30, "y": 22},
	{"name": "Route101", "x": 30, "y": 42},
	{"name": "LittlerootTown", "x": 30, "y": 62},
]
const WORLD_WIDTH := 110
const WORLD_HEIGHT := 82
const ZOOM_LEVELS: Array[float] = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 6.0]
const ACTOR_ROOT := "res://assets/people/"

var map_info: Dictionary
var encounter_regions: Array[Dictionary] = []
var player: CharacterBody2D
var camera: Camera2D
var zoom_index := 8
var dialogue: CanvasLayer
var debug_zoom_label: Label
var talking := false
var battle_active := false
var input_lock := false
var world_art: Node2D
var map_base_art: Node2D
var sorted_art: Node2D
var map_foreground_art: Node2D
var object_events: Array[Dictionary] = []
var pokemon_stats: Dictionary
var mudkip_level := 5
var mudkip_hp := 20

func _ready() -> void:
	y_sort_enabled = true
	pokemon_stats = JSON.parse_string(FileAccess.get_file_as_string("res://assets/pokemon/base_stats.json"))
	world_art = Node2D.new()
	world_art.name = "MapAndPeople"
	add_child(world_art)
	map_base_art = Node2D.new()
	map_base_art.name = "MapBase"
	world_art.add_child(map_base_art)
	sorted_art = Node2D.new()
	sorted_art.name = "DepthSortedForegroundAndPeople"
	sorted_art.y_sort_enabled = true
	world_art.add_child(sorted_art)
	map_foreground_art = Node2D.new()
	map_foreground_art.name = "MapForegroundOverPeople"
	map_foreground_art.z_as_relative = false
	map_foreground_art.z_index = 10
	world_art.add_child(map_foreground_art)
	_load_world()
	_build_player()
	dialogue = get_node("Dialogue")
	dialogue.hide_message()
	_build_debug_panel()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("zoom_in"):
		_set_zoom(zoom_index + 1)
	elif Input.is_action_just_pressed("zoom_out"):
		_set_zoom(zoom_index - 1)

func _set_zoom(level: int) -> void:
	zoom_index = clampi(level, 0, ZOOM_LEVELS.size() - 1)
	if is_instance_valid(camera):
		camera.zoom = Vector2.ONE * ZOOM_LEVELS[zoom_index]
	if is_instance_valid(debug_zoom_label):
		debug_zoom_label.text = "DEBUG  |  ZOOM %.2fx" % ZOOM_LEVELS[zoom_index]

func _build_debug_panel() -> void:
	var overlay := CanvasLayer.new()
	overlay.name = "DebugOverlay"
	overlay.layer = 2
	add_child(overlay)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(root)
	var panel := Panel.new()
	panel.position = Vector2(16, 16)
	panel.size = Vector2(190, 40)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.15, 0.82)
	style.border_color = Color("a8c58a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	debug_zoom_label = Label.new()
	debug_zoom_label.position = Vector2(8, 3)
	debug_zoom_label.size = Vector2(174, 34)
	debug_zoom_label.add_theme_color_override("font_color", Color("f5f0d9"))
	debug_zoom_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(debug_zoom_label)
	_set_zoom(zoom_index)

func _load_world() -> void:
	object_events.clear()
	encounter_regions.clear()
	var combined_collision := PackedInt32Array()
	combined_collision.resize(WORLD_WIDTH * WORLD_HEIGHT)
	combined_collision.fill(1)
	var combined_terrain := PackedInt32Array()
	combined_terrain.resize(WORLD_WIDTH * WORLD_HEIGHT)
	combined_terrain.fill(0)
	var forest_ground := Sprite2D.new()
	forest_ground.name = "ForestGround"
	forest_ground.texture = load("res://assets/maps/ForestGround.png")
	forest_ground.position = Vector2.ZERO
	forest_ground.centered = false
	forest_ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Keep the grass behind both map layers and all Y-sorted sprites. Using an
	# absolute low Z avoids transparent art revealing the viewport clear color.
	forest_ground.z_as_relative = false
	forest_ground.z_index = -100
	map_base_art.add_child(forest_ground)
	var forest_trees := Sprite2D.new()
	forest_trees.name = "ForestTrees"
	forest_trees.texture = load("res://assets/maps/ForestTrees.png")
	forest_trees.position = Vector2(0, 22 * TILE)
	forest_trees.centered = false
	forest_trees.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_base_art.add_child(forest_trees)
	for region in WORLD_MAPS:
		var map_name: String = region["name"]
		var offset := Vector2i(int(region["x"]), int(region["y"]))
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/%s.json" % map_name))
		var map_sprite := Sprite2D.new()
		map_sprite.name = map_name
		map_sprite.texture = load("res://assets/maps/%s_Layer0.png" % map_name)
		map_sprite.centered = false
		map_sprite.position = Vector2(offset * TILE)
		map_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		map_base_art.add_child(map_sprite)
		var map_width: int = data["width"]
		var map_height: int = data["height"]
		var foreground := Sprite2D.new()
		foreground.name = "%s_Foreground" % map_name
		foreground.texture = load("res://assets/maps/%s_Layer1.png" % map_name)
		foreground.position = Vector2(offset * TILE)
		foreground.centered = false
		foreground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		map_foreground_art.add_child(foreground)
		for y in range(int(data["height"])):
			for x in range(map_width):
				var source_index := y * map_width + x
				var target_index := (y + offset.y) * WORLD_WIDTH + x + offset.x
				combined_collision[target_index] = int(data["collision"][source_index])
				combined_terrain[target_index] = int(data["terrain"][source_index])
		encounter_regions.append({
			"rect": Rect2i(offset.x, offset.y, map_width, int(data["height"])),
			"wild_mons": data["wild_mons"],
		})
		for event in data["object_events"]:
			var graphics_id: String = event["graphics_id"]
			var sprite_path := ACTOR_ROOT + graphics_id.trim_prefix("OBJ_EVENT_GFX_").to_lower() + ".png"
			if not ResourceLoader.exists(sprite_path):
				continue
			var actor := Node2D.new()
			actor.name = graphics_id
			actor.position = Vector2((int(event["x"]) + offset.x + 0.5) * TILE, (int(event["y"]) + offset.y + 0.5) * TILE)
			actor.set_script(preload("res://scripts/npc.gd"))
			actor.set("world", self)
			actor.set("graphics_id", graphics_id)
			actor.set("movement_type", String(event["movement_type"]))
			actor.set("home_cell", Vector2i(int(event["x"]) + offset.x, int(event["y"]) + offset.y))
			actor.set("movement_range", Vector2i(int(event.get("movement_range_x", 0)), int(event.get("movement_range_y", 0))))
			var sprite := Sprite2D.new()
			sprite.texture = load(sprite_path)
			sprite.region_enabled = true
			sprite.region_rect = Rect2(_facing_frame(String(event["movement_type"])) * 16, 0, 16, 32)
			sprite.position.y = -8
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			actor.add_child(sprite)
			actor.set("actor_sprite", sprite)
			var actor_record := {
				"position": actor.position,
				"graphics_id": graphics_id,
				"dialogue": event.get("dialogue", ""),
				"actor": actor,
			}
			actor.set("event_record", actor_record)
			sorted_art.add_child(actor)
			object_events.append(actor_record)
		for event in data.get("bg_events", []):
			if event.get("type", "") != "sign":
				continue
			object_events.append({
				"position": Vector2((int(event["x"]) + offset.x + 0.5) * TILE, (int(event["y"]) + offset.y + 0.5) * TILE),
				"graphics_id": "SIGN",
				"dialogue": event.get("dialogue", "")
			})
	map_info = {"width": WORLD_WIDTH, "height": WORLD_HEIGHT, "collision": combined_collision, "terrain": combined_terrain}
	if is_instance_valid(camera):
		camera.limit_right = WORLD_WIDTH * TILE
		camera.limit_bottom = WORLD_HEIGHT * TILE
		camera.reset_smoothing()

func _facing_frame(movement_type: String) -> int:
	if movement_type.ends_with("UP"):
		return 1
	if movement_type.ends_with("LEFT") or movement_type.ends_with("RIGHT"):
		return 2
	return 0

func _build_player() -> void:
	player = CharacterBody2D.new()
	player.name = "Player"
	player.set_script(preload("res://scripts/player.gd"))
	player.position = _starting_position()
	sorted_art.add_child(player)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = preload("res://assets/people/brendan_walking.png")
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 16, 32)
	sprite.position.y = -8
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	player.add_child(sprite)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(9, 8)
	collider.shape = shape
	collider.position = Vector2(0, 4)
	player.add_child(collider)
	player.set("world", self)
	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(map_info["width"]) * TILE
	camera.limit_bottom = int(map_info["height"]) * TILE
	camera.zoom = Vector2.ONE * ZOOM_LEVELS[zoom_index]
	player.add_child(camera)

func _starting_position() -> Vector2:
	return Vector2(42.5 * TILE, 73.5 * TILE)

func is_solid(world_position: Vector2) -> bool:
	var tile_x := floori(world_position.x / TILE)
	var tile_y := floori(world_position.y / TILE)
	var width: int = map_info["width"]
	var height: int = map_info["height"]
	if tile_x < 0 or tile_y < 0 or tile_x >= width or tile_y >= height:
		return true
	var index := tile_y * width + tile_x
	if int(map_info["collision"][index]) != 0:
		return true
	for event in object_events:
		if world_position.distance_to(event["position"]) < 10.0:
			return true
	return false

func npc_can_step(actor: Node2D, target: Vector2) -> bool:
	if is_solid(target):
		return false
	if is_instance_valid(player) and cell_for(target) == cell_for(player.position):
		return false
	return true

func cell_for(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / TILE), floori(world_position.y / TILE))

func on_enter_tile(world_position: Vector2) -> void:
	var cell := cell_for(world_position)
	var width: int = map_info["width"]
	var index := cell.y * width + cell.x
	if int(map_info["terrain"][index]) != 2:
		return
	var wild_mons: Array = []
	for region in encounter_regions:
		if region["rect"].has_point(cell):
			wild_mons = region["wild_mons"]
			break
	if wild_mons.is_empty():
		return
	if randf() >= 0.16:
		return
	var weighted_total := 0
	for mon in wild_mons:
		weighted_total += int(mon["weight"])
	var selection := randi_range(1, weighted_total)
	for mon in wild_mons:
		selection -= int(mon["weight"])
		if selection <= 0:
			var level := randi_range(int(mon["min_level"]), int(mon["max_level"]))
			begin_wild_battle(String(mon["species"]), level)
			return

func begin_wild_battle(species: String, level: int) -> void:
	if battle_active:
		return
	battle_active = true
	var battle := CanvasLayer.new()
	battle.name = "WildBattle"
	battle.set_script(preload("res://scripts/battle.gd"))
	add_child(battle)
	battle.call("begin", self, species, level, mudkip_level, mudkip_hp)

func battle_finished(result: String, remaining_hp: int) -> void:
	battle_active = false
	input_lock = true
	var maximum_hp := floori((2.0 * pokemon_stats["mudkip"]["hp"] * mudkip_level) / 100.0) + mudkip_level + 10
	mudkip_hp = remaining_hp if remaining_hp > 0 else maximum_hp
	if result == "win":
		mudkip_hp = mini(maximum_hp, mudkip_hp + 3)

func interact(origin: Vector2, facing: Vector2) -> void:
	var target := origin + facing * TILE
	for event in object_events:
		if target.distance_to(event["position"]) <= 12.0:
			var line: String = event["dialogue"]
			if line.is_empty():
				line = "There is nothing to read here."
			talking = true
			dialogue.show_message(line)
			return
	talking = true
	dialogue.show_message("There is nothing to interact with.")

func close_dialogue() -> void:
	talking = false
	dialogue.hide_message()
