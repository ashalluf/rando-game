extends RefCounted
## HUD polish checks for tests/smoke_test.gd (docs/HANDOFF.md "HUD polish"): the shared theme
## (scale, safe area at 16:9 / 16:10 / 21:9 / 32:9, easing, the bundled type), the place toast
## (the street under the player, when a toast is due), the vehicle readout (an invented name for
## every body type, the units, the selector) and, in the city, the pieces on the HUD and inside
## its safe area. Loaded at run time, so it compiles after the autoloads; it puts back every
## static it forces and leaves no toast up.

var _t: Node
var _tree: SceneTree


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_theme()
	_vehicle_names()
	_toast_rules(city)
	await _scene(city)


func _theme() -> void:
	var saved := GameSettings.hud_scale
	GameSettings.hud_scale = 1.0
	_check(is_equal_approx(HudTheme.scale(Vector2(1920, 1080)), 1.0) and is_equal_approx(HudTheme.scale(Vector2(2560, 1600)), 1600.0 / 1080.0),
		"the HUD is laid out in 1080-line units (1 at 1080, %.2f at 1600)" % HudTheme.scale(Vector2(2560, 1600)))
	for v: Vector2 in [Vector2(1920, 1080), Vector2(2560, 1600), Vector2(1280, 800)]:
		var r := HudTheme.safe_rect(v)
		var m := HudTheme.MARGIN * HudTheme.scale(v)
		_check(is_equal_approx(r.position.x, m) and is_equal_approx(r.end.x, v.x - m) and is_equal_approx(r.end.y, v.y - m),
			"at %dx%d the safe area is the whole window less the margin" % [int(v.x), int(v.y)])
	for v: Vector2 in [Vector2(3440, 1440), Vector2(5120, 1440)]:
		var r := HudTheme.safe_rect(v)
		var band := r.size.x + 2.0 * HudTheme.MARGIN * HudTheme.scale(v)
		_check(band <= v.y * HudTheme.MAX_ASPECT + 0.5 and absf(r.get_center().x - v.x * 0.5) < 0.5,
			"at %dx%d the HUD keeps to a centred 21:9 band (%d px)" % [int(v.x), int(v.y), int(band)])
	_check(HudTheme.band_inset(Vector2(1920, 1080)) == 0.0 and HudTheme.band_inset(Vector2(5120, 1440)) > 800.0,
		"only a window wider than 21:9 is inset")
	GameSettings.hud_scale = saved
	_check(is_equal_approx(HudTheme.envelope(0.0, 0.5, 2.0, 0.5), 0.0) and is_equal_approx(HudTheme.envelope(1.0, 0.5, 2.0, 0.5), 1.0)
		and HudTheme.envelope(3.2, 0.5, 2.0, 0.5) < 0.01 and HudTheme.envelope(0.25, 0.5, 2.0, 0.5) > 0.5,
		"a toast eases in, holds and eases out")
	var mono := true
	var last := -1.0
	for i in 21:
		var e := HudTheme.ease_in_out(float(i) / 20.0)
		mono = mono and e >= last
		last = e
	_check(mono and is_equal_approx(HudTheme.ease_out(1.0), 1.0) and is_equal_approx(HudTheme.ease_back(1.0), 1.0),
		"the easing curves rise and land on 1")
	for p in [HudTheme.FONT_DISPLAY, HudTheme.FONT_DISPLAY_BOLD, HudTheme.FONT_TEXT, HudTheme.FONT_TEXT_MEDIUM]:
		var f := HudTheme.font(p)
		_check(ResourceLoader.exists(p) and f != null and f != ThemeDB.fallback_font, "the HUD's type is bundled: %s" % p.get_file())


## Every body type has an invented maker and model; none is a real one.
func _vehicle_names() -> void:
	_check(VehicleHud.MODELS.size() == Vehicle.BodyType.size(),
		"every body type has a model name (%d of %d)" % [VehicleHud.MODELS.size(), Vehicle.BodyType.size()])
	var seen := {}
	var ok := true
	for row: Array in VehicleHud.MODELS:
		var full := "%s %s" % [row[0], row[1]]
		ok = ok and row.size() == 3 and str(row[2]) != "" and str(row[0]) != "" and str(row[1]) != "" and not seen.has(full)
		seen[full] = true
	_check(ok, "model names are filled in and unique")
	# Never a real maker (a list of the ones a player would know; the names are invented).
	var real := ["ford", "chevrolet", "chevy", "toyota", "honda", "nissan", "dodge", "jeep", "tesla", "bmw", "audi",
		"mercedes", "porsche", "ferrari", "lamborghini", "kia", "hyundai", "mazda", "subaru", "lexus", "cadillac",
		"lincoln", "buick", "gmc", "ram", "volkswagen", "volvo", "harley", "ducati", "yamaha", "kawasaki",
		"suzuki", "vespa", "peterbilt", "kenworth", "freightliner", "mack", "navistar", "bugatti", "mclaren"]
	var clean := true
	for row: Array in VehicleHud.MODELS:
		for word in ("%s %s" % [row[0], row[1]]).to_lower().split(" "):
			if real.has(word):
				clean = false
				_check(false, "a real maker in the vehicle names: %s" % word)
	_check(clean, "no real maker's name in the vehicle names")
	var n := VehicleHud.names_for_type(Vehicle.BodyType.SEDAN)
	_check(n.size() == 3 and n[2] == "SEDAN" and n[1] != "", "a sedan reads %s %s (%s)" % [n[0], n[1], n[2]])
	var r: Array = VehicleHud.speed_reading(null, 26.8224)
	_check(int(r[0]) == 60 and r[1] == "MPH", "60 mph reads 60 MPH (%s %s)" % [str(r[0]), str(r[1])])
	_check(VehicleHud.gear_letter(5.0) == "D" and VehicleHud.gear_letter(-3.0) == "R" and VehicleHud.gear_letter(0.1) == "N",
		"the selector reads D forward, R backing, N standing")


