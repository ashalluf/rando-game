extends RefCounted
## The reset between check files (tests/gate_reset.gd, docs/HANDOFF.md "Every check file starts
## from a clean city"): what it puts back, the light reset leaving nodes alone, and the file list
## SMOKE_SHUFFLE permutes.


func run(t, city: Node3D) -> void:
	var reset = t._reset
	t._check(reset != null, "the smoke test took a snapshot of the clean city before the first part")
	if reset == null:
		return
	var tree: SceneTree = t.get_tree()

	# Statics: a switch, a forced value, a forced kind.
	var onl_was: bool = Onlookers.enabled
	var rain_was: float = RainCrowd.forced
	var panic_was: int = CarPanic.force_kind
	var fleet_was: bool = ServiceFleet.enabled
	Onlookers.enabled = not onl_was
	RainCrowd.forced = 0.8
	CarPanic.force_kind = 2
	ServiceFleet.enabled = not fleet_was
	var n: int = reset.light()
	t._check(n >= 4 and Onlookers.enabled == onl_was and RainCrowd.forced == rain_was
		and CarPanic.force_kind == panic_was and ServiceFleet.enabled == fleet_was,
		"the light reset puts the statics back (%d: Onlookers.enabled, RainCrowd.forced, CarPanic.force_kind, ServiceFleet.enabled)" % n)

	# The city: weather, hour, time scale, staged traffic, the units' switches, destruction.
	var weather: Node = city.get_node("Weather")
	var dn: Node = city.get_node("DayNight")
	var traffic: Node = city.get_node("Traffic")
	var police: Node = city.get_node("Police")
	var emergency: Node = city.get_node("Emergency")
	var ws: Node = tree.root.get_node("WorldState")
	var state_was := int(weather.get("state"))
	var forced_was: bool = bool(weather.call("is_forced"))
	var hour_was := float(dn.get("hour"))
	var staged_was: bool = bool(traffic.get("staged"))
	var cap_was := int(traffic.get("max_cars"))
	var police_was: bool = bool(police.get("enabled"))
	var emergency_was: bool = bool(emergency.get("enabled"))
	weather.call("force_state", 3) # storm
	dn.set("hour", hour_was + 7.5)
	traffic.set("staged", not staged_was)
	traffic.set("max_cars", cap_was + 5)
	police.set("enabled", not police_was)
	emergency.set("enabled", not emergency_was)
	ws.call("mark_destroyed", "gate_reset_check", "prop_0")
	Engine.time_scale = 0.4
	Onlookers.enabled = not onl_was
	reset.full(tree)
	t._check(int(weather.get("state")) == state_was and bool(weather.call("is_forced")) == forced_was,
		"the full reset puts the weather back (state %d, forced %s)" % [int(weather.get("state")), weather.call("is_forced")])
	# (Back to the snapshot's hour: the clock runs on its own, so "before" is not the hour to expect.)
	t._check(is_equal_approx(float(dn.get("hour")), float(reset._hour)), "the full reset puts the hour back to the snapshot's (%.2f)" % float(dn.get("hour")))
	t._check(bool(traffic.get("staged")) == staged_was and int(traffic.get("max_cars")) == cap_was,
		"the full reset un-stages the traffic and puts its cap back")
	t._check(bool(police.get("enabled")) == police_was and bool(emergency.get("enabled")) == emergency_was,
		"the full reset puts the police's and the emergency services' switches back")
	t._check(not bool(ws.call("is_destroyed", "gate_reset_check", "prop_0")) and Engine.time_scale == 1.0
		and Onlookers.enabled == onl_was, "the full reset clears destruction, time scale and the statics")
	t._check(reset.last.has("Weather:state") and reset.last.has("Police:enabled"),
		"the reset says what it put back (%s)" % ",".join(reset.last.keys()))

	# The file list: every check file that is not run from inside a part is on it (SMOKE_SHUFFLE
	# permutes this list, and a file missing from it never runs in a whole run either).
	var files: Array = t.city_file_list()
	var listed := {}
	for f in files:
		listed[str(f[0]).get_file().get_basename()] = true
	var missing: Array = []
	for part in t.all_parts():
		if part == "room" or t.CITY_PARTS.has(part):
			continue
		if not listed.has(part):
			missing.append(part)
	t._check(files.size() >= 100 and missing.is_empty() and listed.has("gate_speed_2_checks"),
		"city_files lists every check file (%d listed; missing: %s)" % [files.size(), ",".join(missing)])
