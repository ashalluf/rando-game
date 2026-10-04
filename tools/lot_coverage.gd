extends SceneTree
## How much of the city's ground the buildings cover, block by block, and what the rest is.
## Walks every BUILDINGS block inside a rect, lays each lot's building out exactly as
## CityChunk._build_lot() does (Building.plan_only(), no nodes, podium_lot set where LotFill
## runs) and rasterises each block's inner rect (inside the pavement ring) on a GRID m grid:
##   built     under a building part standing on the ground (podiums included) or a downtown tower
##   yard      a pocket garden (lawn); a freeway corridor lot's ivy when the yard fill is off
##   forecourt a lot's ground the building leaves, out to its grid cell, and the cells a
##             landmark's square dropped (LotFill: paving, planters, benches)
##   parking   a surface car park (CityPlan.lots() "parking", LotFill; the beach car parks and the
##             campus's, YardFill)
##   garden    a house's yard, a courtyard, a walk street, a pocket park, the campus's walks, quads,
##             lawns and service yards (YardFill)
##   row       the freeway's right of way, out to its cells (YardFill: ivy, hedge rows, sound walls)
##   bare      the block's plain paving (or, on a campus or suburban block, its plain lawn): nothing
##             on it
## With FILL=0 the lot fill and the yard fill are left out (what the city was before them: no
## podiums, and forecourt, parking, garden and row are bare - a corridor lot's old ivy is "yard");
## FILL=lot keeps LotFill and leaves YardFill out (the city before the yards); FILL=yard keeps
## both and leaves Industrial out (the industrial district before its warehouses and yards; "works"
## is its yards).
## Replica blocks (the Esplanade's: ReplicaBuilder builds them) are left out.
## Rows: one per district (DOWNTOWN split into _core and _rest), FREEWAY (every block a corridor lot
## stands in, whatever its district: the same blocks again), ROW_CELLS (only the ground inside
## those corridor lots' cells) and MACARTHUR_SE (the plaza the roll put across the street from
## MacArthur Park's site, buildings since the yard pass). Also the shapes' own coverage of their lot
## and the podiums built. Headless is fine: nothing is drawn.
##
##   godot --headless --path . --script tools/lot_coverage.gd
##
## Env: RECT=x,z,w,d (default downtown's game extent), SEED (default 1337), FILL (default 1),
## GRID (default 1.0).
## Everything is loaded dynamically: this script compiles before the autoloads exist.
func _initialize() -> void:
	await process_frame
	var report: Dictionary = (load("res://scripts/world/ground_coverage.gd") as GDScript).call("report",
		int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337,
		_rect(), {"0": 0, "lot": 1, "yard": 2}.get(OS.get_environment("FILL"), 3),
		float(OS.get_environment("GRID")) if OS.get_environment("GRID") != "" else 1.0)
	for line: String in report.lines:
		print(line)
	quit()


func _rect() -> Rect2:
	var env := OS.get_environment("RECT")
	if env == "":
		return Rect2(1650.0, -1750.0, 2300.0, 3770.0)
	var v := env.split_floats(",")
	return Rect2(v[0], v[1], v[2], v[3])
