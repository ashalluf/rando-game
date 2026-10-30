extends RefCounted
## Aerial advertising (SkyAds, AdBlimp, BannerPlane, SkyAdMesh, shaders/sky_ads.gdshader;
## docs/HANDOFF.md "Aerial advertising"): checks for tests/smoke_test.gd. Loaded at run time, so
## it compiles after the autoloads. Nothing here leans on where the player is or what the
## weather does: the schedule is asked with a forced hour and weather, and the flights it tests
## are its own, staged (SkyAds.staged) and stepped with advance(), then cleared.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var air := city.get_node_or_null("AirTraffic")
	_t._check(air != null, "the city has AirTraffic for the aerial advertising")
	if air == null:
		return
	for i in 120:
		if air.get("_ready_done"):
			break
		await _t.get_tree().physics_frame
	var ads = air.get("sky_ads")
	_t._check(ads != null and ads is SkyAds, "AirTraffic made its SkyAds node (SKY_ADS=0 is the A/B)")
	if ads == null:
		return
	var src := FileAccess.get_file_as_string("res://scripts/world/air_traffic.gd")
	_t._check(src.contains("\"SKY_ADS\"") and src.contains("!= \"0\""), "SkyAds sits behind its SKY_ADS=0 switch")
	_routes(ads)
	_schedule(ads)
	_meshes()
	_shader_copies()
	_flights(ads)


## The blimp loops the ballpark and the beach clear of everything under it at an airship's
## grades; the banner racetracks lie over the sea, level, with turns a light plane makes.
func _routes(ads: SkyAds) -> void:
	var r: AirRoute = ads.blimp_route
	_t._check(r != null and r.length > 4000.0, "the blimp has its loop (%.0f m)" % [r.length if r else 0.0])
	if r == null:
		return
	var low := INF
	var steep := 0.0
	var near_stadium := INF
	var near_beach := INF
	for i in r.xz.size():
		var p: Vector2 = r.xz[i]
		low = minf(low, r.y[i] - float(ads.air.call("obstacle_top", p)))
		if i > 0:
			steep = maxf(steep, absf(r.y[i] - r.y[i - 1]) / maxf(r.dist[i] - r.dist[i - 1], 0.01))
		near_stadium = minf(near_stadium, p.distance_to(ads.stadium_centre()))
		near_beach = minf(near_beach, p.distance_to(ads.beach_centre()))
	_t._check(low >= ads.blimp_clearance - 1.0, "the blimp's loop clears everything under it by %.0f m (least %.0f)" % [ads.blimp_clearance, low])
	_t._check(steep <= 0.04, "the blimp climbs and sinks at an airship's grade (steepest %.3f)" % steep)
	_t._check(near_stadium < ads.stadium_radius * 1.1 and near_beach < ads.beach_radius * 1.1,
		"the blimp circles the ballpark and the beach (nearest %.0f m / %.0f m to their centres)" % [near_stadium, near_beach])
	_t._check(r.xz[0].distance_to(r.xz[r.xz.size() - 1]) < 1.0 and absf(r.y[0] - r.y[r.y.size() - 1]) < 0.5,
		"the blimp's loop closes on itself, level at the seam")
	_t._check(ads.banner_routes.size() == 2, "two banner racetracks")
	for b: AirRoute in ads.banner_routes:
		var dry := 0
		var tight := INF
		var lo := INF
		for i in b.xz.size():
			if ads.macro.zone_at(b.xz[i]) != MacroMap.Zone.OCEAN:
				dry += 1
			tight = minf(tight, 1.0 / maxf(absf(b.turn[i]), 1e-6))
			lo = minf(lo, b.y[i])
		_t._check(dry == 0, "%s lies over the sea (%d points over land)" % [b.name, dry])
		_t._check(tight > 60.0, "%s turns no tighter than a banner tow can (%.0f m)" % [b.name, tight])
		_t._check(lo >= 140.0, "%s flies at least 140 m up (%.0f m)" % [b.name, lo])
		_t._check(b.xz[0].distance_to(b.xz[b.xz.size() - 1]) < 1.0, "%s closes on itself" % b.name)


## Who flies is the hour and the weather, nothing else: the blimp day and night but not in rain
## or a storm, the banners by day only.
func _schedule(ads: SkyAds) -> void:
	_t._check(SkyAds.blimp_flies(12.0, 0) and SkyAds.blimp_flies(22.0, 0), "the blimp flies by day and by night")
	_t._check(not SkyAds.blimp_flies(12.0, 2) and not SkyAds.blimp_flies(12.0, 3), "the blimp stays down in rain and storms")
	var day := true
	var night := false
	for i in ads.banner_planes:
		day = day and ads.banner_flies(i, 13.0, 0)
		night = night or ads.banner_flies(i, 3.0, 0) or ads.banner_flies(i, 21.0, 0) or ads.banner_flies(i, 13.0, 2)
	_t._check(day and not night, "banner planes fly by day in fair weather only")
	_t._check(is_equal_approx(SkyAds.roll(1337, "x"), SkyAds.roll(1337, "x")) and SkyAds.roll(1337, "x") != SkyAds.roll(1338, "x"),
		"the rolls are hashes of the seed")
	var picks_ok := true
	for n in 20:
		var k := ads.banner_pick(0, n)
		picks_ok = picks_ok and k >= 0 and k < SkyAds.BANNERS.size()
	_t._check(picks_ok and ads.banner_pick(1, 3) == ads.banner_pick(1, 3), "banner picks are in the table and repeat")


