extends McpTestSuite


func suite_name() -> String:
	return "vesicle_path"


func test_path_goes_along_x_then_y_and_includes_both_ends() -> void:
	var cells := VesiclePath.cells(Vector2i(0, 0), Vector2i(3, -2))
	assert_eq(cells[0], Vector2i(0, 0))
	assert_eq(cells[cells.size() - 1], Vector2i(3, -2))
	assert_eq(cells.size(), 6)
	assert_eq(cells[3], Vector2i(3, 0), "turns after reaching the target column")


func test_every_step_moves_exactly_one_tile() -> void:
	for pair in [[Vector2i(-4, 3), Vector2i(5, -6)], [Vector2i(2, 2), Vector2i(2, 9)], [Vector2i(7, 1), Vector2i(-2, 1)]]:
		var cells := VesiclePath.cells(pair[0], pair[1])
		for i in range(1, cells.size()):
			assert_eq(absi(cells[i].x - cells[i - 1].x) + absi(cells[i].y - cells[i - 1].y), 1)


func test_same_cell_is_a_single_tile_path() -> void:
	assert_eq(VesiclePath.cells(Vector2i(4, 4), Vector2i(4, 4)), [Vector2i(4, 4)] as Array[Vector2i])


func test_direction_names_match_the_train_animations() -> void:
	assert_eq(VesiclePath.direction(Vector2i(0, 0), Vector2i(1, 0)), "right")
	assert_eq(VesiclePath.direction(Vector2i(0, 0), Vector2i(-1, 0)), "left")
	assert_eq(VesiclePath.direction(Vector2i(0, 0), Vector2i(0, 1)), "down")
	assert_eq(VesiclePath.direction(Vector2i(0, 0), Vector2i(0, -1)), "up")
