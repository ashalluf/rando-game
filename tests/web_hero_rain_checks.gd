extends RefCounted
## The sky's radiance catches up with a jump (docs/HANDOFF.md "The hero in the rain on the web",
## SkySettle) for tests/smoke_test.gd:
## - DayNight carries a SkySettle, and the city's sky is back at its own process mode (INCREMENTAL)
##   once the start-up frames are past - QUALITY every frame would refilter the radiance every frame.
## - A jump in the hour or the weather holds the sky at QUALITY for a few frames and then puts the
##   mode back; an ordinary frame of the day's drift does not.
## Stages the hour and the weather on the city's DayNight / Weather and puts them back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var day: Node = city.get_node_or_null("DayNight")
	var settle := day.get_node_or_null("SkySettle") if day else null
	_t._check(settle != null, "sky settle: DayNight has a SkySettle")
	if settle == null:
		return
	var env := (city.get_node("WorldEnvironment") as WorldEnvironment).environment
	var own: int = settle.get("_mode")
	_t._check(own == Sky.PROCESS_MODE_INCREMENTAL,
		"sky settle: the city's sky is incremental by its own setting (%d)" % own)
	for i in 12:
		await _t.get_tree().process_frame
	_t._check(env.sky.process_mode == own and not settle.get("_held"),
		"sky settle: the sky is back at its own mode after the start-up frames (%d)" % env.sky.process_mode)
	# The day's own drift is no jump.
	var before: int = settle.get("settles")
	for i in 6:
		await _t.get_tree().process_frame
	_t._check(int(settle.get("settles")) == before and env.sky.process_mode == own,
		"sky settle: an ordinary frame does not refilter the sky")
	# An hour jump (the pause menu's presets) holds QUALITY, then lets go.
	var hour: float = day.get("hour")
	day.set("hour", fmod(hour + 6.0, 24.0))
	day.call("_apply")
	await _t.get_tree().process_frame
	await _t.get_tree().process_frame
	_t._check(env.sky.process_mode == Sky.PROCESS_MODE_QUALITY and int(settle.get("settles")) == before + 1,
		"sky settle: an hour jump holds the sky at QUALITY (mode %d)" % env.sky.process_mode)
	for i in int(settle.get("hold_frames")) + 3:
		await _t.get_tree().process_frame
	_t._check(env.sky.process_mode == own, "sky settle: the mode is put back after the hold")
	day.set("hour", hour)
	day.call("_apply")
	# A weather snap (force_state) does the same.
	var wx: Node = city.get_node_or_null("Weather")
	if wx:
		for i in int(settle.get("hold_frames")) + 3:
			await _t.get_tree().process_frame
		var n: int = settle.get("settles")
		var was: int = wx.get("state")
		wx.call("force_state", 3 if was != 3 else 0)
		await _t.get_tree().process_frame
		await _t.get_tree().process_frame
		_t._check(int(settle.get("settles")) > n, "sky settle: a forced weather snap refilters the sky")
		wx.call("force_state", was)
		wx.call("force_state", -1)
		for i in int(settle.get("hold_frames")) + 3:
			await _t.get_tree().process_frame
		_t._check(env.sky.process_mode == own, "sky settle: the mode is back after the weather snap")
	_t._check(SkySettle.enabled(), "sky settle: on unless SKY_SETTLE=0")
