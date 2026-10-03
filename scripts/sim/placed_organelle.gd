class_name PlacedOrganelle extends RefCounted
## Runtime state of one placed tile.

var uid: int = 0
var def: OrganelleDef
var cell: Vector2i = Vector2i.ZERO
var health: float = 100.0
var disabled: bool = false  # knocked out by a bacteria event until repaired
var energy_ok: bool = false
var water_ok: bool = false
var running: bool = false


func alive() -> bool:
	return health > 0.0 and not disabled
