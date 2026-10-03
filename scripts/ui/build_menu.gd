class_name BuildMenu extends CanvasLayer
## Wires the scene's own organelle palette ("organell buttons and stuff") to the
## sim: toggling a button selects that organelle, locked organelles are disabled
## and show progress toward their thresholds, and plant-only buttons are hidden
## in animal cells. Adds a small bottom bar with the Link and Repair tools.

const PALETTE_PATH := "organell buttons and stuff/MarginContainer/Panel/MarginContainer/VBoxContainer"
const BUTTON_IDS := {
	"membrane Button": "membrane",
	"nucleus button": "nucleus",
	"vacuole button": "vacuole",
	"cytoplasm button": "cytoplasm",
	"mitochondria button": "mitochondria",
	"cell wall button": "cell_wall",
	"chromosome button": "chromosomes",
	"chloroplast": "chloroplast",
	"endoplasmic reculum": "endoplasmic_reticulum",
	"lysosome button": "lysosome",
}

var _game: CellGame
var _group := ButtonGroup.new()
var _buttons: Dictionary = {}  # tool id -> Button
var _base_text: Dictionary = {}  # tool id -> original button text
var _full_tip: Dictionary = {}  # tool id -> teaching tooltip


func setup(game: CellGame) -> void:
	_game = game
	_group.allow_unpress = true
	var palette := game.get_node_or_null(PALETTE_PATH)
	if palette != null:
		for node_name in BUTTON_IDS:
			var b := palette.get_node_or_null(node_name) as Button
			if b != null:
				_bind(BUTTON_IDS[node_name], b)
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 8)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.theme = MetalUi.theme()
	add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	_add_tool(row, "link", "Link", "Drag from an organelle to its supplier: a mitochondria for energy, a membrane or cell wall for water. Beside an ER, link a mitochondria to the ER to let it burn fat. Right-click an organelle in this mode to cut its links.")
	_add_tool(row, "repair", "Repair", "Click or drag over damaged or worn tiles to repair them. Costs a little energy.")
	game.run_started.connect(_on_run_started)
	game.ticked.connect(_refresh)


func _bind(id: String, b: Button) -> void:
	b.toggle_mode = true
	b.button_group = _group
	b.toggled.connect(func(pressed: bool) -> void: _select(id, pressed))
	_buttons[id] = b
	_base_text[id] = b.text


func _add_tool(row: HBoxContainer, id: String, text: String, tip: String) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	row.add_child(b)
	_bind(id, b)


func _select(id: String, pressed: bool) -> void:
	if pressed:
		_game.tool = id
	elif _game.tool == id:
		_game.tool = ""


func _on_run_started() -> void:
	for id in _buttons:
		var b: Button = _buttons[id]
		b.set_pressed_no_signal(false)
		if _game.sim.defs.has(id):
			var d: OrganelleDef = _game.sim.defs[id]
			b.visible = d.allowed_cell_types.has(_game.sim.cell_type)
			_full_tip[id] = "%s\n\nIn a city: %s (%s)" % [d.function_text, d.city_name, d.city_text]
			b.clip_text = true
	_refresh()


func _refresh() -> void:
	var sim := _game.sim
	for id in _buttons:
		if not sim.defs.has(id):
			continue
		var b: Button = _buttons[id]
		var locked := not sim.unlocked_ids.has(id)
		b.disabled = locked
		if locked:
			var first := ""
			var needs: Array[String] = []
			var progress := sim.unlock_progress(id)
			for meter in progress:
				if progress[meter][0] >= progress[meter][1]:
					continue
				if first == "":
					first = "%d/%d" % [progress[meter][0], progress[meter][1]]
				needs.append("%s %d (now %d)" % [meter, progress[meter][1], progress[meter][0]])
			if needs.size() > 1:
				first += "+"
			b.text = "%s %s" % [_base_text[id], first]
			b.tooltip_text = "Locked: reach %s to unlock.\n\n%s" % [" and ".join(needs), _full_tip.get(id, "")]
			b.add_theme_font_size_override("font_size", 10)
		else:
			b.text = _base_text[id]
			b.tooltip_text = _full_tip.get(id, "")
			b.remove_theme_font_size_override("font_size")
