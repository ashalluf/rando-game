class_name MetroCrowd
extends Node
## Keeps the Coral Line's underground terminus peopled while the player is down there (wave 7,
## refcam `metro_station`, docs/HANDOFF.md "The metro station refcam"). MetroBuild's riders wait on
## the island, and a dwelling train takes most of them aboard (LightRailSystem._passengers()): a
## minute later the platform was empty and the escalators always were. Now people ride the bank's
## escalators standing on the steps (MetroRider level 2: down onto the island, up from it), the
## ones who alight ride the up escalator rather than vanish at its foot, and while the station is
## shown somebody steps onto the down escalator every few seconds while the island holds fewer
## than its share. Every rider is in the crowd cap (CityChunk._take_crowd_room()); the seeds are
## hashes of the city seed and a counter. METRO_CROWD=0 is the A/B (the station as it was).

static var enabled: bool = OS.get_environment("METRO_CROWD") != "0"

## Riders put on the escalators when the station is built: down, up.
const START_DOWN := 3
const START_UP := 2
## The island's share while the station is shown, and the most on the down escalator at once.
const ISLAND_TARGET := 9
const DOWN_MAX := 4
## Seconds between two arrivals (the step a rider takes is ~1.1 m at 0.5 m/s: 2.4 s apart).
const ARRIVE_EVERY := 2.6

var chunk: CityChunk
var frame: Dictionary = {}
var line: LightRail
var station := 0
var seed_base := 0
var _n := 0
var _t := 0.0


## Made by MetroBuild._add_riders() (one hook line), after the waiting riders.
static func attach(c: CityChunk, f: Dictionary, l: LightRail, idx: int, s: int) -> void:
	if not enabled or f.is_empty():
		return
	var mc := MetroCrowd.new()
	mc.name = "MetroCrowd"
	mc.chunk = c
	mc.frame = f
	mc.line = l
	mc.station = idx
	mc.seed_base = s
	c.add_child(mc)
	# The bank's escalators start with people on them, spaced a few steps apart.
	var span := (MetroStation.BANK_U - 0.3) * 2.0
	for k in START_DOWN:
		mc._spawn(1, -MetroStation.BANK_U + 0.3 + span * (float(k) + 0.35) / float(START_DOWN))
	for k in START_UP:
		mc._spawn(-1, MetroStation.BANK_U - 0.3 - span * (float(k) + 0.6) / float(START_UP))


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < ARRIVE_EVERY:
		return
	_t = 0.0
	if not MetroStation.showing:
		return
	var island := 0
	var down := 0
	for r in get_tree().get_nodes_in_group("rail_rider"):
		var m := r as MetroRider
		if m == null or m.get_parent() != chunk or m.is_queued_for_deletion():
			continue
		if m.level == 0 and m.state == 0:
			island += 1
		elif m.level == 2 and m.esc_dir > 0:
			down += 1
	if island + down < ISLAND_TARGET and down < DOWN_MAX:
		_spawn(1, -MetroStation.BANK_U + 0.3)


## One rider stood on an escalator (dir +1 down, -1 up) at `u`; false with the crowd cap full.
func _spawn(dir: int, u: float) -> bool:
	if chunk == null or not chunk._take_crowd_room():
		return false
	var ped := MetroRider.new()
	ped.line = line
	ped.station = station
	ped.frame = frame
	ped.setup(Rect2(), 3.0, hash([seed_base, "metro_crowd", _n]))
	_n += 1
	ped.ride(dir, u)
	chunk.add_child(ped)
	return true
