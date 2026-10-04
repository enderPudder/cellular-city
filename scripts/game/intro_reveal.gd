class_name IntroReveal extends RefCounted
## Reveals a list of tiles one at a time over a fixed total time, so the intro
## lasts the same for any cell size. Scene-free: `show_tile` does the drawing.

signal finished

const TOTAL_SECONDS := 2.5

var done := false

var _tiles: Array[Dictionary]
var _show: Callable
var _total: float
var _elapsed := 0.0
var _shown := 0


func _init(tiles: Array[Dictionary], show_tile: Callable, total_seconds: float = TOTAL_SECONDS) -> void:
	_tiles = tiles
	_show = show_tile
	_total = total_seconds


func advance(delta: float) -> void:
	if done:
		return
	_elapsed += delta
	var target := _tiles.size() if _elapsed >= _total else int(_tiles.size() * _elapsed / _total)
	_reveal_to(target)


## Shows every remaining tile at once (tests and tools; the player cannot skip).
func skip() -> void:
	if not done:
		_reveal_to(_tiles.size())


func _reveal_to(target: int) -> void:
	while _shown < target:
		var t: Dictionary = _tiles[_shown]
		_show.call(t["id"], t["cell"])
		_shown += 1
	if _shown >= _tiles.size():
		done = true
		finished.emit()
