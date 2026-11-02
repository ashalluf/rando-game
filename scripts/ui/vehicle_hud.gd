class_name VehicleHud
extends Control
## The car the player is in (docs/HANDOFF.md "HUD polish"): its maker and model ease in on the
## right, over the speed readout beside the minimap, as he gets in, hold and go; the speed
## (MPH on the road, knots in the air and on the water) stays while he drives, in a glass pill
## with a thin bar of how fast and the selector's letter. Built by DebugHud, CLEAN and FULL.
##
## The names are invented (`MODELS`): the makers are the city's dealership brands (CarDealers)
## and a few more; nothing is or imitates a real manufacturer or model.

## Seconds: the name toast's ease in, hold and ease out; the speed pill's fade.
@export var fade_in: float = 0.5
@export var hold: float = 3.2
@export var fade_out: float = 0.8
@export var pill_fade: float = 0.3
## The pill's size at 1080 lines and its gap from the minimap's left edge.
@export var pill_size: Vector2 = Vector2(196.0, 86.0)
@export var pill_gap: float = 18.0
## The speed the bar is full at (mph).
@export var bar_full_mph: float = 160.0

## VEHICLE_HUD=0 in the environment: neither the name nor the speed (the A/B).
static var enabled: bool = OS.get_environment("VEHICLE_HUD") != "0"
## Stills: [body type, mph] shown at once without a car (-1 none).
static var forced_type: int = -1
static var forced_mph: float = 0.0

const MPS_TO_MPH := 2.236936
const MPS_TO_KNOTS := 1.943844

## [maker, model, class] per Vehicle.BodyType, in its order (the checks hold the count).
const MODELS := [
	["Quentis", "Marlow", "Sedan"],
	["Haldric", "Sawtooth 1500", "Pickup"],
	["Sundale", "Haulmate", "Van"],
	["Bravent", "Vesper GT", "Sports"],
	["Vantari", "Fulmine", "Supercar"],
	["Vantari", "Fulmine Aperta", "Supercar"],
	["Kestrel", "Halcyon", "Hypercar"],
	["Kestrel", "Halcyon RS", "Hypercar"],
	["Orivo", "Ventra", "Crossover"],
	["Brennard", "CityLiner 40", "City bus"],
	["Brennard", "Stacker 26", "Box truck"],
	["Brennard", "Longhaul LX", "Semi"],
	["Brennard", "Pumper 1250", "Fire engine"],
	["Brennard", "Medic III", "Ambulance"],
	["Velmara", "Pippa", "Hatchback"],
	["Haldric", "Bastion", "SUV"],
	["Orivo", "Hearthway", "Minivan"],
	["Quentis", "Marlow Cab", "Taxi"],
	["Quentis", "Esquire '94", "Sedan"],
	["Brennard", "Scholar D", "School bus"],
	["Brennard", "Sidewinder", "Garbage truck"],
	["Brennard", "Broomhall", "Street sweeper"],
	["Brennard", "Rollback 21", "Tow truck"],
	["Sundale", "Frostline", "Ice cream truck"],
	["Sundale", "Haulmate Courier", "Delivery van"],
	["Velmara", "Imperio '64", "Lowrider"],
	["Velmara", "Solano '84", "Lowrider"],
	["Torvik", "Strega 900", "Motorcycle"],
	["Torvik", "Longrider", "Motorcycle"],
	["Torvik", "Zippa 125", "Scooter"],
	["Orivo", "Pebble e", "Electric"],
	["Bravent", "Meridian", "Luxury"],
	["Velmara", "Tessa", "Compact SUV"],
	["Haldric", "Sawtooth Work", "Work truck"],
	["Bravent", "Vesper Coupe", "Coupe"],
	["Orivo", "Ventra Estate", "Wagon"],
	["Haldric", "Brutano 6.4", "Muscle"],
	["Quentis", "Sovrana", "Luxury SUV"],
	["Sundale", "Minimo", "City van"],
	["Velmara", "Cordale '74", "Classic"],
]

var _player: Node
var _car: Node
var _toast_age: float = 99.0
var _pill: float = 0.0
var _mph: float = 0.0
var _unit := "MPH"
var _maker := ""
var _model := ""
var _kind := ""
var _gear := "N"
var _glass: ColorRect
var _glass_mat: ShaderMaterial
var _ink: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_glass = ColorRect.new()
	_glass.name = "SpeedGlass"
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass_mat = HudTheme.glass_material()
	_glass.material = _glass_mat
	_glass.visible = false
	add_child(_glass)
	_ink = Control.new()
	_ink.name = "Ink"
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ink.draw.connect(_draw_ink)
	add_child(_ink)


