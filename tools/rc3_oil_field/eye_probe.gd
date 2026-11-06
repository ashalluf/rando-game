extends Node
## Finds refcam eyes for the oil field: points on the lease roads looking toward downtown with the
## most pumpjacks in a 50-degree cone 12-90 m out. Headless, seconds:
##   godot --headless --path . res://tools/rc3_oil_field/eye_probe.tscn
func _ready() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var f: OilField = macro.oil
	var target := Vector2(2800, 100)
	var ws := f.wells()
	var best: Array = []
	for ri in f.roads.size():
		var pts: PackedVector2Array = f.roads[ri].pts
		var hs: PackedFloat32Array = f.roads[ri].h
		for i in range(0, pts.size(), 2):
			var p := pts[i]
			var d := (target - p).normalized()
			var n := 0
			var near := 0.0
			for w: Dictionary in ws:
				var v: Vector2 = (w.p as Vector2) - p
				var l := v.length()
				if l < 12.0 or l > 90.0:
					continue
				if v.normalized().dot(d) > cos(deg_to_rad(25.0)):
					n += 1
					if l < 35.0:
						near += 1.0
			var score := float(n) + near * 1.5 + (hs[i] - f.base_h) * 0.05
			best.append([score, p, hs[i], rad_to_deg(atan2(-d.x, -d.y)), n, near, ri])
	best.sort_custom(func(a, b): return a[0] > b[0])
	for k in mini(15, best.size()):
		var b: Array = best[k]
		print("score=%.1f road=%d at %s h=%.1f (base %.1f) yaw=%.1f wells=%d near=%d" % [b[0], b[6], b[1], b[2], f.base_h, b[3], b[4], b[5]])
	get_tree().quit()
