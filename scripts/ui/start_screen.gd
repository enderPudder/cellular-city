class_name StartScreen extends CanvasLayer
## Pick animal or plant to begin a run.


func setup(game: CellGame) -> void:
	layer = 20
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Cell is a City\nKeep your cell alive for as long as you can."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for entry in [["Animal cell", true], ["Plant cell", false]]:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(func() -> void:
			visible = false
			game.start_run(entry[1]))
		box.add_child(b)
