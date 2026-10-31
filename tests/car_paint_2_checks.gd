extends RefCounted
## Car paint, second pass (CarPaint2 + the paint2 block of shaders/car_paint.gdshaderinc) for
## tests/smoke_test.gd. Loaded at run time, so it can name Vehicle and CarPaint2. Pure: builds no
## city part and moves nothing. Checks: random_car() spends the caller's rng exactly as before;
## with CAR_PAINT_2 off it turns out every car exactly as with the pass on, except the cars the
## hashes picked (only private paint, only the new paints and contrast roofs, at about their
## shares); the new enum values are appended; the shader carries the paint2 uniforms with 0
## defaults (the old path); a car's paint material gets them on, its contrast roof's line and its
## new finish's set, and nothing with the switch off; condition() is pure and in range.

var _t: Node


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var was := CarPaint2.enabled
	CarPaint2.enabled = true
	_enums()
	_rolls()
	_shader()
	_materials()
	_conditions()
	CarPaint2.enabled = was


func _enums() -> void:
	_check(Vehicle.Finish.MATTE == 4 and Vehicle.Finish.CANDY == 5 and Vehicle.Finish.TRICOAT == 6
		and Vehicle.Finish.SATIN == 7, "car paint 2: the new finishes are appended to Vehicle.Finish")
	_check(Vehicle.Livery.SERVICE == 5 and Vehicle.Livery.CONTRAST_ROOF == 6,
		"car paint 2: the contrast roof is appended to Vehicle.Livery")
	var ok := true
	for e: Array in CarPaint2.PAINTS_2:
		ok = ok and CarPaint2.FINISH_2.has(int(e[1])) and int(e[1]) >= Vehicle.Finish.CANDY
	for k in CarPaint2.ROOF_SHARE:
		ok = ok and CarPaint2.ROOF_LINE.has(k)
	_check(ok, "car paint 2: every new paint has a new finish's set, every roof body a roof line")


## Same seeds with the pass on and off: the rng is spent identically, and a car differs only where
## a hash picked it, only in its private paint, to a new paint or a contrast roof.
func _rolls() -> void:
	var same_state := true
	var stray := ""
	var new_paints := 0
	var roofs := 0
	var private := 0
	var roof_bodies := 0
	var n := 2500
	for s in n:
		var a := RandomNumberGenerator.new()
		a.seed = 72000 + s
		var b := RandomNumberGenerator.new()
		b.seed = 72000 + s
		CarPaint2.enabled = true
		var on := Vehicle.random_car(a)
		CarPaint2.enabled = false
		var off := Vehicle.random_car(b)
		CarPaint2.enabled = true
		same_state = same_state and a.state == b.state
		if on.body_type != off.body_type or on.addon != off.addon:
			stray = "seed %d: body or add-on moved" % s
		var is_private := Vehicle.PAINTS.has(off.paint) and off.body_type != Vehicle.BodyType.BEATER \
			and (off.livery == Vehicle.Livery.NONE or off.livery == Vehicle.Livery.RACING or off.livery == Vehicle.Livery.TWO_TONE)
		if is_private:
			private += 1
			if CarPaint2.ROOF_SHARE.has(int(off.body_type)) and off.livery == Vehicle.Livery.NONE:
				roof_bodies += 1
		var paint_moved := not on.paint.is_equal_approx(off.paint) or on.finish != off.finish
		if paint_moved:
			new_paints += 1
			if not is_private or on.finish < Vehicle.Finish.CANDY:
				stray = "seed %d: a non-private car or an old finish got a new paint" % s
		if on.livery != off.livery:
			roofs += 1
			if on.livery != Vehicle.Livery.CONTRAST_ROOF or off.livery != Vehicle.Livery.NONE or not is_private:
				stray = "seed %d: livery moved to something other than a contrast roof" % s
		if not paint_moved and on.livery == off.livery and not on.trim_color.is_equal_approx(off.trim_color):
			stray = "seed %d: trim moved on an unpicked car" % s
		on.free()
		off.free()
	_check(same_state, "car paint 2: random_car() spends the caller's rng exactly as before")
	_check(stray == "", "car paint 2: only picked private cars change, and only to new paints / roofs (%s)" % stray)
	var share := float(new_paints) / maxf(float(private), 1.0)
	_check(share > 0.06 and share < 0.2, "car paint 2: about a tenth of private cars wear a new paint (%.3f)" % share)
	var roof_share := float(roofs) / maxf(float(roof_bodies), 1.0)
	_check(roofs > 0 and roof_share > 0.08 and roof_share < 0.35,
		"car paint 2: contrast roofs on a share of the bodies that suit one (%d, %.3f)" % [roofs, roof_share])


