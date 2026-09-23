extends CanvasLayer

var panel: Panel
var label: Label
var design_root: Control

func _ready() -> void:
	design_root = Control.new()
	design_root.size = Vector2(320, 180)
	design_root.scale = Vector2(6, 6)
	add_child(design_root)
	panel = Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 16
	panel.offset_top = -52
	panel.offset_right = -16
	panel.offset_bottom = -8
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f8f4df")
	style.border_color = Color("342d40")
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", style)
	design_root.add_child(panel)
	label = Label.new()
	label.position = Vector2(8, 4)
	label.size = Vector2(272, 36)
	label.add_theme_color_override("font_color", Color("292632"))
	label.add_theme_font_size_override("font_size", 10)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)

func show_message(message: String) -> void:
	label.text = message
	panel.visible = true

func hide_message() -> void:
	if is_instance_valid(panel):
		panel.visible = false
