extends Node
## Oil field siting probe: an ASCII map of the basin at STEP metres. Headless, seconds:
##   godot --headless --path . --script tools/oil_field/map_probe.gd   (X0,Z0,X1,Z1,STEP env)
func _ready() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = macro
	var x0 := float(OS.get_environment("X0")) if OS.get_environment("X0") != "" else -800.0
	var z0 := float(OS.get_environment("Z0")) if OS.get_environment("Z0") != "" else -1200.0
	var x1 := float(OS.get_environment("X1")) if OS.get_environment("X1") != "" else 3400.0
	var z1 := float(OS.get_environment("Z1")) if OS.get_environment("Z1") != "" else 4200.0
	var st := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 100.0
	var rz := macro.runway_clear_zone()
	print("legend: F freeway, A airport, ~ water/beach, ^ hills, R river, P port, C clear zone, L landmark, S site, D downtown, m midtown, s suburbs, i industrial, c campus, b beachtown")
	var z := z0
	while z <= z1:
		var row := "%6.0f " % z
		var x := x0
		while x <= x1:
			var p := Vector2(x, z)
			var ch := "?"
			var zone := macro.zone_at(p)
			if macro.freeway.blocks_rect(Rect2(p - Vector2(st, st) * 0.5, Vector2(st, st)), 0.0):
				ch = "F"
			elif zone == MacroMap.Zone.AIRPORT:
				ch = "A"
			elif zone == MacroMap.Zone.OCEAN or zone == MacroMap.Zone.BEACH:
				ch = "~"
			elif zone == MacroMap.Zone.HILLS:
				ch = "^"
			elif zone == MacroMap.Zone.PORT:
				ch = "P"
			elif LightRail.of(plan) and LightRail.of(plan).blocks_rect(Rect2(p - Vector2(st, st) * 0.5, Vector2(st, st)), 0.0):
				ch = "T"
			elif rz.has_point(p):
				ch = "C"
			elif macro.river and macro.river.terrace(p).y > 0.5:
				ch = "R"
			elif plan.in_site(p):
				ch = "S"
			elif Landmarks.claims(Rect2(p, Vector2.ONE)):
				ch = "L"
			else:
				ch = "Dmsicb"[int(plan.district_at(p))]
				var k := plan.block_index_at(p)
				var b := plan.block(k.x, k.y)
				if b.has("grounds"):
					ch = "g"
				elif int(b.kind) == CityPlan.BlockKind.PARK:
					ch = "p"
			row += ch
			x += st
		print(row)
		z += st
	get_tree().quit()
