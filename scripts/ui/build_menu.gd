class_name BuildMenu extends CanvasLayer
## Wires the scene's own organelle palette ("organell buttons and stuff") to the
## sim: toggling a button selects that organelle, locked organelles are disabled
## and show progress toward their thresholds, and plant-only buttons are hidden
## in animal cells. Hovering a button shows a short themed tip (what it is and
## what must connect to it). Adds a small bottom bar with the Link and Repair tools.

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
	"golgi apparatus button": "golgi_apparatus",
}
const TOOL_TIPS := {
	"link": "[b]Link[/b]\nDrag from an organelle to what it needs: a mitochondria for energy, a membrane or cell wall for water.\nTo burn fat, link a mitochondria touching an ER to that ER.\nRight-click an organelle in this mode to cut its links.",
	"repair": "[b]Repair[/b]\nHold and move over damaged or worn tiles: everything inside the circle is repaired.\nCosts a little energy per tile.",
}
const TIP_WIDTH := 250.0
const TIP_FONT_SIZE := 12

var _game  # the CellGame node, untyped on purpose so helpers don't form a compile cycle with it
var _group := ButtonGroup.new()
var _buttons: Dictionary = {}  # tool id -> Button
var _base_text: Dictionary = {}  # tool id -> original button text
var _base_font_size: Dictionary = {}  # tool id -> the button's own font size
var _tip_panel := PanelContainer.new()
var _tip_label := RichTextLabel.new()


func setup(game) -> void:
	_game = game
	_group.allow_unpress = true
	_setup_tip_panel()
	var palette: Node = game.get_node_or_null(PALETTE_PATH)
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
	_add_tool(row, "link", "Link")
	_add_tool(row, "repair", "Repair")
	game.run_started.connect(_on_run_started)
	game.ticked.connect(_refresh)


func _setup_tip_panel() -> void:
	layer = 5
	_tip_panel.theme = MetalUi.theme()
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.visible = false
	_tip_label.bbcode_enabled = true
	_tip_label.fit_content = true
	_tip_label.scroll_active = false
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label.custom_minimum_size = Vector2(TIP_WIDTH, 0)
	_tip_label.add_theme_font_size_override("normal_font_size", TIP_FONT_SIZE)
	_tip_label.add_theme_font_size_override("bold_font_size", TIP_FONT_SIZE)
	_tip_panel.add_child(_tip_label)
	add_child(_tip_panel)


func _bind(id: String, b: Button) -> void:
	b.toggle_mode = true
	b.button_group = _group
	b.tooltip_text = ""  # the themed tip panel replaces the default tooltip
	b.toggled.connect(func(pressed: bool) -> void: _select(id, pressed))
	b.mouse_entered.connect(func() -> void: show_tip_for(id, b))
	b.mouse_exited.connect(hide_tip)
	_buttons[id] = b
	_base_text[id] = b.text
	_base_font_size[id] = b.get_theme_font_size("font_size")


func _add_tool(row: HBoxContainer, id: String, text: String) -> void:
	var b := Button.new()
	b.text = text
	row.add_child(b)
	_bind(id, b)


func _select(id: String, pressed: bool) -> void:
	if pressed:
		_game.tool = id
	elif _game.tool == id:
		_game.tool = ""


## Shows the tip for tool/organelle `id` next to `anchor`, kept on screen.
func show_tip_for(id: String, anchor: Control) -> void:
	if TOOL_TIPS.has(id):
		_tip_label.text = TOOL_TIPS[id]
	elif _game.sim != null and _game.sim.defs.has(id):
		var progress := {}
		if not _game.sim.unlocked_ids.has(id):
			progress = _game.sim.unlock_progress(id)
		_tip_label.text = OrganelleTip.build(_game.sim.defs[id], _game.sim.cell_type, progress)
	else:
		return
	_tip_panel.reset_size()
	_tip_panel.visible = true
	var rect := anchor.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, anchor.size)
	var view := anchor.get_viewport().get_visible_rect().size
	var size := _tip_panel.get_combined_minimum_size()
	var x := rect.end.x + 8.0
	if x + size.x > view.x:
		x = rect.position.x - size.x - 8.0
	var y := clampf(rect.position.y, 8.0, maxf(8.0, view.y - size.y - 8.0))
	_tip_panel.position = Vector2(x, y)


func hide_tip() -> void:
	_tip_panel.visible = false


func _on_run_started() -> void:
	for id in _buttons:
		var b: Button = _buttons[id]
		b.set_pressed_no_signal(false)
		if _game.sim.defs.has(id):
			var d: OrganelleDef = _game.sim.defs[id]
			b.visible = d.allowed_cell_types.has(_game.sim.cell_type)
			b.clip_text = true
	_refresh()


func _refresh() -> void:
	var sim: CellSim = _game.sim
	for id in _buttons:
		if not sim.defs.has(id):
			continue
		var b: Button = _buttons[id]
		var locked := not sim.unlocked_ids.has(id)
		b.disabled = locked
		if locked:
			var first := ""
			var unmet := 0
			var progress := sim.unlock_progress(id)
			for meter in progress:
				if progress[meter][0] >= progress[meter][1]:
					continue
				unmet += 1
				if first == "":
					first = "%d/%d" % [progress[meter][0], progress[meter][1]]
			if unmet > 1:
				first += "+"
			b.text = "%s %s" % [_base_text[id], first]
			b.add_theme_font_size_override("font_size", 10)
		else:
			b.text = _base_text[id]
			b.add_theme_font_size_override("font_size", _base_font_size[id])
