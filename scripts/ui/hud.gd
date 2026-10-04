class_name Hud extends CanvasLayer
## Meters, survival timer, active repair timers, hover tooltip.

const METER_COLORS := {
	"food": Color("e8a33d"), "energy": Color("f2d64b"), "water": Color("4aa3e0"),
	"waste": Color("8a6d3b"), "fat": Color("d9c7a0"),
}

var _game  # the CellGame node, untyped on purpose so helpers don't form a compile cycle with it
var _bars: Dictionary = {}
var _time := Label.new()
var _alerts := Label.new()
var _tip := Label.new()
var _root: UiRoot
var _palette: Control
var _stats: PanelContainer
var _panels_shown := true  # toggled by open_buildings; an attack overrides it for the stats tab


func setup(game) -> void:
	_game = game
	_root = UiRoot.attach(self)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.theme = MetalUi.theme()
	_root.add_child(panel)
	_stats = panel
	_palette = game.get_node_or_null("organell buttons and stuff") as Control
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_time)
	for m in CellSim.METERS:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = m.capitalize()
		name_label.custom_minimum_size.x = 56
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(110, 12)
		bar.show_percentage = false
		bar.modulate = METER_COLORS[m]
		row.add_child(name_label)
		row.add_child(bar)
		box.add_child(row)
		_bars[m] = bar
	box.add_child(_alerts)
	var book := Button.new()
	book.text = "Encyclopedia"
	book.pressed.connect(func() -> void: get_tree().call_group("encyclopedia", "toggle"))
	box.add_child(book)
	_tip.theme = MetalUi.theme()
	_tip.add_theme_color_override("font_color", Color.WHITE)
	_tip.add_theme_color_override("font_outline_color", Color.BLACK)
	_tip.add_theme_constant_override("outline_size", 4)
	_root.add_child(_tip)
	game.ticked.connect(_refresh)
	game.run_started.connect(_refresh)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_buildings"):
		_panels_shown = not _panels_shown
		_update_panels()
		_game.panels_toggled.emit(_panels_shown)
		get_viewport().set_input_as_handled()


## open_buildings shows/hides the buildings palette and the stats tab together.
## The stats tab also pops up while any repair is pending, then hides again.
func _update_panels() -> void:
	if _palette != null:
		_palette.visible = _panels_shown
	var under_attack: bool = _game.director != null and not _game.director.timers.is_empty()
	_stats.visible = _panels_shown or under_attack


func _refresh() -> void:
	var sim: CellSim = _game.sim
	var caps := sim.capacities()
	for m in CellSim.METERS:
		var bar: ProgressBar = _bars[m]
		bar.max_value = caps[m]
		bar.value = sim.meters[m]
	var seconds := int(sim.elapsed)
	_time.text = "Survived %d:%02d" % [seconds / 60, seconds % 60]
	var lines: Array[String] = []
	for t in _game.director.timers:
		lines.append("%s: %ds left" % [t["label"], ceili(t["remaining"])])
	_alerts.text = "\n".join(lines)
	_update_panels()


func _process(_delta: float) -> void:
	if _game.sim == null or not _game.running:
		_tip.text = ""
		return
	var uid: int = _game.uid_at(_game.cell_at_mouse())
	_tip.text = _game.describe(uid) if uid != -1 else ""
	_tip.position = get_viewport().get_mouse_position() / _root.scale.x + Vector2(14, 14)
