extends RefCounted
## The loading screen's rehearsal (scripts/ui/warm_rehearsal.gd), for tests/smoke_test.gd. Loaded
## at run time, not named there, so it compiles after the autoloads.
##
## Runs WarmRehearsal.run() in the loaded city in front of the player's camera and checks it
## leaves nothing behind: no holder, no new plain node in the scene (the effects' particles,
## decals, pools, craters), no car, person or body; the wanted level and Police.innocent as they
## were, the master bus unmuted; and that every texture the decal atlas keeper holds is real. The
## frames themselves (what it saves) are measured by tools/shader_warm/first_use_probe.tscn under
## lavapipe; the dummy renderer here compiles nothing.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var tree := city.get_tree()
	var cam := city.get_viewport().get_camera_3d()
	_t._check(cam != null, "the rehearsal has a camera to stage in front of")
	if cam == null:
		return
	var police: Node = tree.get_first_node_in_group("wanted")
	var stars_before: int = int(police.get("stars")) if police else 0
	var heat_before: float = float(police.get("heat")) if police else 0.0
	var scene: Node = tree.current_scene if tree.current_scene else tree.root
	var plain_before := 0
	for c in scene.get_children():
		if c.get_script() == null:
			plain_before += 1
	var cars_before := tree.get_nodes_in_group("vehicle").size()
	var peds_before := tree.get_nodes_in_group("pedestrian").size()
	var mute_before := AudioServer.is_bus_mute(0)
	var t0 := Time.get_ticks_msec()
	await WarmRehearsal.run(city, cam)
	var ms := Time.get_ticks_msec() - t0
	for i in 3:
		await tree.process_frame
	_t._check(city.get_node_or_null("WarmRehearsal") == null, "the rehearsal's holder is gone afterwards (ran in %d ms)" % ms)
	var plain_after := 0
	for c in scene.get_children():
		if c.get_script() == null and not c.is_queued_for_deletion():
			plain_after += 1
	_t._check(plain_after <= plain_before, "the rehearsal's effects leave no node in the scene (%d plain nodes before, %d after)" % [plain_before, plain_after])
	var cars_after := 0
	for v in tree.get_nodes_in_group("vehicle"):
		if not (v as Node).is_queued_for_deletion():
			cars_after += 1
	_t._check(cars_after <= cars_before, "the rehearsal's cars are freed (%d vehicles before, %d after)" % [cars_before, cars_after])
	var peds_after := 0
	for p in tree.get_nodes_in_group("pedestrian"):
		if not (p as Node).is_queued_for_deletion():
			peds_after += 1
	_t._check(peds_after <= peds_before, "the rehearsal's people are freed (%d before, %d after)" % [peds_before, peds_after])
	if police:
		_t._check(int(police.get("stars")) == stars_before and is_equal_approx(float(police.get("heat")), heat_before),
				"the rehearsal is no crime (stars %d -> %d, heat %.1f -> %.1f)" % [stars_before, int(police.get("stars")), heat_before, float(police.get("heat"))])
	_t._check(not Police.innocent, "Police.innocent is put back after the rehearsal")
	_t._check(AudioServer.is_bus_mute(0) == mute_before, "the master bus is unmuted after the rehearsal")
	var sets: Array = WarmRehearsal.atlas_textures()
	var real := 0
	for s: Array in sets:
		if s[0] is Texture2D and (s[0] as Texture2D).get_width() > 0:
			real += 1
	_t._check(sets.size() >= 10 and real == sets.size(), "the decal atlas keeper holds every decal texture (%d of %d real)" % [real, sets.size()])
