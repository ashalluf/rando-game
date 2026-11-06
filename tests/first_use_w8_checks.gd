extends RefCounted
## First uses after waves 5-8 (first-use-w8, docs/HANDOFF.md "First uses after waves 5-8"): the
## rehearsal stages wave 5-8's mid-play first uses behind WARM_WAVE8 (a fuel fireball with its
## burning pools, a boat and its wake, a lit bonfire, landing-light beams, the
## wingsuit's two meshes), and leaves none of it behind: no burning pool, boat, bonfire or beam, no
## car of the row set off by Blast4's chain, the chain's depth put back. Runs a part of the
## rehearsal (its two wave 5-8 stages and the idle-particle stage). Loaded at run time by
## tests/smoke_test.gd. The frames themselves are measured by tools/shader_warm/first_use_probe
## EVENTS=wave8 (opengl3); the dummy renderer here compiles nothing.

var _t: Node


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_source()
	await _staged(city)


func _source() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/warm_rehearsal.gd")
	_check(src.contains("\"WARM_WAVE8\"") and src.contains("_stage_wave8_blasts") and src.contains("_stage_wave8_effects"),
			"the rehearsal stages waves 5-8's first uses behind WARM_WAVE8")
	_check(WarmRehearsal.wave8 == (OS.get_environment("WARM_WAVE8") != "0"), "WARM_WAVE8 reads the environment")
	_check(src.contains("c is BlastPool"), "the rehearsal's sweep frees the burning pools it lit (scripted nodes)")
	var probe := FileAccess.get_file_as_string("res://tools/shader_warm/first_use_probe.gd")
	_check(probe.contains("const WAVE8 :=") and probe.contains("_ev_fuel_blast") and probe.contains("_ev_wingsuit"),
			"the first-use probe has waves 5-8's events")


## A part of the rehearsal in the loaded city: what it lit and staged is all gone afterwards.
func _staged(city: Node3D) -> void:
	if not WarmRehearsal.wave8:
		_check(true, "waves 5-8's stages are off (WARM_WAVE8=0): nothing to stage")
		return
	var tree := city.get_tree()
	var cam := city.get_viewport().get_camera_3d()
	if cam == null:
		_check(false, "the rehearsal has a camera to stage in front of")
		return
	var scene: Node = tree.current_scene if tree.current_scene else tree.root
	var depth := Blast4.chain_depth
	var pops := Blast4.secondary_count
	var pools_before := _count(scene, "BlastPool")
	var fires_before := tree.get_nodes_in_group("vehicle").filter(func(v): return (v as Node).has_meta(WarmRehearsal.TAG)).size()
	var stages_was := WarmRehearsal.only_stages
	var types_was := WarmRehearsal.only_types
	WarmRehearsal.only_stages = PackedStringArray(["wave 5-8 blasts", "wave 5-8 effects", "idle particles"])
	var chained := [0]
	var watch := func() -> void:
		for v in tree.get_nodes_in_group("vehicle"):
			var car := v as Vehicle
			if car != null and car.has_meta(WarmRehearsal.TAG) and car.has_meta("chain_gen"):
				chained[0] += 1
	tree.process_frame.connect(watch)
	await WarmRehearsal.run(city, cam)
	tree.process_frame.disconnect(watch)
	WarmRehearsal.only_stages = stages_was
	WarmRehearsal.only_types = types_was
	for i in 3:
		await tree.process_frame
	_check(Blast4.secondary_count == pops, "the rehearsal puts Blast4's secondary pops back (%s)" % str(Blast4.secondary_count))
	_check(Blast4.chain_depth == depth, "the rehearsal puts Blast4's chain depth back (%d)" % Blast4.chain_depth)
	_check(chained[0] == 0, "no rehearsal car caught the fuel blast's chain fuse (%d frames saw one)" % chained[0])
	var pools_after := _count(scene, "BlastPool")
	_check(pools_after <= pools_before, "the rehearsal's burning pools are swept (%d before, %d after)" % [pools_before, pools_after])
	var left := 0
	for n in scene.find_children("*", "BonfireFire", true, false):
		if not (n as Node).is_queued_for_deletion() and (n as Node).get_parent() != null and String((n as Node).get_parent().name) == "WarmRehearsal":
			left += 1
	for v in tree.get_nodes_in_group("vehicle"):
		if (v as Node).has_meta(WarmRehearsal.TAG) and not (v as Node).is_queued_for_deletion():
			left += 1
	print("FIRST_USE_W8 idle systems: %d copied of %d" % [WarmRehearsal.ghosts_made, WarmRehearsal.ghosts_seen])
	_check(WarmRehearsal.ghosts_seen > 0 and WarmRehearsal.ghosts_made == mini(WarmRehearsal.ghosts_seen, WarmRehearsal.GHOST_CAP)
			and WarmRehearsal.ghosts_seen <= WarmRehearsal.GHOST_CAP,
			"the idle-particle stage copies every idle weather and boost system (%d of %d, cap %d)" % [WarmRehearsal.ghosts_made, WarmRehearsal.ghosts_seen, WarmRehearsal.GHOST_CAP])
	_check(left == 0 and city.get_node_or_null("WarmRehearsal") == null,
			"the rehearsal's boats, bonfire and cars are freed (%d left, %d tagged before)" % [left, fires_before])


func _count(scene: Node, cls: String) -> int:
	var n := 0
	for c in scene.get_children():
		if not c.is_queued_for_deletion() and c.get_script() != null and (c.get_script() as Script).get_global_name() == cls:
			n += 1
	return n
