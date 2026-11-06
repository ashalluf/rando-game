extends RefCounted
## The boot compile (boot-compile, docs/HANDOFF.md "The boot compile"): most of the game is ONE
## GDScript dependency cycle (tools/boot_compile/deps.py), compiled by a single load(); every
## script of it calls LoadPulse.compiled() from its static initialiser, which Godot runs as that
## script finishes compiling, so the boot's picture is presented between scripts. Loaded at run
## time by tests/smoke_test.gd.

const HOOK := "static func _static_init() -> void: LoadPulse.compiled()"
## The cycle's hubs (most named by other scripts, tools/boot_compile/deps.py --cut).
const HUBS := [
	"res://scripts/world/city_chunk.gd", "res://scripts/world/prop_factory.gd",
	"res://scripts/world/building.gd", "res://scripts/npc/pedestrian.gd",
	"res://scripts/vehicles/vehicle.gd", "res://scripts/weapons/weapon_fx.gd",
	"res://scripts/world/landmarks.gd", "res://scripts/world/macro_map.gd",
	"res://scripts/world/city_plan.gd", "res://scripts/player/player.gd",
	"res://scripts/npc/traffic.gd", "res://scripts/world/freeway_kit.gd",
]

var _t: Node


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node) -> void:
	_t = t
	for p: String in HUBS:
		_check(FileAccess.get_file_as_string(p).contains(HOOK), "boot compile: %s carries the boot-frame hook" % p.get_file())
	var hooked := _count_hooked("res://scripts")
	_check(hooked >= 450, "boot compile: the cycle's scripts carry the hook (%d files)" % hooked)
	# Every hooked script's static initialiser has run by now (the gate compiled them): the hook
	# really is called as scripts compile.
	_check(LoadPulse.compiled_count >= 400, "boot compile: compiled() ran from %d static initialisers" % LoadPulse.compiled_count)
	# Inactive (the gate, every tool, the game after the boot): an increment and nothing else.
	var pulses := LoadPulse.pulses
	var n := LoadPulse.compiled_count
	for i in 5:
		LoadPulse.compiled()
	_check(LoadPulse.compiled_count == n + 5 and LoadPulse.pulses == pulses, "boot compile: an inactive compiled() presents nothing")
	# The count on the picture never runs backwards.
	LoadPulse._compile_shown = 0
	LoadPulse.compile_progress(300, 600)
	LoadPulse.compile_progress(120, 600)
	_check(LoadPulse._compile_shown == 300, "boot compile: the script count never counts down")
	LoadPulse.compile_progress(900, 600)
	_check(LoadPulse._compile_shown == 600, "boot compile: the script count stops at the total")
	LoadPulse._compile_shown = 0
	LoadPulse.note("")
	var boot := FileAccess.get_file_as_string("res://scripts/util/boot.gd")
	_check(boot.contains("LoadPulse.compile_mark()") and boot.contains("BOOT_QUIT"), "boot compile: the boot measures the cycle's steps (BOOT_QUIT=1 stops there)")


func _count_hooked(dir: String) -> int:
	var n := 0
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	for f in d.get_files():
		if f.ends_with(".gd") and FileAccess.get_file_as_string(dir.path_join(f)).contains(HOOK):
			n += 1
	for sub in d.get_directories():
		n += _count_hooked(dir.path_join(sub))
	return n