## The street under the player and when a toast is due.
func _toast_rules(city: Node3D) -> void:
	var plan: CityPlan = city.get("plan")
	_check(AreaToast.next_toast("", "", "Downtown", "Flower St", 0.0, 7.0) == AreaToast.Kind.DISTRICT,
		"coming into a district shows it")
	_check(AreaToast.next_toast("Downtown", "Flower St", "Downtown", "Hope St", 2.0, 7.0) == AreaToast.Kind.NONE
		and AreaToast.next_toast("Downtown", "Flower St", "Downtown", "Hope St", 8.0, 7.0) == AreaToast.Kind.STREET,
		"a new street in the same district waits its gap, then shows alone")
	_check(AreaToast.next_toast("Downtown", "Flower St", "Downtown", "", 20.0, 7.0) == AreaToast.Kind.NONE,
		"leaving the grid for a block's middle shows nothing")
	if plan == null:
		_check(false, "the city has a plan")
		return
	# A road's centre line, half-way along a block: that road's name.
	var bi := plan.block_index_at(Vector2(30.0, 30.0))
	var x := plan.road_pos(CityPlan.AXIS_X, bi.x)
	var z := (plan.road_pos(CityPlan.AXIS_Z, bi.y) + plan.road_pos(CityPlan.AXIS_Z, bi.y + 1)) * 0.5
	var want := plan.road_name(CityPlan.AXIS_X, bi.x)
	var got := AreaToast.street_at(plan, Vector2(x, z))
	_check(got == want and got != "", "on a road the toast names it (%s)" % got)
	var b: Dictionary = plan.block(bi.x, bi.y)
	var rect: Rect2 = b.rect
	if rect.size.x > 40.0 and rect.size.y > 40.0:
		_check(AreaToast.street_at(plan, rect.get_center()) == "", "in a block's middle there is no street")


func _scene(city: Node3D) -> void:
	var hud: Node = city.get_node_or_null("DebugHud")
	if hud == null:
		_check(false, "the city has its HUD")
		return
	var toast := hud.get_node_or_null("AreaToast") as AreaToast
	var car_hud := hud.get_node_or_null("VehicleHud") as VehicleHud
	_check((toast != null) == AreaToast.enabled and (car_hud != null) == VehicleHud.enabled,
		"the HUD has the place toast and the vehicle readout (AREA_TOAST / VEHICLE_HUD switches)")
	var view: Vector2 = (hud.get_node("MinimapFrame") as Control).get_viewport_rect().size
	var safe := HudTheme.safe_rect(view)
	var frame := hud.get_node_or_null("MinimapFrame") as Control
	if frame:
		frame.call("layout")
		var mr: Rect2 = frame.call("screen_rect")
		_check(absf(mr.end.x - safe.end.x) < 1.0 and absf(mr.end.y - safe.end.y) < 1.0,
			"the minimap's corner is the safe area's corner (%s in %s; the headless view is small)" % [str(mr), str(safe)])
	var weapon := hud.get_node_or_null("WeaponHud")
	if weapon:
		weapon.call("_layout")
		var wr: Rect2 = weapon.call("panel_rect")
		_check(absf(wr.end.x - safe.end.x) < 1.0 and absf(wr.position.y - safe.position.y) < 1.0,
			"the weapon panel sits in the safe area's top right (%s)" % str(wr))
	if toast:
		toast.show_now("Testville", "Check St", true)
		toast.queue_redraw()
		await _tree.process_frame
		_check(is_equal_approx(toast.amount(), 1.0) and toast.shown_district == "Testville", "a toast shows on demand")
		toast.show_now("", "", false)
		toast.kind = AreaToast.Kind.NONE
		toast.shown_district = ""
		_check(toast.amount() == 0.0, "the toast is put away again")
	if car_hud:
		var saved_type := VehicleHud.forced_type
		var saved_mph := VehicleHud.forced_mph
		VehicleHud.forced_type = Vehicle.BodyType.CROSSOVER
		VehicleHud.forced_mph = 42.0
		var was_visible: bool = hud.visible
		hud.visible = true
		for i in 240:
			await _tree.process_frame
			if float(car_hud.get("_pill")) >= 1.0:
				break
		var pill: Rect2 = car_hud.pill_rect()
		var glass := car_hud.get_node_or_null("SpeedGlass") as Control
		_check(glass != null and glass.visible and pill.size.y > 0.0 and car_hud.toast_amount() == 1.0,
			"a car's speed pill shows (%s)" % str(pill))
		if frame:
			var mr2: Rect2 = frame.call("screen_rect")
			_check(pill.end.x <= mr2.position.x and absf(pill.end.y - mr2.end.y) < 1.0, "the pill stands left of the minimap, its bottom on the minimap's")
		VehicleHud.forced_type = saved_type
		VehicleHud.forced_mph = saved_mph
		car_hud.set("_model", "")
		car_hud.set("_car", null)
		hud.visible = was_visible
