extends SceneTree
## Scans the plan's MIDTOWN edge lots (no buildings built) for a low building whose shop names put
## an open LAUNDRY beside a DONUT HOLE and a closed, shuttered shop beside them (Building's own
## name and night rolls, copied): candidates for the laundromat_night refcam.
##   godot --headless --path . --script tools/rc5_laundromat_night/plan_scan.gd
## RECT=x0,z0,x1,z1 (TRUE world), MAX_H=metres.

func _names(seed: int, face: int, runs: int) -> Array:
	var out := []
	var last := -1
	for run in runs:
		var i := absi(hash([seed, "sign_name", face, run * 7919])) % 30
		if i == last:
			i = (i + 1) % 30
		last = i
		out.append(i)
	return out


func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 20:
		await process_frame
	var plan = current_scene.get("plan")
	var B: GDScript = load("res://scripts/world/building.gd")
	var r := OS.get_environment("RECT").split(",") if OS.get_environment("RECT") != "" else PackedStringArray(["-600", "-3000", "1700", "3000"])
	var max_h := float(OS.get_environment("MAX_H")) if OS.get_environment("MAX_H") != "" else 14.0
	var a: Vector2i = plan.block_index_at(Vector2(float(r[0]), float(r[1])))
	var b: Vector2i = plan.block_index_at(Vector2(float(r[2]), float(r[3])))
	var hits := 0
	for ix in range(a.x, b.x + 1):
		for iz in range(a.y, b.y + 1):
			var blk: Dictionary = plan.block(ix, iz)
			if int(blk.get("kind", -1)) != 0 or int(blk.get("district", -1)) != 1:
				continue
			for lot in plan.lots(ix, iz):
				if not lot.get("edge", false) or lot.get("parking", false):
					continue
				var h: float = plan.lot_height(lot.seed, 1, float(blk.get("skyline_boost", 0.0)))
				if h > max_h:
					continue
				for face in 4:
					var nm := _names(lot.seed, face, 5)
					for run in 4:
						var k0: int = (absi(lot.seed % 1000) * 8 + face + 1) * 1024
						var l: String = B.SHOP_NAMES[nm[run]]
						var m: String = B.SHOP_NAMES[nm[run + 1]]
						var pair := (l == "LAUNDRY" and m == "DONUT HOLE") or (l == "DONUT HOLE" and m == "LAUNDRY")
						if not pair:
							continue
						var li := run if l == "LAUNDRY" else run + 1
						if not B.shop_open(k0 + li):
							continue
						var desc := ""
						for q in 5:
							var k := k0 + q
							var op: bool = B.shop_open(k)
							desc += " [%s %s]" % [B.SHOP_NAMES[nm[q]], "open" if op else ("SHUT" if B.shop_byte(k, 8) < 140 else "dark")]
						var c: Vector2 = lot.center
						print("CAND block=", ix, ",", iz, " lot=", c.snapped(Vector2.ONE * 0.1), " size=", lot.size, " h=", snappedf(h, 0.1), " face=", face, desc)
						hits += 1
	print("SCAN done, ", hits, " candidates")
	quit(0)
