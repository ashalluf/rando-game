extends SceneTree
## How much of the city's ground the buildings cover, block by block, and where the rest goes.
## Walks every BUILDINGS block inside a rect, lays each lot's building out exactly as
## CityChunk._build_lot() does (Building.plan_only(), no nodes), rasterises the parts that stand
## on the ground on a 1 m grid and sums, per district:
##   inner   the block inside its pavement ring (what could be built on)
##   lots    what CityPlan.lots() hands out (the rest is the gaps between lots, dropped lots)
##   built   ground under a building part (bottom at 0)
##   yard    pocket-garden lots, corridor lots (ivy), pads
##   fill    LotFill's podium extensions, forecourt planting, surface parking (after this pass)
## and the shapes' own coverage of their lot. Headless is fine: nothing is drawn.
##
##   godot --headless --path . --script tools/lot_coverage.gd -- [RECT=x,z,w,d]
##
## Env: RECT (default downtown's game extent), SEED (default 1337).
## Everything is loaded dynamically: this script compiles before the autoloads exist.
func _initialize() -> void:
	await process_frame
	var plan_script: GDScript = load("res://scripts/world/city_plan.gd")
	var macro_script: GDScript = load("res://scripts/world/macro_map.gd")
	var building_scene: PackedScene = load("res://scenes/props/building.tscn")
	var fill_script: GDScript = load("res://scripts/world/lot_fill.gd") if ResourceLoader.exists("res://scripts/world/lot_fill.gd") else null
	var plan = plan_script.new()
	plan.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	plan.macro = macro_script.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	var area := Rect2(1650.0, -1750.0, 2300.0, 3770.0)
	var env := OS.get_environment("RECT")
	if env != "":
		var v := env.split_floats(",")
		area = Rect2(v[0], v[1], v[2], v[3])
	var lo: Vector2i = plan.block_index_at(area.position)
	var hi: Vector2i = plan.block_index_at(area.end)
	var names := ["DOWNTOWN", "MIDTOWN", "SUBURBS", "INDUSTRIAL", "CAMPUS", "BEACHTOWN"]
	var shape_names := ["SLAB", "TOWER", "STEPPED", "PODIUM_TOWER", "L_SHAPE", "SETBACK", "CROWN", "WAREHOUSE"]
	var tot := {}
	var shape_cov := {}
	var fill_kinds := {}
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b: Dictionary = plan.block(bx, bz)
			if int(b.kind) != 0 or b.has("site"):
				continue
			if not area.has_point((b.rect as Rect2).get_center()):
				continue
			if int(plan.zone_at((b.rect as Rect2).get_center())) != 0:
				continue
			var d: String = names[int(b.district)]
			var boost0: float = plan.macro.skyline_boost((b.rect as Rect2).get_center())
			if int(b.district) == 0:
				d += "_core" if boost0 > 0.55 else "_rest"
			if not tot.has(d):
				tot[d] = {"blocks": 0, "inner": 0.0, "lots": 0.0, "built": 0.0, "yard": 0.0, "corridor": 0.0, "fill": 0.0, "lots_n": 0, "cells": 0.0, "dropped": 0.0}
			var t: Dictionary = tot[d]
			var inner: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width)
			t.blocks += 1
			t.inner += inner.get_area()
			var boost: float = boost0
			# The lot grid as CityPlan.lots() lays it (same rng), for the gaps and the dropped lots.
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([plan.seed, 11, bx, bz])
			var params: Dictionary = plan_script.DISTRICTS[int(b.district)]
			var lot_range: Vector2 = params.lot
			if params.has("core_lot"):
				lot_range = lot_range.lerp(params.core_lot, boost)
			var lw := rng.randf_range(lot_range.x, lot_range.y)
			var ld := rng.randf_range(lot_range.x, lot_range.y)
			var gnx := maxi(1, floori(inner.size.x / lw))
			var gnz := maxi(1, floori(inner.size.y / ld))
			var cell := Vector2(inner.size.x / gnx, inner.size.y / gnz)
			var kept := 0.0
			for lot: Dictionary in plan.lots(bx, bz):
				kept += (lot.size as Vector2).x * (lot.size as Vector2).y
			var possible := 0.0
			var gap_range: Vector2 = params.gap
			var courtyard: float = float(params.courtyard)
			for lx in gnx:
				for lz in gnz:
					var edge := lx == 0 or lz == 0 or lx == gnx - 1 or lz == gnz - 1
					if not edge:
						rng.randf()
					var gap := rng.randf_range(gap_range.x, gap_range.y)
					rng.randi()
					possible += maxf(cell.x - gap, 0.0) * maxf(cell.y - gap, 0.0)
			t.cells += possible
			t.dropped += maxf(possible - kept, 0.0)
			for lot: Dictionary in plan.lots(bx, bz):
				var size: Vector2 = lot.size
				t.lots += size.x * size.y
				t.lots_n += 1
				if lot.yard:
					t.yard += size.x * size.y
					continue
				if plan.macro.freeway and (plan.macro.freeway.blocks(lot.center, 14.0) or plan.macro.freeway.blocks_rect(Rect2((lot.center as Vector2) - size * 0.5, size), 3.0)):
					t.corridor += size.x * size.y
					continue
				var bld = building_scene.instantiate()
				bld.seed = lot.seed
				bld.lot_size = size
				var target: float = plan.lot_height(lot.seed, int(b.district), boost)
				bld.min_height = target * 0.88
				bld.max_height = target
				var sh: Array[int] = []
				sh.assign(plan_script.lot_shapes(int(b.district), boost))
				bld.shape_options = sh
				var fi: Array[int] = []
				fi.assign(plan_script.lot_finishes(int(b.district), boost))
				bld.finish_options = fi
				bld.plan_only()
				var cells := 0
				var fill_cells := 0
				var nx := int(size.x)
				var nz := int(size.y)
				var fill = null
				if fill_script:
					fill = fill_script.plan_lot(plan, lot, bld, int(b.district), boost)
				for i in nx:
					for j in nz:
						var p := Vector2(-size.x * 0.5 + i + 0.5, -size.y * 0.5 + j + 0.5)
						var hit := false
						for part: Dictionary in bld.parts:
							var c: Vector3 = part.center
							var s: Vector3 = part.size
							if c.y - s.y * 0.5 > 0.01:
								continue
							if absf(p.x - c.x) <= s.x * 0.5 and absf(p.y - c.z) <= s.z * 0.5:
								hit = true
								break
						if hit:
							cells += 1
						elif fill != null and fill_script.covers(fill, p):
							fill_cells += 1
				t.built += cells
				t.fill += fill_cells
				if fill != null:
					var k: String = str(fill.get("kind", "none"))
					fill_kinds[d + " " + k] = int(fill_kinds.get(d + " " + k, 0)) + 1
				var sk: String = d + " " + shape_names[int(bld.shape)]
				if not shape_cov.has(sk):
					shape_cov[sk] = [0, 0.0]
				shape_cov[sk][0] += 1
				shape_cov[sk][1] += float(cells) / maxf(float(nx * nz), 1.0)
				bld.free()
	for d: String in tot:
		var t: Dictionary = tot[d]
		print("GRID %s gaps between lots %.1f %% of inner | lots dropped (landmark squares, clear zone, tiny) %.1f %%" % [d, 100.0 * (t.inner - t.cells) / t.inner, 100.0 * t.dropped / t.inner])
		print("COVER %s blocks %d lots %d | inner %.0f m2 | lots %.1f %% of inner | built %.1f %% of inner (%.1f %% of lots) | yard %.1f %% corridor %.1f %% | fill %.1f %% | bare %.1f %%" % [
			d, t.blocks, t.lots_n, t.inner, 100.0 * t.lots / t.inner, 100.0 * t.built / t.inner, 100.0 * t.built / maxf(t.lots, 1.0),
			100.0 * t.yard / t.inner, 100.0 * t.corridor / t.inner, 100.0 * t.fill / t.inner,
			100.0 * (t.inner - t.built - t.yard - t.corridor - t.fill) / t.inner])
	var keys := shape_cov.keys()
	keys.sort()
	for k: String in keys:
		print("SHAPE %s n %d mean lot cover %.1f %%" % [k, shape_cov[k][0], 100.0 * shape_cov[k][1] / shape_cov[k][0]])
	var fk := fill_kinds.keys()
	fk.sort()
	for k: String in fk:
		print("FILL %s %d" % [k, fill_kinds[k]])
	quit()
