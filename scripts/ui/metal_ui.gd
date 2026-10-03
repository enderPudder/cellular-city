class_name MetalUi extends RefCounted
## The scene's "custom metal plate theme", extended for the controls the game
## builds in code. Panels use the theme's metal panel, labels use its font
## (without the plate behind them), and everything else inherits from it.

const BASE_THEME: Theme = preload("res://assets/themes/custom/custom metal plate theme.tres")

static var _theme: Theme


static func theme() -> Theme:
	if _theme == null:
		_theme = BASE_THEME.duplicate()
		var font := BASE_THEME.get_font("font", "Button")
		_theme.default_font = font
		_theme.default_font_size = 14
		_theme.set_stylebox("panel", "PanelContainer", BASE_THEME.get_stylebox("panel", "Panel"))
		_theme.set_stylebox("normal", "Label", StyleBoxEmpty.new())
		_theme.set_stylebox("focus", "Label", StyleBoxEmpty.new())
		_theme.set_color("font_color", "Label", Color(0.92, 0.92, 0.92))
		var bar_bg := StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.1, 0.1, 0.12)
		bar_bg.set_corner_radius_all(2)
		var bar_fill := StyleBoxFlat.new()
		bar_fill.bg_color = Color.WHITE
		bar_fill.set_corner_radius_all(2)
		_theme.set_stylebox("background", "ProgressBar", bar_bg)
		_theme.set_stylebox("fill", "ProgressBar", bar_fill)
	return _theme