func _meshes() -> void:
	var tc := SkyAdMesh.triangle_counts()
	_t._check(int(tc.blimp) > 4000 and int(tc.blimp) < 14000, "the blimp is real geometry within budget (%d triangles)" % tc.blimp)
	_t._check(int(tc.plane) > 500 and int(tc.plane) < 2500, "the tow plane is real geometry within budget (%d triangles)" % tc.plane)
	_t._check(SkyAdMesh.env_radius(SkyAdMesh.ENV_LENGTH * SkyAdMesh.ENV_PEAK) > 7.5 and SkyAdMesh.env_radius(1.0) < 3.0 and SkyAdMesh.env_radius(SkyAdMesh.ENV_LENGTH) < 0.5,
		"the envelope swells to its 15 m girth and closes at both ends")
	var w := SkyAds.led_width()
	var img := SkyAds.led_texture().get_image()
	var lit := 0
	if img:
		for x in range(0, img.get_width()):
			for y in img.get_height():
				if img.get_pixel(x, y).a > 0.5:
					lit += 1
	_t._check(w > 200 and img != null and img.get_height() == SkyAds.LED_ROWS and lit > 300, "the night sign's text strip is drawn (%d px wide, %d lit)" % [w, lit])


## The shader's kind codes are SkyAdMesh's.
func _shader_copies() -> void:
	var sh := FileAccess.get_file_as_string("res://shaders/sky_ads.gdshader")
	var bad: Array[String] = []
	var codes := {"K_PAINT": SkyAdMesh.K_PAINT, "K_ENVELOPE": SkyAdMesh.K_ENVELOPE, "K_LETTER": SkyAdMesh.K_LETTER,
		"K_LED": SkyAdMesh.K_LED, "K_GLASS": SkyAdMesh.K_GLASS, "K_DARK": SkyAdMesh.K_DARK, "K_METAL": SkyAdMesh.K_METAL,
		"K_PROP": SkyAdMesh.K_PROP, "K_CLOTH": SkyAdMesh.K_CLOTH, "K_ROPE": SkyAdMesh.K_ROPE, "K_LAMP": SkyAdMesh.K_LAMP}
	for k: String in codes:
		if not sh.contains("const float %s = %d.0;" % [k, int(codes[k])]):
			bad.append(k)
	_t._check(bad.is_empty(), "shaders/sky_ads.gdshader's kind codes are SkyAdMesh's %s" % [bad])


## A staged blimp flies its loop, takes rounds and goes down to a wreck; a staged tow plane
## drags its banner behind and below, loses the banner to rounds, then goes down itself.
func _flights(ads: SkyAds) -> void:
	var was_staged := ads.staged
	ads.staged = true
	ads.clear_all()
	var b := ads.spawn_blimp(1000.0, false)
	var s0 := b.s
	for i in 50:
		b.advance(0.2)
	var moved := fposmod(b.s - s0, ads.blimp_route.length)
	var on := Vector2(b.world_pos.x, b.world_pos.z).distance_to(Vector2(ads.blimp_route.sample(b.s).pos.x, ads.blimp_route.sample(b.s).pos.z))
	_t._check(absf(moved - b.speed * 10.0) < 1.0 and on < 1.0, "the blimp flies its loop at its own speed (%.1f m in 10 s, %.2f m off it)" % [moved, on])
	b.take_hit(0, 10.0, Vector3.FORWARD)
	_t._check(b.life == AmbientCraft.Life.FLYING, "one round does not bring the blimp down")
	b.take_hit(0, 100000.0, Vector3.FORWARD)
	_t._check(b.life == AmbientCraft.Life.DOWN, "enough fire brings the blimp down")
	var y_hit := b.world_pos.y
	var steps := 0
	while b.life == AmbientCraft.Life.DOWN and steps < 3000:
		b.advance(0.25)
		steps += 1
	_t._check(b.life == AmbientCraft.Life.WRECK and b.crash_world != Vector3.INF, "the burning blimp sinks to the ground and blows up there (%.0f s from %.0f m)" % [steps * 0.25, y_hit])
	b.remove()
	var p := ads.spawn_plane(0, 500.0, false, 0)
	for i in 20:
		p.advance(0.1)
	var bw := WorldState.to_world(p.banner.global_position)
	var back := bw - p.world_pos
	var flat := Vector3(back.x, 0.0, back.z)
	_t._check(flat.length() > p.tow_length * 0.8 and flat.length() < p.tow_length + 20.0 and flat.dot(AmbientCraft.yaw_dir(p.yaw)) < 0.0 and back.y < -3.0,
		"the banner trails %.0f m behind the tow plane and %.0f m below" % [flat.length(), -back.y])
	p.banner_hit(10.0)
	_t._check(not p.banner_cut, "a round through the banner does not cut it loose")
	p.banner_hit(10000.0)
	_t._check(p.banner_cut and p.life == AmbientCraft.Life.FLYING, "the banner shot to rags tears off; the plane flies on")
	p.take_hit(0, 1000.0, Vector3.FORWARD)
	_t._check(p.life == AmbientCraft.Life.DOWN, "a shot-up tow plane goes down")
	p.remove()
	ads.clear_all()
	ads.staged = was_staged
	ads._blimp_respawn = 0.0
	for i in ads._plane_respawn.size():
		ads._plane_respawn[i] = 0.0
