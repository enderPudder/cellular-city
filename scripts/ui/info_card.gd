class_name InfoCard extends CanvasLayer
## Pops up when an organelle unlocks and pauses the sim until dismissed.

var _game: CellGame
var _queue: Array[String] = []
var _title := Label.new()
var _body := RichTextLabel.new()


func setup(game: CellGame) -> void:
	_game = game
	layer = 15
	visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	_body.bbcode_enabled = true
	_body.fit_content = true
	box.add_child(_body)
	var ok := Button.new()
	ok.text = "Got it"
	ok.pressed.connect(_next)
	box.add_child(ok)
	game.sim_unlocked.connect(_on_unlocked)
	game.run_started.connect(func() -> void:
		_queue.clear()
		visible = false)


func _on_unlocked(def_id: String) -> void:
	_queue.append(def_id)
	if not visible:
		_next()


func _next() -> void:
	if _queue.is_empty():
		visible = false
		_game.set_paused(false)
		return
	var d: OrganelleDef = _game.sim.defs[_queue.pop_front()]
	_title.text = "Unlocked: %s" % d.display_name
	_body.text = "[b]In your cell:[/b] %s\n\n[b]In a city, it's the %s:[/b] %s" % [d.function_text, d.city_name.to_lower(), d.city_text]
	visible = true
	_game.set_paused(true)
