extends Node2D
## Small, source-movement-type-driven NPC controller for loaded map events.

const TILE := 16.0
const WALK_SPEED := 60.0 # Source normal movement advances one pixel per GBA frame.
const FRAME_TIME := 0.09
const DIRECTION_FRAMES := [
	[0, 3, 4], # down
	[1, 5, 6], # up
	[2, 7, 8], # side
]
const DIRECTIONS := [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]
const NON_CHARACTER_GRAPHICS := [
	"OBJ_EVENT_GFX_TRUCK", "OBJ_EVENT_GFX_BIRCHS_BAG", "OBJ_EVENT_GFX_BERRY_TREE",
	"OBJ_EVENT_GFX_ITEM_BALL", "OBJ_EVENT_GFX_CUTTABLE_TREE",
]

var world: Node
var actor_sprite: Sprite2D
var event_record: Dictionary
var graphics_id := ""
var movement_type := ""
var home_cell := Vector2i.ZERO
var movement_range := Vector2i.ZERO
var facing := Vector2.DOWN
var walk_frame := 0
var animation_clock := 0.0
var wait_clock := 0.0
var step_target := Vector2.ZERO
var moving := false
var walk_sequence_direction := Vector2.ZERO
var random := RandomNumberGenerator.new()

func _ready() -> void:
	random.randomize()
	facing = _initial_facing()
	if movement_type.begins_with("MOVEMENT_TYPE_WANDER_") or movement_type.begins_with("MOVEMENT_TYPE_WALK_"):
		# The source engine promotes zero ranges to one for movement types with bounds.
		movement_range.x = maxi(1, movement_range.x)
		movement_range.y = maxi(1, movement_range.y)
	step_target = position
	if movement_type in ["MOVEMENT_TYPE_WALK_UP_AND_DOWN", "MOVEMENT_TYPE_WALK_DOWN_AND_UP"]:
		walk_sequence_direction = facing
	elif _is_jog_in_place():
		wait_clock = 0.0
	else:
		wait_clock = _random_medium_delay()
	_update_sprite(false)

func _process(delta: float) -> void:
	if world == null or not is_instance_valid(actor_sprite):
		return
	if world.battle_active:
		_update_sprite(false)
		return
	if moving:
		position = position.move_toward(step_target, WALK_SPEED * delta)
		_update_sprite(true, delta)
		if position.distance_squared_to(step_target) < 0.01:
			position = step_target
			moving = false
			event_record["position"] = position
			_complete_step()
		return
	if _is_jog_in_place():
		_update_sprite(true, delta)
		return
	if not _is_mobile_character():
		_update_sprite(false)
		return
	wait_clock -= delta
	if wait_clock > 0.0:
		_update_sprite(false)
		return
	if movement_type == "MOVEMENT_TYPE_LOOK_AROUND":
		facing = DIRECTIONS[random.randi_range(0, DIRECTIONS.size() - 1)]
		wait_clock = _random_medium_delay()
		_update_sprite(false)
		return
	if movement_type == "MOVEMENT_TYPE_WANDER_AROUND":
		_try_random_step(DIRECTIONS)
	elif movement_type in ["MOVEMENT_TYPE_WANDER_LEFT_AND_RIGHT", "MOVEMENT_TYPE_WANDER_RIGHT_AND_LEFT"]:
		_try_random_step([Vector2.LEFT, Vector2.RIGHT])
	elif movement_type in ["MOVEMENT_TYPE_WANDER_UP_AND_DOWN", "MOVEMENT_TYPE_WANDER_DOWN_AND_UP"]:
		_try_random_step([Vector2.UP, Vector2.DOWN])
	elif movement_type in ["MOVEMENT_TYPE_WALK_UP_AND_DOWN", "MOVEMENT_TYPE_WALK_DOWN_AND_UP"]:
		_try_back_and_forth_step()
	else:
		wait_clock = _random_medium_delay()
		_update_sprite(false)

func _try_random_step(directions: Array) -> void:
	var direction: Vector2 = directions[random.randi_range(0, directions.size() - 1)]
	facing = direction
	if _can_move(direction):
		_begin_step(direction)
		return
	wait_clock = _random_medium_delay()
	_update_sprite(false)

func _try_back_and_forth_step() -> void:
	var direction := walk_sequence_direction
	var destination_cell: Vector2i = world.cell_for(position + direction * TILE)
	var outside_range: bool = abs(destination_cell.x - home_cell.x) > movement_range.x or abs(destination_cell.y - home_cell.y) > movement_range.y
	if outside_range:
		direction = -direction
		walk_sequence_direction = direction
	if _can_move(direction):
		_begin_step(direction)
	else:
		wait_clock = 0.25
		_update_sprite(false)

func _can_move(direction: Vector2) -> bool:
	var destination := position + direction * TILE
	var destination_cell: Vector2i = world.cell_for(destination)
	if abs(destination_cell.x - home_cell.x) > movement_range.x:
		return false
	if abs(destination_cell.y - home_cell.y) > movement_range.y:
		return false
	return world.npc_can_step(self, destination)

