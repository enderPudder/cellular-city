class_name UiScale extends RefCounted
## One scale factor for all UI, derived from the window height, so the HUD shrinks
## and grows with the screen. The world keeps the project's stretch scale; only UI
## is scaled by this.

## Visible height (in stretched viewport units) at which the UI is drawn at BASE.
const REF_HEIGHT := 648.0
## UI size at REF_HEIGHT. Lower = smaller UI.
const BASE := 0.8
## The window-height ratio is clamped so the UI never becomes tiny or huge.
const MIN_RATIO := 0.6
const MAX_RATIO := 1.6


static func factor(viewport: Viewport) -> float:
	var ratio := clampf(viewport.get_visible_rect().size.y / REF_HEIGHT, MIN_RATIO, MAX_RATIO)
	return BASE * ratio
