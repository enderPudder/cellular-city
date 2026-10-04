class_name SpeedControls extends CanvasLayer
## Three buttons at the top of the screen: pause, normal speed, double speed.

const LABELS := {GameSpeed.PAUSED: "||", GameSpeed.NORMAL: "1x", GameSpeed.DOUBLE: "2x"}
const TIPS := {
	GameSpeed.PAUSED: "Pause the cell. You can still build and repair.",
	GameSpeed.NORMAL: "Normal speed",
	GameSpeed.DOUBLE: "Double speed",
}

var _game  # the CellGame node, untyped on purpose so helpers don't form a compile cycle with it
var _buttons: Dictionary = {}  # speed -> Button
var _group := ButtonGroup.new()


func setup(game) -> void:
	_game = game
	layer = 6
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.theme = MetalUi.theme()
	add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	for speed in [GameSpeed.PAUSED, GameSpeed.NORMAL, GameSpeed.DOUBLE]:
		var b := Button.new()
		b.text = LABELS[speed]
		b.tooltip_text = TIPS[speed]
		b.toggle_mode = true
		b.button_group = _group
		b.custom_minimum_size = Vector2(44, 0)
		b.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				_game.set_speed(speed))
		row.add_child(b)
		_buttons[speed] = b
	game.speed_changed.connect(_on_speed_changed)
	_on_speed_changed(game.speed)


func _on_speed_changed(speed: int) -> void:
	if _buttons.has(speed):
		(_buttons[speed] as Button).set_pressed_no_signal(true)
