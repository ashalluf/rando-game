extends "res://tools/aerial_review/layer_probe.gd"
## The lowrider_meet camera's pale street: layer_probe.gd's per-layer hides plus the local
## lights (every OmniLight3D / SpotLight3D off) and every additive pool batch, so the light on the
## asphalt can be pinned on what throws it. Run like layer_probe.gd (TREES_AB=1, EYE=, --hour=).


func _trees_ab(path: String) -> void:
	await super(path)
	var lights := []
	for n in current_scene.find_children("*", "Light3D", true, false):
		if not (n is DirectionalLight3D) and (n as Light3D).is_visible_in_tree():
			lights.append(n)
	print("PROBE lights on: ", lights.size())
	for l in lights:
		(l as Light3D).visible = false
	for i in 3:
		await process_frame
	get_root().get_texture().get_image().save_png(path.get_basename() + "_hide_lights.png")
	for l in lights:
		(l as Light3D).visible = true
	var pools := []
	for n in current_scene.find_children("*", "GeometryInstance3D", true, false):
		var nm := String(n.name)
		if (nm.contains("pool") or nm.contains("glow") or nm.contains("atmos") or nm.contains("spill")) and (n as Node3D).is_visible_in_tree():
			pools.append(n)
	print("PROBE pools: ", pools.size())
	for p in pools:
		(p as Node3D).visible = false
	for i in 3:
		await process_frame
	get_root().get_texture().get_image().save_png(path.get_basename() + "_hide_pools.png")
	for p in pools:
		(p as Node3D).visible = true
