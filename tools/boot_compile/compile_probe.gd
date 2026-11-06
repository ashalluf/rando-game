extends Node
## Compiles the game's scripts the way the boot does (boot.gd's compile_order(), one load() each)
## and prints what each slow load cost: the big cycle's load, how many hooked scripts it compiled,
## and the longest stretches between two of their static initialisers (LoadPulse.compiled(): how
## long the boot's picture can hold still now), with the script that ended each. Headless, about
## the time of the compile (15 s on a 4-core box):
##   godot --headless --path . tools/boot_compile/compile_probe.tscn
## ENTRY=res://... loads that script first (which script the cycle is entered by); TRACE_HEAD=1
## lists the first hooks. On a tree without the hook (main before boot-compile) it still prints the
## load times. Errors in any script show up as SCRIPT ERROR / Parse Error lines above the summary.

func _ready() -> void:
	var order: PackedStringArray = load("res://scripts/util/boot.gd").compile_order()
	var entry := OS.get_environment("ENTRY")
	if entry != "":
		order.insert(0, entry)
	var lp = load("res://scripts/util/load_pulse.gd")
	var hooked := false
	for m: Dictionary in lp.get_script_method_list():
		if m["name"] == "compile_mark":
			hooked = true
	if hooked:
		lp._tracing = true
	var t0 := Time.get_ticks_msec()
	var worst := 0
	for p in order:
		var a := Time.get_ticks_msec()
		var start_us := Time.get_ticks_usec()
		if hooked:
			lp.compiled_count = 0
			lp.compile_mark()
			lp.compile_trace.clear()
		var s = load(p)
		var ms := Time.get_ticks_msec() - a
		if s == null:
			print("COMPILE FAILED ", p)
		worst = maxi(worst, ms)
		if ms <= 500:
			continue
		if not hooked:
			print("COMPILE %s: %d ms in one load() (no hook: the picture holds still for all of it)" % [p.get_file(), ms])
			continue
		print("COMPILE %s: %d ms, %d hooked scripts, longest step %d ms" % [p.get_file(), ms, lp.compiled_count, lp.compile_max_gap_us / 1000])
		var trace: Array = lp.compile_trace
		if trace.size() < 2:
			continue
		if OS.get_environment("TRACE_HEAD") == "1":
			for i in mini(16, trace.size()):
				print("  HOOK %3d at %6d ms  %s" % [i + 1, (int(trace[i][0]) - start_us) / 1000, trace[i][1]])
		var gaps := []
		var last := start_us
		for e: Array in trace:
			gaps.append([int(e[0]) - last, e[1]])
			last = int(e[0])
		gaps.sort_custom(func(x, y): return x[0] > y[0])
		for g in gaps.slice(0, 8):
			print("  STEP %6d ms ending at %s" % [g[0] / 1000, g[1]])
		var over := 0
		for g in gaps:
			if g[0] > 250000:
				over += 1
		print("  steps over 250 ms: %d of %d" % [over, gaps.size()])
	print("COMPILE all %d scripts: %d ms, slowest load %d ms" % [order.size(), Time.get_ticks_msec() - t0, worst])
	get_tree().quit()
