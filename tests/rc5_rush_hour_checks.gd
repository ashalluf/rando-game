extends RefCounted
## The rush_hour refcam (RushHour) for tests/smoke_test.gd. Loaded at run time.
## Checks: the level by the hour (0 at noon and night, 1 at the rushes' peak); the slots, the cap
## and the standing gap it scales, with the old numbers at level 0; the stop-and-go wave (slow
## bands, a smooth limit, running UPSTREAM against the traffic); slots 10 m apart at the peak; the
## A/B; the camera row. Pure: leans on nothing an earlier check left.

var _t: Node


func run(t: Node) -> void:
	_t = t
	_level()
	_scales()
	_wave()
	_look()
	_row()


func _level() -> void:
	_t._check(RushHour.enabled, "rush hour: on by default (RUSH_HOUR=0 is the A/B)")
	_t._check(RushHour.level(12.0) == 0.0 and RushHour.level(23.0) == 0.0 and RushHour.level(3.0) == 0.0,
		"rush hour: no jam at noon or at night")
	_t._check(is_equal_approx(RushHour.level(17.667), 1.0) and is_equal_approx(RushHour.level(8.0), 1.0),
		"rush hour: the evening (17:40) and morning (8:00) peaks are full (%.2f, %.2f)" % [RushHour.level(17.667), RushHour.level(8.0)])
	var mid := RushHour.level(16.0)
	_t._check(mid > 0.0 and mid < 1.0, "rush hour: it ramps in (16:00 %.2f)" % mid)
	RushHour.enabled = false
	var off := RushHour.level(17.667)
	RushHour.enabled = true
	_t._check(off == 0.0, "rush hour: the A/B never jams")


func _scales() -> void:
	_t._check(is_equal_approx(RushHour.gap(0.0), FreewayFill.LANE_GAP) and is_equal_approx(RushHour.cap_gain(0.0), FreewayFill.CAP_GAIN)
		and is_equal_approx(RushHour.stand_gap(20.4, 0.0), 20.4) and RushHour.wave_cap(26.0, 0.0, 0, 1, 500.0, 3.0) == INF,
		"rush hour: level 0 is the old slots, cap, standing gap and speed")
	_t._check(RushHour.gap(1.0) < 20.0 and RushHour.cap_gain(1.0) > FreewayFill.CAP_GAIN and RushHour.stand_gap(20.4, 1.0) < 10.0,
		"rush hour: the peak packs the lanes (slot %.0f m, cap x%.1f, standing gap %.1f m)" % [RushHour.gap(1.0), RushHour.cap_gain(1.0), RushHour.stand_gap(20.4, 1.0)])
	# Slots at the peak keep 10 m between a lane's cars; the default slots are unchanged.
	var g := RushHour.gap(1.0)
	var min_d := INF
	for slot in 60:
		min_d = minf(min_d, FreewayFill.slot_t(1, 1, 2, slot + 1, g) - FreewayFill.slot_t(1, 1, 2, slot, g))
	_t._check(min_d >= 9.99, "rush hour: a lane's jammed slots keep 10 m between centres (%.2f)" % min_d)
	_t._check(is_equal_approx(FreewayFill.slot_t(1, 1, 2, 7), FreewayFill.slot_t(1, 1, 2, 7, FreewayFill.LANE_GAP)),
		"rush hour: the default slot is the old one")


func _wave() -> void:
	var lo := INF
	var hi := 0.0
	var jump := 0.0
	var prev := -1.0
	for i in 2000:
		var v := RushHour.wave_cap(26.0, 1.0, 1, 1, float(i), 10.0)
		lo = minf(lo, v)
		hi = maxf(hi, v)
		if prev >= 0.0:
			jump = maxf(jump, absf(v - prev))
		prev = v
	_t._check(lo < 26.0 * 0.2 and hi < 26.0 * 0.7 and hi > lo * 3.0,
		"rush hour: the jam crawls in its slow bands (%.1f m/s) and moves between them (%.1f m/s)" % [lo, hi])
	_t._check(jump < 0.5, "rush hour: the limit is smooth along the road (%.2f m/s a metre at most)" % jump)
	# The slow band runs back up the traffic: what is at t after 10 s was at t + dir * 45 m at 0 s,
	# so the pattern moved 45 m against the direction of travel.
	var up := true
	for dir: int in [1, -1]:
		for t: float in [300.0, 1234.0, 2900.0]:
			var a := RushHour.wave_phase(2, dir, t, 10.0)
			var b := RushHour.wave_phase(2, dir, t + float(dir) * RushHour.WAVE_SPEED * 10.0, 0.0)
			var d := absf(a - b)
			up = up and minf(d, 1.0 - d) < 1e-4
	_t._check(up and RushHour.WAVE_SPEED > 0.0, "rush hour: the slow band runs upstream at %.1f m/s" % RushHour.WAVE_SPEED)


func _look() -> void:
	var lv := RushHour.now_level
	var vw := RushHour.now_view
	RushHour.now_level = 1.0
	RushHour.now_view = 1.0
	var on := RcRushHour.traffic_haze(1.0)
	var wet := RcRushHour.traffic_haze(0.0)
	RushHour.now_view = 0.0
	var away := RcRushHour.traffic_haze(1.0)
	RushHour.now_level = lv
	RushHour.now_view = vw
	_t._check(RcRushHour.enabled and on > 0.2 and wet == 0.0 and away == 0.0,
		"rush hour: the jam shimmers over the carriageway the camera looks down (%.2f), not in rain or looking away" % on)
	var mat := FreewayCloseup.deck_material()
	_t._check(float(mat.get_shader_parameter("patch_aged")) == 1.0
		and FileAccess.get_file_as_string("res://shaders/freeway_deck.gdshader").contains("uniform float patch_aged = 0.0;"),
		"rush hour: the deck's patches are aged (RC5_RUSH_LOOK=0 leaves the shader's old default)")


func _row() -> void:
	var f := FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json")
	var data: Variant = JSON.parse_string(f)
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in (data as Dictionary).get("cameras", []):
			if c.get("name", "") == "rush_hour":
				row = c
	_t._check(not row.is_empty() and absf(float(row.get("hour", 0.0)) - 17.667) < 0.01 and row.get("weather", "") == "clear",
		"rush hour: the camera row is in cameras_w8.json at 17:40 clear")
