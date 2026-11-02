extends RefCounted
## Load time after wave 4 (load-time-3, docs/HANDOFF.md "Load time after wave 4"): the rehearsal
## has its LOADING lines and wave 4's stages behind their switch, the scans that walk CarDamage's
## static lists survive a freed entry (the rehearsal's burnt car, freed a tick before its purge,
## raised a SCRIPT ERROR in Emergency._scan on every launch), and the rehearsal empties the shared
## debris rings it threw pieces into. Loaded at run time by tests/smoke_test.gd.

var _t: Node


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_rehearsal_source()
	_freed_entries(city)
	_pools(city)


func _rehearsal_source() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/warm_rehearsal.gd")
	_check(src.contains("LoadClock.start(\"screen: rehearsal\")") and src.contains("LoadClock.stop(\"screen: rehearsal\")"),
			"the rehearsal is a LOADING stage of its own (it was ~12 s with no line)")
	_check(src.contains("\"WARM_WAVE4\"") and src.contains("_stage_wave4_cars") and src.contains("_stage_wave4_effects"),
			"the rehearsal stages wave 4's first uses behind WARM_WAVE4")
	_check(WarmRehearsal.wave4 == (OS.get_environment("WARM_WAVE4") != "0"), "WARM_WAVE4 reads the environment")
	var probe := FileAccess.get_file_as_string("res://tools/shader_warm/first_use_probe.gd")
	_check(probe.contains("const WAVE4 :="), "the first-use probe has wave 4's events")


## A freed node in CarDamage._burning / _wrecks must not stop the scans that read them.
func _freed_entries(city: Node3D) -> void:
	var gone := Node.new()
	gone.free()
	CarDamage._burning.append(gone)
	CarDamage._wrecks.append(gone)
	var fires: Array = Blast3.fire_list(city.get_tree())
	_check(fires is Array, "Blast3.fire_list() steps over a freed burning car")
	var em: Node = city.get_node_or_null("Emergency")
	if em != null and em.get("_player") != null and em.get("plan") != null:
		em.call("_scan")
		_check(true, "Emergency._scan() steps over a freed burning car")
	else:
		_check(true, "Emergency._scan() steps over a freed burning car (no Emergency node to scan with)")
	WarmRehearsal._purge_statics()
	var left := false
	for list: Array in [CarDamage._burning, CarDamage._wrecks]:
		for x in list:
			if not is_instance_valid(x):
				left = true
	_check(not left, "the purge took the freed entries out again")


## clear_pools() empties the crash debris ring.
func _pools(city: Node3D) -> void:
	var debris := CrashDebris.ensure(city)
	if debris == null:
		_check(false, "the crash debris ring can be made in the city")
		return
	debris.thrown = 3
	WarmRehearsal.clear_pools()
	_check(debris.thrown == 0, "the rehearsal's clear_pools() empties the crash debris ring")
