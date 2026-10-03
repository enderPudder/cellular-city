class_name Encyclopedia extends CanvasLayer
## Lists unlocked organelles with their city analogies; locked ones show only
## their unlock requirement. Toggled from the HUD button.

var _game: CellGame
var _list := VBoxContainer.new()


func setup(game: CellGame) -> void:
	_game = game
	layer = 12
	visible = false
	add_to_group("encyclopedia")
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(520, 380)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 330)
	scroll.add_child(_list)
	box.add_child(scroll)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(toggle)
	box.add_child(close)


func toggle() -> void:
	if _game.sim == null:
		return
	visible = not visible
	if visible:
		_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var sim := _game.sim
	var defs: Array = sim.defs.values()
	defs.sort_custom(func(a: OrganelleDef, b: OrganelleDef) -> bool: return a.display_name < b.display_name)
	for d: OrganelleDef in defs:
		if not d.allowed_cell_types.has(sim.cell_type):
			continue
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		if sim.unlocked_ids.has(d.id):
			label.text = "[b]%s[/b] = %s\n%s\n[i]%s[/i]\n" % [d.display_name, d.city_name, d.function_text, d.city_text]
		else:
			var parts: Array[String] = []
			var progress := sim.unlock_progress(d.id)
			for meter in progress:
				parts.append("%s %d" % [meter, progress[meter][1]])
			label.text = "[b]???[/b] Reach %s to unlock.\n" % " and ".join(parts)
		_list.add_child(label)
