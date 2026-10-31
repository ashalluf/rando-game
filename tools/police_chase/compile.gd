extends SceneTree
## Compiles the police chase's scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/police_chase/compile.gd
## RADIO_WAV=<dir> also writes one radio transmission per kind as a .wav to listen to.

const SCRIPTS := ["res://scripts/npc/police_chase.gd", "res://scripts/npc/chase_spike_strip.gd",
	"res://scripts/npc/chase_flat_tyres.gd", "res://scripts/npc/chase_radio.gd", "res://scripts/npc/police.gd",
	"res://scripts/npc/police_car.gd", "res://scripts/npc/police_officer.gd", "res://scripts/world/air_traffic.gd",
	"res://scripts/vehicles/car_interiors.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	var out := OS.get_environment("RADIO_WAV")
	if out != "":
		var radio: GDScript = load("res://scripts/npc/chase_radio.gd")
		for kind: String in radio.LENGTHS.keys():
			var t0 := Time.get_ticks_usec()
			var w: AudioStreamWAV = radio.transmission(float(radio.LENGTHS[kind]), hash([kind]))
			print("RADIO %s %.2f s built in %.1f ms" % [kind, w.get_length(), (Time.get_ticks_usec() - t0) / 1000.0])
			w.save_to_wav(out.path_join("radio_%s.wav" % kind))
	quit()