func _shader() -> void:
	var sh: Shader = load("res://shaders/car_paint.gdshader")
	var want := {"paint2": 0.0, "peel": 0.0, "sparkle": 0.0, "candy_amount": 0.0, "wrap": 0.0,
		"oxidize": 0.0, "dust_film": 0.0, "skyline": 0.0}
	var found := 0
	for u: Dictionary in sh.get_shader_uniform_list():
		if want.has(u.name):
			found += 1
	_check(found == want.size(), "car paint 2: the shader has every paint2 uniform (%d / %d)" % [found, want.size()])
	var src := FileAccess.get_file_as_string("res://shaders/car_paint.gdshaderinc")
	var zero := true
	for k: String in want:
		zero = zero and src.contains("uniform float %s = 0.0;" % k)
	_check(zero, "car paint 2: every paint2 uniform defaults to 0 (the old path for every other material)")
	_check(src.contains("hint_range(0, 6)") and src.contains("stripe_mode == 6"),
		"car paint 2: the shader draws the contrast roof (stripe_mode 6)")


func _paint_of(car: Vehicle) -> ShaderMaterial:
	return car._paint_material(null, null)


func _materials() -> void:
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.CROSSOVER, Color(0.9, 0.9, 0.89), Vehicle.Addon.NONE)
	car.setup_look(Vehicle.Finish.METALLIC, Vehicle.Livery.CONTRAST_ROOF, CarPaint2.ROOF_DARK)
	var m := _paint_of(car)
	_check(float(m.get_shader_parameter("paint2")) == 1.0 and float(m.get_shader_parameter("skyline")) == 1.0
		and float(m.get_shader_parameter("sparkle")) > 0.0 and float(m.get_shader_parameter("peel")) > 0.0,
		"car paint 2: a metallic car's paint gets the pass (skyline, flake, orange peel)")
	_check(int(m.get_shader_parameter("stripe_mode")) == 6
		and is_equal_approx(float(m.get_shader_parameter("stripe_height")), float(CarPaint2.ROOF_LINE[Vehicle.BodyType.CROSSOVER])),
		"car paint 2: a contrast roof sets stripe_mode 6 at its body's roof line")
	CarPaint2.enabled = false
	var m0 := _paint_of(car)
	CarPaint2.enabled = true
	var p0: Variant = m0.get_shader_parameter("paint2")
	_check(p0 == null or float(p0) == 0.0, "car paint 2: with the switch off the material is the old one")
	car.free()
	var candy := Vehicle.new()
	candy.setup(Vehicle.BodyType.SEDAN, Color(0.7, 0.03, 0.04), Vehicle.Addon.NONE)
	candy.setup_look(Vehicle.Finish.CANDY)
	candy.paint_flip = Color(0.16, 0.0, 0.015, 1.0)
	var mc := _paint_of(candy)
	_check(float(mc.get_shader_parameter("candy_amount")) > 0.5 and float(mc.get_shader_parameter("clearcoat_amount")) == 1.0,
		"car paint 2: a candy car gets its tinted lacquer and its own finish set")
	candy.free()
	var wrapc := Vehicle.new()
	wrapc.setup(Vehicle.BodyType.SPORTS, Color(0.4, 0.41, 0.41), Vehicle.Addon.NONE)
	wrapc.setup_look(Vehicle.Finish.SATIN)
	var mw := _paint_of(wrapc)
	_check(float(mw.get_shader_parameter("wrap")) == 1.0 and float(mw.get_shader_parameter("clearcoat_amount")) == 0.0,
		"car paint 2: a satin wrap has no lacquer and the wrap's sheen")
	wrapc.free()


func _conditions() -> void:
	var dusty := 0
	var oxide := 0
	var pure := true
	var bounds := true
	var n := 4000
	for i in n:
		var col: Color = Vehicle.PAINTS[i % Vehicle.PAINTS.size()]
		var a := CarPaint2.condition(9100 + i, Vehicle.BodyType.SEDAN, col, Vehicle.Finish.GLOSS, Vehicle.Livery.NONE)
		var b := CarPaint2.condition(9100 + i, Vehicle.BodyType.SEDAN, col, Vehicle.Finish.GLOSS, Vehicle.Livery.NONE)
		pure = pure and a == b
		bounds = bounds and float(a[0]) >= 0.0 and float(a[0]) <= 0.5 and float(a[2]) >= 0.0 and float(a[2]) <= 1.0
		if float(a[0]) > 0.0:
			dusty += 1
		if float(a[2]) > 0.0:
			oxide += 1
	_check(pure and bounds, "car paint 2: a car's condition is pure and in range")
	_check(abs(float(dusty) / n - CarPaint2.DUST_SHARE) < 0.05 and abs(float(oxide) / n - CarPaint2.OXIDE_SHARE) < 0.04,
		"car paint 2: dust and oxidised paint at about their shares (%d, %d of %d)" % [dusty, oxide, n])
	var beat := CarPaint2.condition(5, Vehicle.BodyType.BEATER, Color(0.36, 0.09, 0.08), Vehicle.Finish.GLOSS, Vehicle.Livery.NONE)
	_check(float(beat[2]) >= 0.55, "car paint 2: the beater's paint is always oxidised")
	var fleet := CarPaint2.condition(5, Vehicle.BodyType.VAN, Vehicle.FLEET_PAINTS[2], Vehicle.Finish.GLOSS, Vehicle.Livery.DELIVERY)
	_check(float(fleet[2]) == 0.0, "car paint 2: no fleet livery oxidises")
