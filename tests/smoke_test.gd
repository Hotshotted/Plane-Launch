extends SceneTree
## Headless smoke test:  godot --headless --path . --script res://tests/smoke_test.gd
## Exits with code 1 if any check fails (CI runs this before exporting).

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	check(is_instance_valid(main), "main scene boots")
	var f = load("res://scripts/Flight.gd").new()
	f.reset({}, 7)
	f.launch()
	var t := 0.0
	while not f.is_over() and t < 120.0:
		f.advance(1.0 / 60.0, f.pilot(1.0 / 60.0))
		f.ev_n = 0
		t += 1.0 / 60.0
	check(f.is_over() and f.distance > 20.0, "a run ends with a touchdown (%.0f m)" % f.distance)
	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED: %d" % failures.size())
		quit(1)
