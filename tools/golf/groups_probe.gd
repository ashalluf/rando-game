extends SceneTree
## Which holes GolfLife puts a group on and at what stage (0 tee, 1 fairway, 2 green), default
## seed (GolfLife.groups()'s rolls, copied: naming GolfLife here compiles the crowd before the
## autoloads exist). Headless, seconds.
func _initialize() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = macro
	var lay := GolfCourse.layout(plan)
	var ps: int = lay.seed
	for h: Dictionary in lay.holes:
		var n: int = h.n
		if GolfCourse.h01([ps, "golf_group", n]) >= 0.72:
			print("hole %d none" % n)
			continue
		var stage := int(GolfCourse.h01([ps, "golf_stage", n]) * 2.999)
		if int(h.par) == 3 and stage == 1:
			stage = 2
		var count := 2 + int(GolfCourse.h01([ps, "golf_count", n]) * 2.999)
		var tee := int(GolfCourse.h01([ps, "golf_tee", n]) * 2.999)
		print("hole %d stage %d count %d tee box %d at %s" % [n, stage, count, tee, str((h.tees[tee] as Dictionary).c)])
	quit()
