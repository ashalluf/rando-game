extends Node
## Engine audio probe (EngineAudio, scripts/vehicles/engine_audio.gd): headless, seconds.
##   godot --headless --path . tools/engine_audio/probe.tscn
## Prints each profile's run through the gears at full and at light throttle (speed, gear, rpm,
## the five layers' gains) and the profile of every body type, then checks every loop loaded.

func _ready() -> void:
	for name: String in EngineAudio.PROFILES:
		var prof: Dictionary = EngineAudio.PROFILES[name]
		for th: float in [1.0, 0.35]:
			var st := EngineAudio.new_state(prof)
			var v := 0.0
			var line := PackedStringArray()
			var accel := float(prof.top) / 14.0
			for i in 900:
				var dt := 1.0 / 60.0
				EngineAudio.step_engine(st, prof, v, th, false, false, dt)
				v = minf(v + accel * th * dt * (1.0 - v / (float(prof.top) * 1.1)), float(prof.top) * 1.1)
				if i % 60 == 0:
					line.append("%4.1f:g%d:%d" % [v, int(st.gear) + 1, int(st.rpm)])
			print("%-6s th %.2f shifts %2d  %s" % [name, th, int(st.shifts), " ".join(line)])
		var g := EngineAudio.layer_gains(prof, float(prof.rpm[2]) * 1.1, 0.0)
		print("        coasting at mid x1.1: ", g)
	var types := PackedStringArray()
	for t in Vehicle.BodyType.values():
		types.append("%s=%s" % [Vehicle.BodyType.keys()[t], EngineAudio.profile_for_type(t)])
	print("PROFILES ", " ".join(types))
	var missing := 0
	for name: String in Sfx.SAMPLES:
		if name.begins_with("eng_") and not ResourceLoader.exists(Sfx.AUDIO_DIR + Sfx.SAMPLES[name][0]):
			missing += 1
	print("ENGINE FILES missing %d" % missing)
	get_tree().quit()
