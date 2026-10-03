class_name SimLink extends RefCounted
## A drawn connection. `from_uid` is the consumer, `to_uid` its supplier
## (for FAT links: from the mitochondria to the ER).

enum Type { ENERGY, WATER, FAT, PROTEIN }

var from_uid: int = 0
var to_uid: int = 0
var type: int = Type.ENERGY


static func make(p_from: int, p_to: int, p_type: int) -> SimLink:
	var l := SimLink.new()
	l.from_uid = p_from
	l.to_uid = p_to
	l.type = p_type
	return l
