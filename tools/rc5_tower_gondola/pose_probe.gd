extends SceneTree
## Prints where a tower's hung cradle is over the clock (TowerGondolas.pose_at), to pick a refcam
## row's gondola_t:  TOWER=dt_park_c SITE=0 T0=0 T1=20000 DT=50 Y0=70 Y1=90 godot --headless --path . --script tools/rc5_tower_gondola/pose_probe.gd

func _initialize() -> void:
	await process_frame
	load("res://tools/rc5_tower_gondola/pose_probe_run.gd").new().call("run", self)
