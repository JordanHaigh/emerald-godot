extends CharacterBody2D

const TILE := 16.0
const STEP_SPEED := 96.0
const FRAME_TIME := 0.08
# The flattened 3×3 sheet is grouped by facing: idle, stride A, stride B.
const DIRECTION_FRAMES := [
	[0, 3, 4], # down
	[1, 5, 6], # up
	[2, 7, 8], # side
]

var world: Node
var facing := Vector2.DOWN
var animation_clock := 0.0
var walk_frame := 0
var step_target := Vector2.ZERO
var stepping := false

func _ready() -> void:
	step_target = position

func _physics_process(delta: float) -> void:
	if world.input_lock:
		world.input_lock = false
		return
	if world.talking or world.battle_active:
		if Input.is_action_just_pressed("interact"):
			world.close_dialogue()
		return
	if stepping:
		position = position.move_toward(step_target, STEP_SPEED * delta)
		_update_sprite(delta, true)
		if position.distance_squared_to(step_target) < 0.01:
			position = step_target
			stepping = false
			world.on_enter_tile(position)
		return

	var direction := _pressed_direction()
	if direction != Vector2.ZERO:
		facing = direction
		var candidate := position + direction * TILE
		if not _can_step_to(candidate):
			_update_sprite(delta, false)
			return
		step_target = candidate
		stepping = true
		_update_sprite(delta, true)
	elif Input.is_action_just_pressed("interact"):
		world.interact(position, facing)
		_update_sprite(delta, false)
	else:
		_update_sprite(delta, false)

func _pressed_direction() -> Vector2:
	if Input.is_action_pressed("move_left"):
		return Vector2.LEFT
	if Input.is_action_pressed("move_right"):
		return Vector2.RIGHT
	if Input.is_action_pressed("move_up"):
		return Vector2.UP
	if Input.is_action_pressed("move_down"):
		return Vector2.DOWN
	return Vector2.ZERO

func _can_step_to(target: Vector2) -> bool:
	return not (
		world.is_solid(target + Vector2(0, 4))
		or world.is_solid(target + Vector2(-4, 4))
		or world.is_solid(target + Vector2(4, 4))
	)

func _update_sprite(delta: float, moving: bool) -> void:
	var sprite: Sprite2D = $Sprite
	var direction_frame := 0
	if facing == Vector2.DOWN:
		direction_frame = 0
	elif facing == Vector2.UP:
		direction_frame = 1
	else:
		direction_frame = 2
	if moving:
		animation_clock += delta
		if animation_clock >= FRAME_TIME:
			animation_clock = 0.0
			walk_frame = (walk_frame + 1) % 3
	else:
		walk_frame = 0
		animation_clock = 0.0
	sprite.flip_h = facing == Vector2.RIGHT
	# Keep every animation phase within the selected facing direction.
	var animation_frame: int = DIRECTION_FRAMES[direction_frame][walk_frame]
	sprite.region_rect = Rect2(animation_frame * 16, 0, 16, 32)
