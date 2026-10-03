extends SceneTree
## Headless runner for res://tests/test_*.gd (McpTestSuite subclasses).
## Run: godot --headless --path . --script res://tools/run_tests.gd [-- suite_name]
## Exits non-zero if any test fails.


func _init() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0]
	var passed := 0
	var failed := 0
	var dir := DirAccess.open("res://tests")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		var script := ResourceLoader.load("res://tests/" + f, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if script == null or not script.can_instantiate():
			print("FAIL  %s: cannot load (parse error?)" % f)
			failed += 1
			continue
		var suite: McpTestSuite = script.new()
		if only != "" and suite.suite_name() != only:
			continue
		var methods: Array[String] = []
		for m in suite.get_method_list():
			if String(m["name"]).begins_with("test_"):
				methods.append(m["name"])
		methods.sort()
		for name in methods:
			suite._reset()
			suite.setup()
			suite.call(name)
			suite.teardown()
			suite._free_tracked()
			if suite._failed or suite._assertion_count == 0:
				failed += 1
				print("FAIL  %s.%s: %s" % [suite.suite_name(), name, suite._message if suite._failed else "0 assertions"])
			else:
				passed += 1
	print("RESULT passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)
