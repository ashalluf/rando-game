extends Node
## The main scene (mac-launch, docs/HANDOFF.md "The Mac launch"): the loading picture at once
## (LoadPulse), then the city scene loaded on a loader thread. Loading city.tscn compiles the whole
## game's GDScript (~650 scripts: 20 s on a 4-core box, more in the editor), and as the main
## scene that compile ran before the window had drawn a single frame. Here the window draws the
## picture throughout; the city's own _ready() takes over the same picture (LoadPulse.begin()).
##
## Straight to the city, with no thread, where there is no picture to show (headless, the web -
## no threads there -, --noload / --nohud, LOAD_PULSE=0) or with BOOT_THREAD=0.

const CITY := "res://scenes/levels/city.tscn"

var _threaded := false
var _progress: Array = []


func _ready() -> void:
	LoadClock.at("boot")
	var picture := LoadPulse.supported() and not _harness()
	_threaded = picture and OS.get_environment("BOOT_THREAD") != "0"
	if picture:
		LoadPulse.begin_picture(get_viewport())
	if not _threaded or ResourceLoader.load_threaded_request(CITY) != OK:
		_threaded = false
		get_tree().change_scene_to_file.call_deferred(CITY)
		return
	LoadClock.start("compile the game")


func _process(_delta: float) -> void:
	if not _threaded:
		return
	var status := ResourceLoader.load_threaded_get_status(CITY, _progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		LoadPulse.paint()
		return
	_threaded = false
	var packed := ResourceLoader.load_threaded_get(CITY) as PackedScene
	LoadClock.stop("compile the game")
	if packed == null:
		get_tree().change_scene_to_file.call_deferred(CITY)
		return
	get_tree().change_scene_to_packed.call_deferred(packed)


## The screenshot harnesses (--noload / --nohud) see no loading picture (CityStreamer's rule).
static func _harness() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--noload" or arg == "--nohud":
			return true
	return false
