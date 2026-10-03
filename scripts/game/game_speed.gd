class_name GameSpeed extends RefCounted
## The three speeds of the speed buttons.

const PAUSED := 0
const NORMAL := 1
const DOUBLE := 2


## How many times faster than normal time runs (0 = stopped). Unknown values count as normal.
static func multiplier(speed: int) -> float:
	match speed:
		PAUSED:
			return 0.0
		DOUBLE:
			return 2.0
		_:
			return 1.0


## Seconds between sim ticks. Stays positive while paused (a Timer needs a wait
## time; the timer itself is paused instead).
static func tick_interval(speed: int, base_seconds: float) -> float:
	var m := multiplier(speed)
	return base_seconds / (m if m > 0.0 else 1.0)
