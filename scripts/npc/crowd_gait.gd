class_name CrowdGait
## How each person in the crowd walks (crowd-anim-2). Everyone used to walk on the one rig clip
## (Casual_Walk_inplace) with the same arms and the same pace, and a pavement of people read as a
## march. Now each plain walker (Pedestrian / ReplicaWalker) gets a GAIT, picked from a hash of
## its seed and its rig's build (the phenotype tools/crowd/gait_clips.gd bakes into the library):
##   casual  the library's everyday walk          brisk   a longer step, leaning in, arms pumping
##   amble   short steps, head down, slack arms   heavy   wide feet turned out, arms off the body,
##   light   narrow, springy                              the hips rolling (heavy builds)
##   formal  upright, small arm swing (suits)     classic the rig's own walk, as before
## each with a pace, an arm swing and a turn rate of its own on top of the person's own spread,
## and a weight-shifting idle (gait/idle) in place of the rig's still one. The clips' ground
## speeds are measured on the keys (clip metadata), so the play rate the walk runs at keeps a
## planted foot planted for every gait on every rig.
##
## Everything rolls on hash([seed, "gait2"]): no stream anyone else reads moves.
## CROWD_ANIM_2=0 in the environment is the A/B (the crowd exactly as before).

const LIB_DIR := "res://assets/models/crowd_gait/"
const LIB := "gait"
## Name -> [pace multiplier, arm swing multiplier, turn rate multiplier, lean into turns].
const GAITS := {
	"casual": [1.0, 1.0, 1.0, 1.0],
	"brisk": [1.17, 1.05, 1.15, 1.2],
	"amble": [0.8, 0.9, 0.75, 0.7],
	"heavy": [0.88, 1.0, 0.8, 0.8],
	"light": [1.05, 1.0, 1.1, 1.1],
	"formal": [1.04, 0.95, 0.95, 0.9],
	"classic": [1.0, 1.0, 1.0, 1.0],
}
## Most a walker banks into a turn (radians) and how much of the centripetal angle it takes.
const TURN_LEAN_MAX := 0.14
const TURN_LEAN_GAIN := 0.45
## The walk's play rate stays in this band (the clips hold one stride in 1.33 s: 1.4 is about two
## steps a second).
const CADENCE := Vector2(0.85, 1.4)

static var _enabled := -1
## A gait every new walker takes ("" = the hash's pick): the lab and stills.
static var forced := ""
static var _libs: Dictionary = {}


static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 0 if OS.get_environment("CROWD_ANIM_2") == "0" else 1
	return _enabled == 1


static func library(model_path: String) -> AnimationLibrary:
	if _libs.has(model_path):
		return _libs[model_path]
	var path := LIB_DIR + model_path.get_file().get_basename() + "_gait.res"
	var lib: AnimationLibrary = load(path) if ResourceLoader.exists(path) else null
	_libs[model_path] = lib
	return lib


## The gait for a person of this seed on this rig, its width roll `wide` (the visual's x scale)
## included: pure, so tests and stills can ask.
static func pick(seed_value: int, lib: AnimationLibrary, wide: float) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "gait2"])
	var u := r.randf()
	var weight := float(lib.get_meta("weight", 0.5)) + (wide - 1.0) * 2.0
	var age := float(lib.get_meta("age", 0.5))
	var muscle := float(lib.get_meta("muscle", 0.5))
	# The build first: a heavy body mostly walks heavy, an old one mostly ambles.
	if weight > 0.68 and u < 0.7:
		return "heavy"
	if age > 0.8 and u < 0.6:
		return "amble"
	if weight < 0.42 and muscle < 0.6 and u < 0.45:
		return "light"
	# Everyone else from a spread: most walk casually, a good share in a hurry.
	var v := r.randf()
	var table := [["casual", 0.32], ["brisk", 0.22], ["classic", 0.16], ["amble", 0.1], ["formal", 0.1], ["light", 0.1]]
	for row: Array in table:
		if v < float(row[1]):
			return row[0]
		v -= float(row[1])
	return "casual"


## Sets the person's walk up: the library on its AnimationPlayer, the clip, its measured ground
## speed and footfall, the idle, and the pace / arms / turn numbers. Called from
## Pedestrian._add_model() once the rig's own clips are fixed up. False when it does nothing.
static func apply(ped: Pedestrian, anim: AnimationPlayer, seed_value: int) -> bool:
	if not enabled() or anim == null:
		return false
	var lib := library(ped._model_path)
	if lib == null:
		return false
	if not anim.has_animation_library(LIB):
		anim.add_animation_library(LIB, lib)
	var name := forced if forced != "" else pick(seed_value, lib, ped._visual.scale.x)
	ped.gait = name
	var row: Array = GAITS[name]
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "gait2", "tune"])
	if name != "classic" and lib.has_animation(name):
		var a := lib.get_animation(name)
		ped._walk_clip = LIB + "/" + name
		ped._walk_clip_speed = maxf(float(a.get_meta("ground_speed", Pedestrian.WALK_CLIP_SPEED)), 0.3)
		ped._walk_cycles = float(a.get_meta("cycles", 1))
		ped._walk_left_down = float(a.get_meta("left_down", 0.0))
	if lib.has_animation("idle") and r.randf() < 0.8:
		ped._idle_clip = LIB + "/idle"
	if not ped._jogger:
		ped.walk_speed *= float(row[0]) * r.randf_range(0.95, 1.05)
		if name != "classic":
			# The cadence a real walker keeps: a short-legged clip at a fast pace would trot
			# (and a long one at a slow pace wade), so the pace gives way to the step instead.
			var step_speed := ped._walk_clip_speed * ped._stride
			ped.walk_speed = clampf(ped.walk_speed, step_speed * CADENCE.x, step_speed * CADENCE.y)
		ped._speed = ped.walk_speed
	ped._arm_swing *= float(row[1])
	ped._turn_rad *= float(row[2])
	ped._turn_lean_gain = TURN_LEAN_GAIN * float(row[3])
	return true


## A walker's bank into a turn: the centripetal angle at its speed and yaw rate, a share of it,
## eased (radians, positive leans left).
static func turn_lean(current: float, yaw_rate: float, speed: float, gain: float, delta: float) -> float:
	var want := clampf(atan(speed * yaw_rate / 9.8) * gain, -TURN_LEAN_MAX, TURN_LEAN_MAX)
	return lerpf(current, want, 1.0 - exp(-6.0 * delta))
