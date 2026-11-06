extends Node
## Footbridges probe: every bridge in a square round a point (or round the map's middle), with its
## kind, form, span, heights, risers and EYE lines for tools/glshot/still_shot.gd. Headless, seconds:
##   godot --headless --path . res://tools/footbridges/probe.tscn   (SEED=n, AT=x,z, RADIUS=m)
func _ready() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	print("setup ms=", Time.get_ticks_msec() - t0)
	var at := Vector2(1500.0, 800.0)
	if OS.get_environment("AT") != "":
		var p := OS.get_environment("AT").split(",")
		at = Vector2(float(p[0]), float(p[1]))
	var radius := float(OS.get_environment("RADIUS")) if OS.get_environment("RADIUS") != "" else 3500.0
	t0 = Time.get_ticks_msec()
	var all := Footbridges.near(plan, Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))
	print("near ms=", Time.get_ticks_msec() - t0, " bridges=", all.size())
	var kinds := [0, 0]
	for b: Dictionary in all:
		kinds[int(b.kind)] += 1
		var c: Vector2 = b.c
		var dir: Vector2 = b.dir
		var along: Vector2 = b.along
		var span := float(b.half) * 2.0
		var flights := 0
		var risers := 0
		for e: Dictionary in b.ends:
			for f: Dictionary in (e.stair as Dictionary).flights:
				flights += 1
				risers += int(f.n)
		# An eye off to the side along the road / route, looking at the span from a pavement / the ground.
		var eye := c + along * 34.0 + dir * (float(b.half) + 6.0)
		var d := c - eye
		var yaw := rad_to_deg(atan2(-d.x, -d.y))
		var g := CityChunk.SIDEWALK_TOP + macro.relief_at(eye)
		var pitch := rad_to_deg(atan2(float(b.y) - 2.0 - g - 1.7, d.length()))
		print("%s kind=%s form=%s c=(%.1f,%.1f) span=%.1f y=%.2f ground=%.2f flights=%d risers=%d paint=%s EYE=%.1f,%.1f,%.1f,%.1f,%.1f" % [
			b.id, ["BOULEVARD", "FREEWAY"][int(b.kind)], ["TRUSS", "GIRDER"][int(b.form)], c.x, c.y, span, b.y,
			float((b.ends[0] as Dictionary).ground), flights, risers, (b.paint as Color).to_html(false),
			eye.x, g + 1.7, eye.y, yaw, pitch])
		if int(b.kind) == Footbridges.Kind.FREEWAY:
			# From the deck: a car's driver 70 m short of it in the second lane.
			var dp := c - along * 70.0 * float(b.sgn) - dir * 6.0
			var dd := c - dp
			print("   DECK EYE=%.1f,%.1f,%.1f,%.1f,%.1f" % [dp.x, float(b.deck) + 1.4, dp.y, rad_to_deg(atan2(-dd.x, -dd.y)), rad_to_deg(atan2(float(b.y) - float(b.deck) - 1.4, dd.length()))])
		else:
			# From the pavement under it, looking up the stair.
			var e0: Dictionary = b.ends[0]
			var foot: Vector2 = e0.stair.foot
			var pp := foot + along * 6.0 * float(b.sgn) - dir * 1.5
			var dd := (e0.p as Vector2) - pp
			print("   STAIR EYE=%.1f,%.1f,%.1f,%.1f,%.1f" % [pp.x, float(e0.ground) + 1.7, pp.y, rad_to_deg(atan2(-dd.x, -dd.y)), rad_to_deg(atan2(float(b.y) - float(e0.ground) - 1.7, dd.length()))])
	print("boulevard=%d freeway=%d" % kinds)
	print("rejects ", Footbridges.rejects)
	get_tree().quit()
