class_name VesicleFleet extends Node2D
## Spawns a vesicle train for every shipment the sim dispatches. The train
## drives the route from VesiclePath, the "vesicles" layer lays a track tile
## under it as it goes, and on arrival the shipment is delivered to the sim.

const TRAIN_SCENE: PackedScene = preload("res://scene/vesicle train.tscn")
const SPEED_TILES_PER_SECOND := 4.0

## Each train: {node: Node2D, cells: Array[Vector2i], progress: float, shipment: Shipment, laid: int}
var trains: Array[Dictionary] = []

var _game: CellGame


func setup(game: CellGame) -> void:
	_game = game
	z_index = 9
	game.run_started.connect(_on_run_started)


func _on_run_started() -> void:
	for t in trains:
		(t["node"] as Node).queue_free()
	trains.clear()
	_game.sim.shipment_dispatched.connect(_spawn)


func _process(delta: float) -> void:
	if _game.running:
		step(_game.scaled_delta(delta))


func _spawn(shipment: Shipment) -> void:
	var golgi: PlacedOrganelle = _game.sim.organelles.get(shipment.from_uid)
	var target: PlacedOrganelle = _game.sim.organelles.get(shipment.to_uid)
	if golgi == null or target == null:
		return
	var node: Node2D = TRAIN_SCENE.instantiate()
	add_child(node)
	var cells := VesiclePath.cells(golgi.cell, target.cell)
	node.position = _game.cell_center(cells[0])
	trains.append({"node": node, "cells": cells, "progress": 0.0, "shipment": shipment, "laid": -1})
	_lay_track(trains[trains.size() - 1])


## Moves every train `dt` seconds along its route.
func step(dt: float) -> void:
	for t in trains.duplicate():
		t["progress"] = float(t["progress"]) + SPEED_TILES_PER_SECOND * dt
		var cells: Array[Vector2i] = t["cells"]
		var last := cells.size() - 1
		var node: Node2D = t["node"]
		if float(t["progress"]) >= last:
			node.position = _game.cell_center(cells[last])
			_lay_track(t)
			_game.sim.deliver(t["shipment"])
			node.queue_free()
			trains.erase(t)
			continue
		var i := int(float(t["progress"]))
		var a := _game.cell_center(cells[i])
		var b := _game.cell_center(cells[i + 1])
		node.position = a.lerp(b, float(t["progress"]) - i)
		var sprite := node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite != null:
			sprite.animation = VesiclePath.direction(cells[i], cells[i + 1])
		_lay_track(t)


## Lays track under the train's current tile (not on top of organelles).
func _lay_track(t: Dictionary) -> void:
	var cells: Array[Vector2i] = t["cells"]
	var i := mini(int(float(t["progress"])), cells.size() - 1)
	if i == int(t["laid"]):
		return
	t["laid"] = i
	var layer := _game.layer_for("vesicles")
	if layer != null and _game.sim.organelle_at(cells[i]) == -1:
		layer.show_tile(cells[i])
