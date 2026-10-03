class_name DifficultyCurve extends Resource
## Every value that scales with survival time lives here, in seconds.

@export var first_event_delay: float = 90.0
@export var interval_start: float = 90.0
@export var interval_floor: float = 40.0
@export var interval_ramp_seconds: float = 900.0
@export var size_start: int = 1
@export var size_max: int = 4
@export var size_ramp_seconds: float = 1200.0
@export var repair_start: float = 60.0
@export var repair_floor: float = 20.0
@export var repair_ramp_seconds: float = 600.0
@export var decay_multiplier_max: float = 2.0
@export var decay_ramp_seconds: float = 900.0


func _progress(t: float, ramp: float) -> float:
	return clampf(t / ramp, 0.0, 1.0)


func event_interval(t: float) -> float:
	return lerpf(interval_start, interval_floor, _progress(t, interval_ramp_seconds))


func event_size(t: float) -> int:
	return int(round(lerpf(float(size_start), float(size_max), _progress(t, size_ramp_seconds))))


func repair_window(t: float) -> float:
	return lerpf(repair_start, repair_floor, _progress(t, repair_ramp_seconds))


func decay_multiplier(t: float) -> float:
	return lerpf(1.0, decay_multiplier_max, _progress(t, decay_ramp_seconds))