## [maker, model, class line] for a vehicle: the police and the aircraft, helicopters and
## boats (their own display names) first, then the body type's row.
static func names_for(car: Node) -> PackedStringArray:
	if car == null:
		return PackedStringArray(["", "", ""])
	if car is PoliceCar:
		var heavy: bool = car.get("heavy")
		return PackedStringArray(["Rando City Police", "Tactical Van" if heavy else "Cruiser", "POLICE"])
	if car is Aircraft or car is FlyableHeli or car is Boat:
		var dn: String = car.call("display_name")
		var cls := "AIRCRAFT" if car is Aircraft else ("HELICOPTER" if car is FlyableHeli else "BOAT")
		return PackedStringArray(["", dn, cls])
	var t: int = int(car.get("body_type"))
	return names_for_type(t)


static func names_for_type(t: int) -> PackedStringArray:
	if t < 0 or t >= MODELS.size():
		return PackedStringArray(["", "Vehicle", ""])
	var row: Array = MODELS[t]
	return PackedStringArray([row[0], row[1], str(row[2]).to_upper()])


## The speed shown for `mps` m/s: [value, unit]. Cars in mph, aircraft and boats in knots.
static func speed_reading(car: Node, mps: float) -> Array:
	if car != null and (car is Aircraft or car is FlyableHeli or car is Boat):
		return [int(round(absf(mps) * MPS_TO_KNOTS)), "KT"]
	return [int(round(absf(mps) * MPS_TO_MPH)), "MPH"]


## The selector's letter from the speed along the car's nose (m/s): D, R or N.
static func gear_letter(forward_mps: float) -> String:
	if forward_mps > 0.4:
		return "D"
	if forward_mps < -0.4:
		return "R"
	return "N"


func _process(delta: float) -> void:
	if not enabled or not is_visible_in_tree():
		return
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	var car: Node = _player.get("vehicle") if _player else null
	if forced_type >= 0:
		car = null
	if car != _car:
		_car = car
		if car != null:
			var n := names_for(car)
			_maker = n[0]
			_model = n[1]
			_kind = n[2]
			_toast_age = 0.0
	if forced_type >= 0 and _model == "":
		var n2 := names_for_type(forced_type)
		_maker = n2[0]
		_model = n2[1]
		_kind = n2[2]
		_toast_age = fade_in
	_toast_age += dt
	var driving := car != null and is_instance_valid(car) or forced_type >= 0
	_pill = move_toward(_pill, 1.0 if driving else 0.0, dt / maxf(pill_fade, 0.01))
	if forced_type >= 0:
		_mph = forced_mph
		_unit = "MPH"
		_gear = "D" if forced_mph > 0.5 else "N"
	elif car is RigidBody3D and is_instance_valid(car):
		var body := car as RigidBody3D
		var v := body.linear_velocity
		var fwd := -body.global_basis.z
		var read := speed_reading(car, v.length())
		_mph = lerpf(_mph, float(read[0]), minf(dt * 12.0, 1.0))
		_unit = read[1]
		_gear = gear_letter(v.dot(fwd))
	_layout()
	_glass.visible = _pill > 0.001
	_ink.queue_redraw()


## The name toast's amount, 0..1.
func toast_amount() -> float:
	if forced_type >= 0:
		return 1.0
	if _model == "":
		return 0.0
	return HudTheme.envelope(_toast_age, fade_in, hold, fade_out)


## Where the pill goes: left of the minimap, its bottom on the minimap's.
func pill_rect() -> Rect2:
	var view := get_viewport_rect().size
	var s := HudTheme.scale(view)
	var size := (pill_size * s).round()
	var frame := get_parent().get_node_or_null("MinimapFrame") if get_parent() else null
	var mini := Rect2(view - Vector2.ONE * 300.0 * s, Vector2.ONE * 260.0 * s)
	if frame and frame.has_method("screen_rect"):
		mini = frame.call("screen_rect")
	return Rect2(Vector2(mini.position.x - pill_gap * s - size.x, mini.end.y - size.y).round(), size)


