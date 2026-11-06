extends RefCounted
## Fireworks (scripts/world/fireworks.gd, shaders/fireworks*.gdshader, docs/HANDOFF.md
## "Fireworks"): checks for tests/smoke_test.gd. Loaded at run time, so it compiles after the
## autoloads. No shader runs under --headless, so these hold the plan both sides share (the
## include's numbers read back, the integer hash), the shows it makes, which nights have one, where
## the sites stand, the booms' timing by the speed of sound, and the node driving a staged show;
## tools/glshot/still_shot.gd (FIREWORKS=1 FIREWORKS_T= FIREWORKS_HOLD=1) shows the pixels.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_mirror()
	_the_plan()
	_the_nights()
	_the_sites(city)
	await _the_node(city)


func _const_f(src: String, name: String) -> float:
	var re := RegEx.new()
	re.compile("const (?:float|int) " + name + " = ([-0-9.]+);")
	var m := re.search(src)
	return float(m.get_string(1)) if m else NAN


func _const_list(src: String, name: String) -> Array:
	var re := RegEx.new()
	re.compile("const float " + name + "\\[\\d+\\] = float\\[\\d+\\]\\(([^)]*)\\)")
	var m := re.search(src)
	var out: Array = []
	if m:
		for x in m.get_string(1).split(","):
			out.append(float(x.strip_edges()))
	return out


## The include's numbers are Fireworks' numbers; the hash is the shader's lowbias hash.
func _mirror() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/fireworks.gdshaderinc")
	var pairs := {"FW_BIN": Fireworks.BIN, "FW_SLOTS": Fireworks.SLOTS, "FW_STARS": Fireworks.STARS,
		"FW_TRAIL": Fireworks.TRAIL, "FW_SMOKE_SLOTS": Fireworks.SMOKE_SLOTS, "FW_SMOKE_LIFE": Fireworks.SMOKE_LIFE,
		"FW_ACT_BINS": Fireworks.ACT_BINS, "FW_OPEN_END": Fireworks.OPEN_END, "FW_BODY_END": Fireworks.BODY_END,
		"FW_BUILD_END": Fireworks.BUILD_END, "FW_FINALE_END": Fireworks.FINALE_END, "FW_P_OPEN": Fireworks.P_OPEN,
		"FW_P_BODY": Fireworks.P_BODY, "FW_P_BUILD": Fireworks.P_BUILD, "FW_P_FINALE": Fireworks.P_FINALE,
		"FW_SPLIT": Fireworks.FW_SPLIT_S}
	var bad: Array = []
	for k in pairs:
		if not is_equal_approx(_const_f(src, k), float(pairs[k])):
			bad.append("%s %s vs %s" % [k, _const_f(src, k), pairs[k]])
	var lists := {"FW_TYPE_CUT": Fireworks.TYPE_CUT, "FW_FINALE_CUT": Fireworks.FINALE_CUT, "FW_LIFE": Fireworks.LIFE,
		"FW_V0": Fireworks.V0, "FW_DRAG": Fireworks.DRAG}
	for k in lists:
		var a := _const_list(src, k)
		var b: Array = lists[k]
		var same := a.size() == b.size()
		for i in mini(a.size(), b.size()):
			same = same and is_equal_approx(float(a[i]), float(b[i]))
		if not same:
			bad.append("%s %s vs %s" % [k, a, b])
	_t._check(bad.is_empty(), "fireworks: the shader include's plan numbers are Fireworks' %s" % [bad])
	var hv := [Fireworks.h32(0, 0), Fireworks.h32(12345, 7), Fireworks.h32(0xFFFFFFFF, 3), Fireworks.h32(2147483647, 1000)]
	_t._check(hv == [0, 121474188, 1134977167, 3013205916], "fireworks: the GDScript hash is the shader's 32-bit hash %s" % [hv])
	_t._check(src.contains("h *= 2246822519u;") and src.contains("h *= 3266489917u;") and src.contains("key * 747796405u + salt * 2891336453u"),
		"fireworks: the include hashes with the same multipliers")


