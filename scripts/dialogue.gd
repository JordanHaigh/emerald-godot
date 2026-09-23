extends CanvasLayer

const SCREEN_SIZE := Vector2(240, 160)
const FRAME_POSITION := Vector2(0, 112)

var frame: TextureRect
var label: Label
var prompt_arrow: Polygon2D
var design_root: Control
var blink_time := 0.0

func _ready() -> void:
	design_root = Control.new()
	design_root.size = SCREEN_SIZE
	# Stretch the original 240×160 GBA composition to this project's 16:9 viewport.
	design_root.scale = Vector2(8, 6.75)
	add_child(design_root)

	frame = TextureRect.new()
	frame.texture = load("res://assets/ui/field_message_box.png")
	frame.position = FRAME_POSITION
	frame.size = Vector2(240, 48)
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	design_root.add_child(frame)

	label = Label.new()
	# In the source, the window content begins at tile (2, 15); text starts one
	# pixel into its 27×4-tile interior.
	label.position = Vector2(16, 121)
	label.size = Vector2(208, 30)
	label.add_theme_color_override("font_color", Color8(96, 96, 96))
	label.add_theme_color_override("font_shadow_color", Color8(208, 208, 200))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 8)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	design_root.add_child(label)

	prompt_arrow = Polygon2D.new()
	prompt_arrow.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(7, 0), Vector2(3.5, 4)
	])
	prompt_arrow.position = Vector2(225, 150)
	prompt_arrow.color = Color8(96, 96, 96)
	prompt_arrow.visible = false
	design_root.add_child(prompt_arrow)

func _process(delta: float) -> void:
	if not frame.visible:
		return
	blink_time += delta
	prompt_arrow.visible = fmod(blink_time, 1.0) < 0.65

func show_message(message: String) -> void:
	label.text = message
	frame.visible = true
	label.visible = true
	prompt_arrow.visible = true
	blink_time = 0.0

func hide_message() -> void:
	if is_instance_valid(frame):
		frame.visible = false
		label.visible = false
		prompt_arrow.visible = false
