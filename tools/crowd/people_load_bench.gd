extends SceneTree
## Times the people's share of the loading screen for the current Pedestrian.MODELS, without the
## city: every rig's limbs cut and welded middle / far bodies built (Ragdoll.warm_limbs,
## Pedestrian.warm_far_mesh), then every camp figure baked (CampFigure.kinds / mesh_for), exactly
## what LoadingScreen.run() does for them. Needs mesh data, so a real renderer, never --headless:
##
##   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 800x600x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/crowd/people_load_bench.gd
##
## Prints "LOADBENCH rigs N: ms, camp figures M: ms". Classes are loaded by path (this compiles
## before the autoloads exist).
func _initialize() -> void:
	await process_frame
	var ped = load("res://scripts/npc/pedestrian.gd")
	var rag = load("res://scripts/npc/ragdoll.gd")
	var camp = load("res://scripts/world/camp_figure.gd")
	var host := Node3D.new()
	get_root().add_child(host)
	await process_frame
	var t0 := Time.get_ticks_usec()
	for m: String in ped.MODELS:
		rag.warm_limbs(m, host)
		ped.warm_far_mesh(m, host)
	var t1 := Time.get_ticks_usec()
	var kinds: Array = camp.kinds()
	for k: Array in kinds:
		camp.mesh_for(camp.seed_for(k[0], k[1], k[2]), k[1])
	var t2 := Time.get_ticks_usec()
	print("LOADBENCH rigs %d: %d ms, camp figures %d: %d ms, total %d ms" % [ped.MODELS.size(), (t1 - t0) / 1000,
		kinds.size(), (t2 - t1) / 1000, (t2 - t0) / 1000])
	quit()
