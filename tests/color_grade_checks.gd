extends RefCounted
## The per-hour grade (HourGrade, scripts/world/hour_grade.gd) for tests/smoke_test.gd. Checks:
## DayNight made it and the Environment wears its curve; the weights are zero at noon and each look
## owns its hour (golden hour, the blue hour, night, the weather); every look's curve rises, keeps
## black near black and white near white; the looks do what they are for (night's toe deeper than
## the old single curve's and no redder or bluer than green - the lavender cast -, golden hour warmer, the blue
## hour cooler, the marine layer greyer and flatter); the live curve follows the clock; and a curve
## that is not ours (photo mode's filter) is left alone.

const HG := preload("res://scripts/world/hour_grade.gd")

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var day: Node = city.get_node_or_null("DayNight")
	if day == null:
		_t._check(false, "grade: the city has a DayNight")
		return
	if not HG.enabled:
		_t._check(day.get("grade") == null, "grade: HOUR_GRADE=0 leaves the scene's single curve")
		return
	var grade: RefCounted = day.get("grade")
	_t._check(grade != null and grade.is_active(), "grade: DayNight made its HourGrade")
	if grade == null:
		return
	var we := day.get_node_or_null(day.get("environment_path")) as WorldEnvironment
	var env: Environment = we.environment if we else null
	_t._check(env != null and env.adjustment_color_correction == grade.get("_tex"),
		"grade: the Environment wears the per-hour curve")
	_weights()
	_curves(grade)
	if env:
		_live(day, grade, env)


func _weights() -> void:
	var noon: Dictionary = HG.weights(1.0, 0.0, 0.0, 0.0, 0.0)
	var none := true
	for k in noon:
		none = none and float(noon[k]) == 0.0
	_t._check(none, "grade: noon is the day look alone")
	var gold: Dictionary = HG.weights(0.15, 1.0, 0.0, 0.0, 0.0)
	_t._check(float(gold[HG.Look.GOLDEN]) > 0.99 and float(gold[HG.Look.NIGHT]) == 0.0,
		"grade: golden hour is the golden look")
	var blue: Dictionary = HG.weights(-0.07, 0.0, 0.0, 0.0, 0.0)
	_t._check(float(blue[HG.Look.BLUE]) > 0.9, "grade: the sun 4 degrees down is the blue hour (%.2f)" % float(blue[HG.Look.BLUE]))
	var night: Dictionary = HG.weights(-0.6, 0.0, 0.0, 0.0, 0.0)
	_t._check(float(night[HG.Look.NIGHT]) > 0.99 and float(night[HG.Look.BLUE]) == 0.0,
		"grade: midnight is the night look")
	var gloom: Dictionary = HG.weights(0.6, 0.0, 0.0, 1.0, 0.0)
	_t._check(float(gloom[HG.Look.MARINE]) > 0.99, "grade: under the marine layer is the marine look")


func _curves(grade: RefCounted) -> void:
	var base: Gradient = grade.get("_base")
	var rises := true
	var ends := true
	for look in HG.LOOKS:
		var g: Gradient = HG.gradient_for(base, HG.LOOKS[look])
		var prev := Color(-1, -1, -1)
		for i in 65:
			var c := g.sample(i / 64.0)
			rises = rises and c.r >= prev.r - 0.002 and c.g >= prev.g - 0.002 and c.b >= prev.b - 0.002
			prev = c
		var lo := g.sample(0.0)
		var hi := g.sample(1.0)
		ends = ends and maxf(lo.r, maxf(lo.g, lo.b)) < 0.06 and minf(hi.r, minf(hi.g, hi.b)) > 0.85
	_t._check(rises, "grade: every look's curve rises in every channel")
	_t._check(ends, "grade: every look keeps black black and white white")
	var day_g: Gradient = HG.gradient_for(base, HG.LOOKS[HG.Look.DAY])
	var night_g: Gradient = HG.gradient_for(base, HG.LOOKS[HG.Look.NIGHT])
	# Night's toe against the old single curve's (the base): the blacks go deeper.
	var b0 := base.sample(0.05)
	var n0 := night_g.sample(0.05)
	_t._check(n0.g < b0.g * 0.8, "grade: night's blacks are deeper than the old curve's (%.3f < %.3f)" % [n0.g, b0.g])
	var d := day_g.sample(0.15)
	var n := night_g.sample(0.15)
	var lav_day := (d.r + d.b) * 0.5 - d.g
	var lav_night := (n.r + n.b) * 0.5 - n.g
	_t._check(lav_night <= lav_day + 0.001, "grade: night's shadows lean no more lavender than the day's")
	var gold_g: Gradient = HG.gradient_for(base, HG.LOOKS[HG.Look.GOLDEN])
	var dm := day_g.sample(0.6)
	var gm := gold_g.sample(0.6)
	_t._check(gm.r - gm.b > dm.r - dm.b + 0.03, "grade: golden hour is warmer than noon")
	var blue_g: Gradient = HG.gradient_for(base, HG.LOOKS[HG.Look.BLUE])
	var bs := blue_g.sample(0.3)
	var ds := day_g.sample(0.3)
	_t._check(bs.b - bs.r > ds.b - ds.r + 0.02, "grade: the blue hour is cooler than noon")
	var marine: Dictionary = HG.LOOKS[HG.Look.MARINE]
	var day_l: Dictionary = HG.LOOKS[HG.Look.DAY]
	_t._check(float(marine["sat"]) < float(day_l["sat"]) - 0.1 and float(marine["contrast"]) < float(day_l["contrast"]),
		"grade: the marine layer is greyer and flatter than a clear day")


func _live(day: Node, grade: RefCounted, env: Environment) -> void:
	var hour: float = day.get("hour")
	day.set("hour", 12.0)
	day.call("_apply")
	var noon_sat := env.adjustment_saturation
	var noon_lo := (env.adjustment_color_correction as GradientTexture1D).gradient.sample(0.15)
	day.set("hour", 23.5)
	day.call("_apply")
	var night_sat := env.adjustment_saturation
	var night_lo := (env.adjustment_color_correction as GradientTexture1D).gradient.sample(0.15)
	_t._check(night_sat < noon_sat and night_lo.g < noon_lo.g,
		"grade: the live curve follows the clock (sat %.2f -> %.2f)" % [noon_sat, night_sat])
	# A curve that is not ours (photo mode's filter) is left alone.
	var mine := env.adjustment_color_correction
	var other := GradientTexture1D.new()
	other.gradient = Gradient.new()
	env.adjustment_color_correction = other
	env.adjustment_saturation = 0.5
	day.set("hour", 12.0)
	day.call("_apply")
	_t._check(env.adjustment_saturation == 0.5 and env.adjustment_color_correction == other,
		"grade: photo mode's filter is left alone")
	env.adjustment_color_correction = mine
	day.set("hour", hour)
	day.call("_apply")
