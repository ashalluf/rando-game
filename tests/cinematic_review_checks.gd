extends RefCounted
## The cinematic review (docs/HANDOFF.md "The cinematic review") for tests/smoke_test.gd: pins the
## numbers the art-direction pass tuned against the ten reference cameras, so none of them is
## reverted silently - the per-hour grade's looks (HourGrade.LOOKS: saturation, contrast, the
## broad `depth` term, split toning, the golden-hour mids, the night's blue pulled out), DayNight's
## exposures, night bloom and night ambient / fog, and the clear-day haze (Weather.fog_by_state).
## Also checks that the depth term does what it says (darkens the lower mids, leaves black and
## white) and that the live Environment follows: day bloom at noon, night bloom at midnight.
## Stages its own clock and weather on the city's DayNight and puts them back.

const HG := preload("res://scripts/world/hour_grade.gd")

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_looks()
	_depth()
	var day: Node = city.get_node_or_null("DayNight")
	_t._check(day != null, "cinematic: the city has a DayNight")
	if day == null:
		return
	_daynight(day)
	var wx: Node = city.get_node_or_null("Weather")
	if wx:
		var fog: PackedFloat32Array = wx.get("fog_by_state")
		_t._check(fog.size() > 0 and fog[0] >= 0.00007 and fog[0] <= 0.000095,
			"cinematic: the clear-day haze is thinner than 0.0001 (%.6f)" % (fog[0] if fog.size() > 0 else -1.0))
	_live(day)


func _looks() -> void:
	var every := true
	for look in HG.LOOKS:
		every = every and (HG.LOOKS[look] as Dictionary).has("depth")
	_t._check(every, "cinematic: every look carries a depth term")
	var d: Dictionary = HG.LOOKS[HG.Look.DAY]
	_t._check(float(d["sat"]) >= 1.36 and float(d["sat"]) <= 1.5 and float(d["contrast"]) >= 0.26
		and float(d["contrast"]) <= 0.36 and float(d["depth"]) <= -0.15 and float(d["depth"]) >= -0.35,
		"cinematic: the day look is rich and firm (sat %.2f, contrast %.2f, depth %.2f)" % [d["sat"], d["contrast"], d["depth"]])
	var dg: Vector3 = d["gamma"]
	var dh: Vector3 = d["high"]
	var ds: Vector3 = d["shadow"]
	_t._check(dg.x < 0.96 and dg.z > dg.x and dh.x > dh.z and ds.z > ds.x,
		"cinematic: the day look holds its mids and splits warm highlights over cooler shadows")
	var g: Dictionary = HG.LOOKS[HG.Look.GOLDEN]
	var gg: Vector3 = g["gamma"]
	_t._check(float(g["sat"]) >= 1.42 and gg.x <= 0.88 and gg.x < gg.z,
		"cinematic: golden hour's mids glow warm (sat %.2f, red gamma %.2f)" % [g["sat"], gg.x])
	var n: Dictionary = HG.LOOKS[HG.Look.NIGHT]
	var ng: Vector3 = n["gamma"]
	_t._check(float(n["sat"]) >= 1.18 and float(n["sat"]) <= 1.3 and ng.z > ng.y + 0.03,
		"cinematic: the night look pulls the blue out of the mids (blue gamma %.2f)" % ng.z)
	var s: Dictionary = HG.LOOKS[HG.Look.SANTA_ANA]
	_t._check(float(s["sat"]) >= float(d["sat"]) and float(s["contrast"]) >= float(d["contrast"]),
		"cinematic: a Santa Ana day is at least as crisp as a clear one")


func _depth() -> void:
	var lo_plain := HG.channel(0.25, 1.0, 0.0, 0.0, 0.0)
	var lo_deep := HG.channel(0.25, 1.0, 0.0, 0.0, 0.0, -0.25)
	var hi_deep := HG.channel(0.95, 1.0, 0.0, 0.0, 0.0, -0.25)
	_t._check(lo_deep < lo_plain - 0.02 and hi_deep > 0.94 and HG.channel(0.0, 1.0, 0.0, 0.0, 0.0, -0.25) == 0.0,
		"cinematic: depth darkens the lower mids and keeps black and white (%.3f -> %.3f)" % [lo_plain, lo_deep])
	_t._check(is_equal_approx(HG.channel(0.4, 1.1, -0.2, 0.2, 0.01), HG.channel(0.4, 1.1, -0.2, 0.2, 0.01, 0.0)),
		"cinematic: a look without depth is the curve it always was")


func _daynight(day: Node) -> void:
	var de: float = day.get("day_exposure")
	var ne: float = day.get("night_exposure")
	_t._check(de >= 1.12 and de <= 1.22 and ne >= 2.2 and ne <= 2.45,
		"cinematic: exposure %.2f by day, %.2f at night" % [de, ne])
	var dgi: float = day.get("day_glow_intensity")
	var ngi: float = day.get("night_glow_intensity")
	var dgt: float = day.get("day_glow_threshold")
	var ngt: float = day.get("night_glow_threshold")
	_t._check(ngi > dgi + 0.2 and ngt < dgt - 0.2 and ngt >= 0.6,
		"cinematic: lamps bloom more after dark (glow %.2f / %.2f, threshold %.2f / %.2f)" % [dgi, ngi, dgt, ngt])
	var amb: Color = day.get("night_ambient")
	var fog: Color = day.get("night_fog")
	_t._check(amb.b - amb.r <= 0.22 and fog.b - fog.r <= 0.06,
		"cinematic: the night fill and haze are cool, not navy")


func _live(day: Node) -> void:
	var we := day.get_node_or_null(day.get("environment_path")) as WorldEnvironment
	var env: Environment = we.environment if we else null
	if env == null:
		_t._check(false, "cinematic: DayNight has its Environment")
		return
	var hour: float = day.get("hour")
	var held := {"weather_darken": day.get("weather_darken"), "marine": day.get("marine"), "santa_ana": day.get("santa_ana")}
	for k in held:
		day.set(k, 0.0)
	day.set("hour", 12.0)
	day.call("_apply")
	var noon_glow := env.glow_intensity
	var noon_thr := env.glow_hdr_threshold
	var noon_exp := env.tonemap_exposure
	day.set("hour", 0.5)
	day.call("_apply")
	_t._check(is_equal_approx(noon_glow, float(day.get("day_glow_intensity"))) and is_equal_approx(noon_exp, float(day.get("day_exposure")))
		and is_equal_approx(env.glow_intensity, float(day.get("night_glow_intensity")))
		and env.glow_hdr_threshold < noon_thr,
		"cinematic: the Environment's bloom and exposure follow the clock (glow %.2f -> %.2f)" % [noon_glow, env.glow_intensity])
	for k in held:
		day.set(k, held[k])
	day.set("hour", hour)
	day.call("_apply")