## An act of a show: busier in the build and the finale, every type, breaks in the height band, and
## every shell (and its smoke) gone before its slot draws the next bin.
func _the_plan() -> void:
	var line := Vector2(0.0, 1.0)
	var per_phase := {"body": [0, 0], "finale": [0, 0]}
	var types := [0, 0, 0, 0, 0]
	var too_long: Array = []
	var off_band := 0
	var n := 0
	for b in Fireworks.ACT_BINS * 2:
		var sh := Fireworks.shell(98765, b, line, 200.0, 140.0, 290.0)
		var ph := b % Fireworks.ACT_BINS
		var key := "finale" if Fireworks.is_finale(b) else ("body" if ph >= Fireworks.OPEN_END and ph < Fireworks.BODY_END else "")
		if key != "":
			per_phase[key][1] += 1
		if sh.is_empty():
			continue
		n += 1
		if key != "":
			per_phase[key][0] += 1
		types[int(sh.type)] += 1
		var b0 := float(b) * Fireworks.BIN
		if float(sh.burst_t) + float(sh.life) - b0 >= Fireworks.SLOTS * Fireworks.BIN:
			too_long.append(b)
		if float(sh.burst_t) + Fireworks.SMOKE_LIFE - b0 >= Fireworks.SMOKE_SLOTS * Fireworks.BIN:
			too_long.append(-b)
		var h: float = Vector3(sh.burst).y
		if h < 140.0 or h > 290.0 or absf(Vector3(sh.off).z) > 101.0:
			off_band += 1
	var body: float = float(per_phase.body[0]) / maxf(per_phase.body[1], 1.0)
	var fin: float = float(per_phase.finale[0]) / maxf(per_phase.finale[1], 1.0)
	_t._check(n > 200 and fin > body + 0.3, "fireworks: an act launches a shell in %.0f %% of the body's bins and %.0f %% of the finale's (%d shells in two acts)" % [body * 100.0, fin * 100.0, n])
	_t._check(not types.has(0), "fireworks: every type turns up in two acts (peony, willow, crossette, strobe, ring: %s)" % [types])
	_t._check(too_long.is_empty(), "fireworks: every shell and its smoke are gone before their slot is reused %s" % [too_long.slice(0, 6)])
	_t._check(off_band == 0, "fireworks: every break is in the site's height band, every mortar on its launch line (%d not)" % off_band)
	var a := Fireworks.shell(98765, 40, line, 200.0, 140.0, 290.0)
	var b2 := Fireworks.shell(98765, 40, line, 200.0, 140.0, 290.0)
	var other := 0
	for b in 200:
		if Fireworks.shell(98765, b, line, 200.0, 140.0, 290.0).is_empty() != Fireworks.shell(4321, b, line, 200.0, 140.0, 290.0).is_empty():
			other += 1
	_t._check(a == b2 and other > 40, "fireworks: a show is the same twice from its seed and another seed is another show (%d of 200 bins differ)" % other)


## Some nights, not most; both sites roll on their own; the window and the night after midnight.
func _the_nights() -> void:
	for id in ["beach", "stadium"]:
		var on := 0
		for d in 400:
			if Fireworks.show_tonight(1337, d, id):
				on += 1
		var odds: float = Fireworks.ODDS[id]
		_t._check(absf(float(on) / 400.0 - odds) < 0.07, "fireworks: the %s has a show on %d of 400 nights (odds %.2f)" % [id, on, odds])
	var both := 0
	for d in 400:
		if Fireworks.show_tonight(1337, d, "beach") == Fireworks.show_tonight(1337, d, "stadium"):
			both += 1
	_t._check(both < 380, "fireworks: the beach and the ballpark roll their nights apart (%d of 400 agree)" % both)
	_t._check(Fireworks.window_level(12.0) == 0.0 and Fireworks.window_level(21.5) == 1.0 and Fireworks.window_level(Fireworks.START_HOUR + 0.02) > 0.0 \
		and Fireworks.window_level(Fireworks.START_HOUR + 0.02) < 1.0 and Fireworks.window_level(2.0) == 0.0,
		"fireworks: the show's window is the evening, fading in at its start")
	_t._check(Fireworks.night_of(5, 23.0) == 5 and Fireworks.night_of(5, 1.0) == 4, "fireworks: after midnight it is still the evening's night")
	_t._check(is_equal_approx(Fireworks.heard_at(10.0, 1715.0), 15.0), "fireworks: a break 1,715 m off is heard five seconds after it is seen")


