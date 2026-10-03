class_name BuildInput extends Node
## Mouse handling. `click` places/repairs (hold to paint), `erase` removes,
## and in link mode left-drag from one organelle to another draws a link.

## Override to supply the cell under the pointer (used by the smoke test).
var mouse_cell: Callable = Callable()

var _game: CellGame
var _drag_uid: int = -1


func setup(game: CellGame) -> void:
	_game = game


func _cell() -> Vector2i:
	return mouse_cell.call() if mouse_cell.is_valid() else _game.cell_at_mouse()


func _blocked() -> bool:
	return not _game.running or _game.paused or _game.get_viewport().gui_get_hovered_control() != null


func _process(_delta: float) -> void:
	if _blocked():
		return
	var cell := _cell()
	if Input.is_action_pressed("click"):
		if _game.tool == "repair":
			_game.try_repair(cell)
		elif _game.tool != "" and _game.tool != "link":
			_game.try_place(_game.tool, cell)
	if Input.is_action_pressed("erase"):
		_game.try_erase(cell)


func _unhandled_input(event: InputEvent) -> void:
	if not _game.running or _game.paused or _game.tool != "link":
		return
	if not (event is InputEventMouseButton) or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	if (event as InputEventMouseButton).pressed:
		_drag_uid = _game.uid_at(_cell())
		_game.link_drag_from = _drag_uid
	else:
		if _drag_uid != -1:
			var target := _game.uid_at(_cell())
			if target != -1:
				_game.sim.add_link(_drag_uid, target)
		_drag_uid = -1
		_game.link_drag_from = -1