func _layout() -> void:
	var r := pill_rect()
	var e := HudTheme.ease_out(_pill)
	_glass.position = r.position + Vector2(0.0, (1.0 - e) * 16.0 * HudTheme.scale(get_viewport_rect().size))
	_glass.size = r.size
	_glass.modulate = Color(1, 1, 1, e)
	_glass_mat.set_shader_parameter("rect_px", r.size)
	_glass_mat.set_shader_parameter("bar_corner", r.size.y * 0.3)


func _draw_ink() -> void:
	var view := get_viewport_rect().size
	var s := HudTheme.scale(view)
	var r := pill_rect()
	var e := HudTheme.ease_out(_pill)
	if e > 0.001:
		var off := Vector2(0.0, (1.0 - e) * 16.0 * s)
		var big := HudTheme.display_bold()
		var px := int(round(58.0 * s))
		var num := str(int(round(_mph)))
		var right := r.end.x - 66.0 * s
		var base := r.position.y + r.size.y * 0.66
		HudTheme.draw_tracked_right(_ink, big, num, right, base + off.y, px, 1.0 * s, Color(1, 1, 1, 0.97 * e))
		var unit_f := HudTheme.text()
		var upx := int(round(13.0 * s))
		HudTheme.draw_tracked(_ink, unit_f, _unit, Vector2(right + 9.0 * s, base - 22.0 * s + off.y), upx, 1.6 * s, Color(1, 1, 1, 0.62 * e))
		# The selector letter, in its own little ring.
		var gc := Vector2(right + 30.0 * s, base - 1.0 * s + off.y - 6.0 * s)
		_ink.draw_arc(gc, 11.0 * s, 0.0, TAU, 32, Color(1, 1, 1, 0.35 * e), maxf(1.2 * s, 1.0), true)
		var gpx := int(round(15.0 * s))
		var gw := HudTheme.display_bold().get_string_size(_gear, HORIZONTAL_ALIGNMENT_LEFT, -1, gpx).x
		var gcol := HudTheme.ACCENT if _gear == "R" else Color(1, 1, 1)
		_ink.draw_string(HudTheme.display_bold(), Vector2(gc.x - gw * 0.5, gc.y + gpx * 0.36).round(), _gear, HORIZONTAL_ALIGNMENT_LEFT, -1, gpx, Color(gcol.r, gcol.g, gcol.b, 0.95 * e))
		# The bar: how fast, out of bar_full_mph, eased so city speeds move it.
		var bx := r.position.x + 18.0 * s
		var bw := r.size.x - 36.0 * s
		var by := r.end.y - 14.0 * s + off.y
		var frac := clampf(sqrt(clampf(_mph / bar_full_mph, 0.0, 1.0)), 0.0, 1.0)
		_ink.draw_rect(Rect2(bx, by, bw, 3.0 * s), Color(1, 1, 1, 0.16 * e))
		_ink.draw_rect(Rect2(bx, by, bw * frac, 3.0 * s), Color(HudTheme.ACCENT.r, HudTheme.ACCENT.g, HudTheme.ACCENT.b, 0.9 * e))
	var a := toast_amount()
	if a > 0.001 and _model != "":
		# Maker in small tracked caps, the model in display type, the class under: right-aligned
		# to the pill, over it.
		var lift := (1.0 - a) * 14.0 * s
		var right2 := r.end.x
		var y := r.position.y - 14.0 * s + lift
		var kpx := int(round(14.0 * s))
		if _kind != "":
			HudTheme.draw_tracked_right(_ink, HudTheme.text(), _kind, right2, y, kpx, 2.2 * s, Color(1, 1, 1, 0.55 * a))
			y -= kpx * 1.5
		var mpx := int(round(40.0 * s))
		HudTheme.draw_tracked_right(_ink, HudTheme.display(), _model.to_upper(), right2, y, mpx, 1.6 * s, Color(1, 1, 1, 0.97 * a))
		y -= mpx * 0.98
		if _maker != "":
			var mkpx := int(round(15.0 * s))
			HudTheme.draw_tracked_right(_ink, HudTheme.text(), _maker.to_upper(), right2, y, mkpx, 3.0 * s, Color(HudTheme.ACCENT.r, HudTheme.ACCENT.g, HudTheme.ACCENT.b, 0.95 * a))
