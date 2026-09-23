extends CanvasLayer
## Small native turn-based battle slice using source Pokémon sprites and stats.

var world: Node
var species := "wurmple"
var enemy_level := 2
var player_level := 5
var player_hp := 20
var player_max_hp := 20
var enemy_hp := 12
var enemy_max_hp := 12
var stats: Dictionary
var state := "intro"
var root_control: Control
var design_root: Control
var enemy_bar: ProgressBar
var player_bar: ProgressBar
var enemy_status: Label
var player_status: Label
var message_label: Label

func begin(field: Node, wild_species: String, wild_level: int, starter_level: int, starter_hp: int) -> void:
	world = field
	species = wild_species
	enemy_level = wild_level
	player_level = starter_level
	stats = field.get("pokemon_stats")
	player_hp = starter_hp
	player_max_hp = _max_hp("mudkip", player_level)
	enemy_hp = _max_hp(species, enemy_level)
	enemy_max_hp = enemy_hp
	_build_screen()
	message_label.text = "A wild %s appeared!\n(Press Z to continue)" % species.capitalize()

func _max_hp(mon: String, level: int) -> int:
	return floori((2.0 * stats[mon]["hp"] * level) / 100.0) + level + 10

func _build_screen() -> void:
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)
	design_root = Control.new()
	design_root.size = Vector2(320, 180)
	design_root.scale = Vector2(6, 6)
	root_control.add_child(design_root)
	var backdrop := ColorRect.new()
	backdrop.color = Color("a7cfb8")
	backdrop.size = Vector2(320, 180)
	design_root.add_child(backdrop)
	var distant_ground := ColorRect.new()
	distant_ground.position = Vector2(0, 70)
	distant_ground.size = Vector2(320, 62)
	distant_ground.color = Color("c3d49b")
	design_root.add_child(distant_ground)
	var near_ground := ColorRect.new()
	near_ground.position = Vector2(0, 112)
	near_ground.size = Vector2(320, 20)
	near_ground.color = Color("89b775")
	design_root.add_child(near_ground)
	_add_battle_panel(Rect2(8, 8, 145, 38))
	_add_battle_panel(Rect2(165, 82, 147, 42))
	var enemy_name := _add_label(design_root, species.capitalize() + "  Lv." + str(enemy_level), Vector2(16, 13), Vector2(128, 13), 9)
	enemy_bar = _add_bar(Vector2(18, 31), Vector2(124, 8))
	var player_name := _add_label(design_root, "MUDKIP  Lv." + str(player_level), Vector2(173, 87), Vector2(130, 13), 9)
	player_bar = _add_bar(Vector2(175, 103), Vector2(128, 8))
	enemy_status = _add_label(design_root, "", Vector2(215, 56), Vector2(94, 12), 8)
	player_status = _add_label(design_root, "", Vector2(225, 113), Vector2(77, 10), 7)
	var enemy_sprite := TextureRect.new()
	enemy_sprite.texture = load("res://assets/pokemon/%s_front.png" % species)
	enemy_sprite.position = Vector2(216, 13)
	enemy_sprite.size = Vector2(82, 76)
	enemy_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	enemy_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	design_root.add_child(enemy_sprite)
	var player_sprite := TextureRect.new()
	player_sprite.texture = preload("res://assets/pokemon/mudkip_back.png")
	player_sprite.position = Vector2(32, 64)
	player_sprite.size = Vector2(105, 68)
	player_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	design_root.add_child(player_sprite)
	_add_battle_panel(Rect2(8, 132, 304, 40))
	message_label = _add_label(design_root, "", Vector2(16, 137), Vector2(288, 31), 9)
	_refresh_bars()

func _add_battle_panel(rect: Rect2) -> void:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f7f3df")
	style.border_color = Color("393748")
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	design_root.add_child(panel)

func _add_label(parent: Control, text: String, pos: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = label_size
	label.add_theme_color_override("font_color", Color("292632"))
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _add_bar(pos: Vector2, bar_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.size = bar_size
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 100
	var background := StyleBoxFlat.new()
	background.bg_color = Color("d0d1c6")
	background.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("55a75a")
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	design_root.add_child(bar)
	return bar

func _refresh_bars() -> void:
	enemy_bar.value = 100.0 * enemy_hp / enemy_max_hp
	player_bar.value = 100.0 * player_hp / player_max_hp
	enemy_status.text = "%d / %d HP" % [enemy_hp, enemy_max_hp]
	player_status.text = "%d / %d HP" % [player_hp, player_max_hp]

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var confirm := key.keycode == KEY_Z or key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER
	var run := key.keycode == KEY_X or key.keycode == KEY_ESCAPE
	if state == "menu":
		if confirm:
			_player_attack()
		elif run:
			message_label.text = "You got away safely.\n(Press Z to continue)"
			state = "run"
	elif confirm:
		if state == "intro":
			state = "menu"
			message_label.text = "What will Mudkip do?\nZ: TACKLE    X: RUN"
		elif state == "player_action":
			if enemy_hp <= 0:
				message_label.text = "The wild %s fainted!\n(Press Z to continue)" % species.capitalize()
				state = "win"
			else:
				_enemy_attack()
		elif state == "enemy_action":
			if player_hp <= 0:
				message_label.text = "Mudkip fainted!\n(Press Z to continue)"
				state = "lose"
			else:
				state = "menu"
				message_label.text = "What will Mudkip do?\nZ: TACKLE    X: RUN"
		elif state == "win" or state == "lose" or state == "run":
			_finish(state)

func _player_attack() -> void:
	var damage := _damage("mudkip", player_level, species, enemy_level)
	enemy_hp = maxi(0, enemy_hp - damage)
	_refresh_bars()
	message_label.text = "Mudkip used Tackle!\n(Press Z to continue)"
	state = "player_action"

func _enemy_attack() -> void:
	var damage := _damage(species, enemy_level, "mudkip", player_level)
	player_hp = maxi(0, player_hp - damage)
	_refresh_bars()
	message_label.text = "Wild %s used Tackle!\n(Press Z to continue)" % species.capitalize()
	state = "enemy_action"

func _damage(attacker: String, attacker_level: int, defender: String, defender_level: int) -> int:
	var attack: float = stats[attacker]["attack"]
	var defense: float = maxf(1.0, stats[defender]["defense"])
	var raw := (((2.0 * attacker_level / 5.0 + 2.0) * 40.0 * attack / defense) / 50.0) + 2.0
	return maxi(1, floori(raw * randf_range(0.85, 1.0)))

func _finish(result: String) -> void:
	world.call("battle_finished", result, player_hp)
	queue_free()