func _begin_step(direction: Vector2) -> void:
	facing = direction
	step_target = position + direction * TILE
	moving = true
	_update_sprite(true, 0.0)

func _complete_step() -> void:
	if movement_type in ["MOVEMENT_TYPE_WALK_UP_AND_DOWN", "MOVEMENT_TYPE_WALK_DOWN_AND_UP"]:
		var home_position := Vector2((home_cell.x + 0.5) * TILE, (home_cell.y + 0.5) * TILE)
		if position.distance_squared_to(home_position) < 0.01:
			walk_sequence_direction = -walk_sequence_direction
	else:
		wait_clock = _random_medium_delay()
	_update_sprite(false)

func _initial_facing() -> Vector2:
	if movement_type in ["MOVEMENT_TYPE_WALK_UP_AND_DOWN", "MOVEMENT_TYPE_WANDER_UP_AND_DOWN", "MOVEMENT_TYPE_JOG_IN_PLACE_UP", "MOVEMENT_TYPE_FACE_UP", "MOVEMENT_TYPE_FACE_UP_AND_LEFT", "MOVEMENT_TYPE_FACE_UP_AND_RIGHT", "MOVEMENT_TYPE_FACE_UP_LEFT_AND_RIGHT"]:
		return Vector2.UP
	if movement_type in ["MOVEMENT_TYPE_WALK_DOWN_AND_UP", "MOVEMENT_TYPE_WANDER_DOWN_AND_UP", "MOVEMENT_TYPE_JOG_IN_PLACE_DOWN", "MOVEMENT_TYPE_FACE_DOWN", "MOVEMENT_TYPE_FACE_DOWN_AND_UP", "MOVEMENT_TYPE_FACE_DOWN_AND_LEFT", "MOVEMENT_TYPE_FACE_DOWN_AND_RIGHT", "MOVEMENT_TYPE_FACE_DOWN_UP_AND_LEFT", "MOVEMENT_TYPE_FACE_DOWN_UP_AND_RIGHT", "MOVEMENT_TYPE_FACE_DOWN_LEFT_AND_RIGHT"]:
		return Vector2.DOWN
	if movement_type in ["MOVEMENT_TYPE_WANDER_LEFT_AND_RIGHT", "MOVEMENT_TYPE_WALK_LEFT_AND_RIGHT", "MOVEMENT_TYPE_JOG_IN_PLACE_LEFT", "MOVEMENT_TYPE_FACE_LEFT", "MOVEMENT_TYPE_FACE_LEFT_AND_RIGHT"]:
		return Vector2.LEFT
	if movement_type in ["MOVEMENT_TYPE_WANDER_RIGHT_AND_LEFT", "MOVEMENT_TYPE_WALK_RIGHT_AND_LEFT", "MOVEMENT_TYPE_JOG_IN_PLACE_RIGHT", "MOVEMENT_TYPE_FACE_RIGHT"]:
		return Vector2.RIGHT
	return Vector2.DOWN

func _is_jog_in_place() -> bool:
	return movement_type.begins_with("MOVEMENT_TYPE_JOG_IN_PLACE") and not (graphics_id in NON_CHARACTER_GRAPHICS)

func _is_mobile_character() -> bool:
	if graphics_id in NON_CHARACTER_GRAPHICS:
		return false
	return movement_type in [
		"MOVEMENT_TYPE_LOOK_AROUND", "MOVEMENT_TYPE_WANDER_AROUND",
		"MOVEMENT_TYPE_WANDER_UP_AND_DOWN", "MOVEMENT_TYPE_WANDER_DOWN_AND_UP",
		"MOVEMENT_TYPE_WANDER_LEFT_AND_RIGHT", "MOVEMENT_TYPE_WANDER_RIGHT_AND_LEFT",
		"MOVEMENT_TYPE_WALK_UP_AND_DOWN", "MOVEMENT_TYPE_WALK_DOWN_AND_UP",
	]

func _random_medium_delay() -> float:
	# Source uses delays of 32, 64, 96, or 128 frames at 60 Hz.
	return float(random.randi_range(1, 4) * 32) / 60.0

func _update_sprite(is_moving: bool, delta: float = 0.0) -> void:
	if not is_instance_valid(actor_sprite):
		return
	if is_moving:
		animation_clock += delta
		if animation_clock >= FRAME_TIME:
			animation_clock = fmod(animation_clock, FRAME_TIME)
			walk_frame = (walk_frame + 1) % 3
	else:
		walk_frame = 0
		animation_clock = 0.0
	var direction_index := 0
	if facing == Vector2.UP:
		direction_index = 1
	elif facing == Vector2.LEFT or facing == Vector2.RIGHT:
		direction_index = 2
	actor_sprite.flip_h = facing == Vector2.RIGHT
	var frame: int = DIRECTION_FRAMES[direction_index][walk_frame]
	actor_sprite.region_rect = Rect2(frame * 16, 0, 16, 32)
