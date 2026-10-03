extends McpTestSuite


func suite_name() -> String:
	return "game_speed"


func test_multiplier_is_zero_when_paused_and_matches_the_speed_otherwise() -> void:
	assert_eq(GameSpeed.multiplier(GameSpeed.PAUSED), 0.0)
	assert_eq(GameSpeed.multiplier(GameSpeed.NORMAL), 1.0)
	assert_eq(GameSpeed.multiplier(GameSpeed.DOUBLE), 2.0)


func test_tick_interval_halves_at_double_speed() -> void:
	assert_eq(GameSpeed.tick_interval(GameSpeed.NORMAL, 1.0), 1.0)
	assert_eq(GameSpeed.tick_interval(GameSpeed.DOUBLE, 1.0), 0.5)


func test_tick_interval_stays_valid_while_paused() -> void:
	assert_gt(GameSpeed.tick_interval(GameSpeed.PAUSED, 1.0), 0.0, "a Timer cannot have a zero wait time")


func test_unknown_speeds_are_treated_as_normal() -> void:
	assert_eq(GameSpeed.multiplier(7), 1.0)
	assert_eq(GameSpeed.tick_interval(-1, 1.0), 1.0)
