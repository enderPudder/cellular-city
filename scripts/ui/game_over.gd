class_name GameOver extends CanvasLayer
## Shown when a run is lost. Restart reloads the scene.

const REASONS := {
	"nucleus": "Your cell lost its nucleus.",
	"repair_timeout": "A repair ran out of time.",
}


func setup(game: CellGame) -> void:
	layer = 20
	visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var restart := Button.new()
	restart.text = "Play again"
	restart.pressed.connect(func() -> void: get_tree().reload_current_scene())
	box.add_child(restart)
	game.run_lost.connect(func(reason: String) -> void:
		var seconds := int(game.sim.elapsed)
		label.text = "%s\nYou survived %d:%02d." % [REASONS.get(reason, reason), seconds / 60, seconds % 60]
		visible = true)