## The barge is on open water off the pier, its breaks over the sea; the ballpark's beyond centre
## field.
func _the_sites(city: Node3D) -> void:
	var plan = city.get("plan")
	if plan == null:
		_t._check(false, "fireworks: the city has a plan")
		return
	var sites := Fireworks.plan_sites(plan)
	var ids: Array = []
	for s in sites:
		ids.append(s.id)
	_t._check(ids.has("beach") and (ids.has("stadium") or not Ballpark.enabled()), "fireworks: the sites are the beach and the ballpark %s" % [ids])
	for s in sites:
		var w: Vector3 = s.world
		if s.id == "beach":
			var wet := 0
			var tot := 0
			for b in 300:
				var sh := Fireworks.shell(777, b, s.line, s.spread, s.h_min, s.h_max)
				if sh.is_empty():
					continue
				tot += 1
				var p := Vector2(w.x, w.z) + Vector2(Vector3(sh.burst).x, Vector3(sh.burst).z)
				if int(plan.zone_at(p)) == int(MacroMap.Zone.OCEAN):
					wet += 1
			_t._check(int(plan.zone_at(Vector2(w.x, w.z))) == int(MacroMap.Zone.OCEAN) and float(s.shore_x) > 400.0 and float(s.shore_x) < 1200.0,
				"fireworks: the beach show's barge is on the sea, %.0f m off the waterline" % float(s.shore_x))
			_t._check(tot > 0 and wet == tot, "fireworks: every beach break is over the water (%d of %d)" % [wet, tot])
		else:
			var d := Vector2(w.x, w.z).distance_to(Ballpark.HOME)
			var along := Ballpark.local(Vector2(w.x, w.z)).y
			_t._check(d > 130.0 and d < 260.0 and along > 120.0, "fireworks: the ballpark's show goes up beyond centre field (%.0f m from home)" % d)


## The node in the city: a staged show is drawn, lit and heard; unstaged in the smoke test, off.
func _the_node(city: Node3D) -> void:
	var fw = city.get_node_or_null("Fireworks")
	_t._check(fw != null, "fireworks: city.tscn has the Fireworks node")
	if fw == null or not Fireworks.enabled():
		return
	await _t.get_tree().process_frame
	var s: Dictionary = fw.site("beach")
	_t._check(not s.is_empty(), "fireworks: the node built its beach site")
	if s.is_empty():
		return
	# Stage the show and hold it, then put its clock two tenths of a second after a peony breaks.
	fw.hold = true
	fw.staged["beach"] = 0.0
	s.active = false
	for i in 2:
		await _t.get_tree().process_frame
	var seed: int = int(s.seed)
	var t_at := -1.0
	for b in range(30, 300):
		var sh := Fireworks.shell(seed, b, s.line, s.spread, s.h_min, s.h_max)
		if not sh.is_empty() and int(sh.type) == Fireworks.Type.PEONY:
			t_at = float(sh.burst_t) + 0.2
			break
	s.clock = t_at
	for i in 2:
		await _t.get_tree().process_frame
	s = fw.site("beach")
	var root: Node3D = s.root
	var stars: ShaderMaterial = s.stars
	_t._check(s.active and root.visible and is_equal_approx(float(stars.get_shader_parameter("now")), t_at),
		"fireworks: a staged show is drawn at its clock (now %.2f)" % float(stars.get_shader_parameter("now")))
	var want := WorldState.to_local(s.world)
	_t._check(root.global_position.distance_to(want) < 0.5, "fireworks: the show stands at its true world place after the origin shifts")
	_t._check(float(s.energy) > 0.5, "fireworks: a break lights its show (level %.2f)" % float(s.energy))
	if s.light != null:
		var l: OmniLight3D = s.light
		_t._check(l.visible and l.light_energy > 0.5, "fireworks: the show's light is on while a shell breaks (%.2f)" % l.light_energy)
	var mesh: ArrayMesh = Fireworks.star_mesh()
	_t._check(mesh.surface_get_array_len(0) == Fireworks.SLOTS * (Fireworks.STARS + Fireworks.TRAIL) * 4,
		"fireworks: the star mesh is a quad per star and trail piece per slot")
	# The booms: a break 1 km from the ear is heard 2.9 s later, not before.
	var sh0: Dictionary = {}
	for b in range(30, 300):
		sh0 = Fireworks.shell(seed, b, s.line, s.spread, s.h_min, s.h_max)
		if not sh0.is_empty():
			break
	var bw: Vector3 = Vector3(s.world) + Vector3(sh0.burst)
	var ear := bw + Vector3(1000.0, -float(Vector3(sh0.burst).y), 0.0)
	var d := ear.distance_to(bw)
	var th := Fireworks.heard_at(float(sh0.burst_t), d)
	s.prev = float(sh0.burst_t)
	s.clock = float(sh0.burst_t) + 0.3
	fw._sounds(s, ear)
	var early: bool = fw.last_heard.has(int(sh0.bin))
	s.prev = th - 0.05
	s.clock = th + 0.05
	fw._sounds(s, ear)
	_t._check(not early and fw.last_heard.has(int(sh0.bin)), "fireworks: the boom is heard %.2f s after the break, not when it is seen" % (th - float(sh0.burst_t)))
	# Unstaged in the smoke test, the show goes.
	fw.staged.erase("beach")
	fw.hold = false
	await _t.get_tree().process_frame
	await _t.get_tree().process_frame
	_t._check(not fw.site("beach").active and not root.visible or Fireworks.forced(), "fireworks: with nothing staged the smoke test has no show")
