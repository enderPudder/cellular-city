class_name GuideHud extends CanvasLayer
## Checklist that walks a new player through the basic cell setup, then
## collapses to a small "Basics done" chip. Hidden until the intro has finished.

const DONE_COLOR := Color("8fd694")
const CURRENT_COLOR := Color("f2d64b")
const WIDTH := 200

var _game  # the CellGame node, untyped on purpose so helpers don't form a compile cycle with it
var _root: UiRoot
var _panel := PanelContainer.new()
var _list := VBoxContainer.new()
var _hint := Label.new()
var _chip := PanelContainer.new()
var _rows: Dictionary = {}  # step id -> Label
var _intro_done := false
var _basics_done := false
var _panels_shown := true


func setup(game) -> void:
	_game = game
	_root = UiRoot.attach(self)
	_panel.theme = MetalUi.theme()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Set up your cell"
	box.add_child(title)
	box.add_child(_list)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = WIDTH
	box.add_child(_hint)
	_chip.theme = MetalUi.theme()
	_chip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var chip_label := Label.new()
	chip_label.text = "Basics done"
	chip_label.add_theme_color_override("font_color", DONE_COLOR)
	_chip.add_child(chip_label)
	_root.add_child(_chip)
	game.run_started.connect(_on_run_started)
	game.intro_finished.connect(_on_intro_finished)
	game.guide_changed.connect(_refresh)
	game.setup_done.connect(_refresh)
	game.panels_toggled.connect(_on_panels_toggled)
	_update_visibility()


func _on_run_started() -> void:
	_intro_done = false
	_basics_done = false
	for child in _list.get_children():
		child.queue_free()
	_rows.clear()
	for step in _game.guide.steps():
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDTH
		_list.add_child(label)
		_rows[step["id"]] = label
	_refresh()


func _on_intro_finished() -> void:
	_intro_done = true
	_update_visibility()


func _on_panels_toggled(shown: bool) -> void:
	_panels_shown = shown
	_update_visibility()


func _refresh() -> void:
	var guide: SetupGuide = _game.guide
	if guide == null:
		return
	var current: Dictionary = guide.current_step()
	for step in guide.steps():
		var label: Label = _rows.get(step["id"])
		if label == null:
			continue
		var done := guide.step_done(step["id"])
		label.text = ("[x] " if done else "[ ] ") + String(step["label"])
		if done:
			label.add_theme_color_override("font_color", DONE_COLOR)
		elif not current.is_empty() and current["id"] == step["id"]:
			label.add_theme_color_override("font_color", CURRENT_COLOR)
		else:
			label.remove_theme_color_override("font_color")
	_hint.text = String(current.get("hint", ""))
	_basics_done = guide.core_done
	_update_visibility()


func _update_visibility() -> void:
	var show := _intro_done and _panels_shown
	_panel.visible = show and not _basics_done
	_chip.visible = show and _basics_done
