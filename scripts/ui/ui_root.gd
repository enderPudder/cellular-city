class_name UiRoot extends Control
## Full-screen container that scales its children by `UiScale.factor` and resizes
## itself to viewport / factor, so anchors on its children still hug the screen edges.
## UI scripts add their controls here instead of straight to their CanvasLayer.


## Creates a UiRoot under `layer` and returns it.
static func attach(layer: CanvasLayer) -> UiRoot:
	var root := UiRoot.new()
	layer.add_child(root)
	return root


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var f := UiScale.factor(get_viewport())
	scale = Vector2.ONE * f
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size / f
