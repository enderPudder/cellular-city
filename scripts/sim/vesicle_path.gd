class_name VesiclePath extends RefCounted
## The route a vesicle train drives: straight along x, then straight along y.


static func cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [from]
	var c := from
	while c.x != to.x:
		c.x += signi(to.x - c.x)
		out.append(c)
	while c.y != to.y:
		c.y += signi(to.y - c.y)
		out.append(c)
	return out


## Name of the train animation (down/left/right/up) for a step from `from` to `to`.
static func direction(from: Vector2i, to: Vector2i) -> String:
	var d := to - from
	if absi(d.x) >= absi(d.y):
		return "right" if d.x >= 0 else "left"
	return "down" if d.y > 0 else "up"
