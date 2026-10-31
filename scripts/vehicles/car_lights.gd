class_name CarLights
extends Node3D
## Real headlights for the few cars nearest the camera (GAME_PLAN G4 / G6). Every car already
## carries its lamps as one additive mesh (PropFactory.vehicle_lights(): the glows, the beam fan
## laid on the road, the red wash behind), which is what the city looks like from any distance and
## all the web build has. On Forward+ this node adds a pool of SpotLight3Ds on top: the player's
## car always (shadowed at HIGH), and up to `budget` running traffic cars within `reach` of the
## camera, so the beams light the road, kerbs, walls, parked cars and people the way the mesh
## cannot. Each light carries a low-beam cookie (`light_projector`: a flat cut-off with the hot
## spot under it and a kick up to the right), never casts shadows except on the player's car, and
## is faded in and out by distance and when it moves to another car, so nothing pops. The player's
## car also gets a small red OmniLight3D behind, which the brake and the reversing lamps drive.
##
## One instance, made by the first Vehicle that enters the tree (ensure()), parked under the
## tree's root so a scene reload keeps it; it positions its lights from the cars' global
## transforms every frame, so origin re-centring never moves it.

## Spot lights for traffic (the player's car is extra). Quality sets it: 6 / 3 / 0 / 0.
static var budget: int = 6
## The player's car gets its headlight (Quality: off at LOWEST) and its shadow (HIGH only).
static var player_light: bool = true
static var player_shadow: bool = true
## Run on the Compatibility renderer too (opengl3 stills of the effect; never in the game, where
## the web keeps the quads).
static var force: bool = false
## Stand-in for DayNight.lamp_now where there is no DayNight (the test room's stills); < 0 off.
static var lamp_override: float = -1.0
## The low-beam cookie on the lights (off: a plain cone, the A/B).
static var cookie_enabled: bool = true
## Lights drawing this frame (the HUD and the stills report it).
static var active_count: int = 0
static var _inst: CarLights

## Traffic cars further from the camera than this get no light (m).
@export var reach: float = 60.0
## The light fades out over the last share of `reach`.
@export var fade_share: float = 0.3
## How fast a light fades in or out (1/s).
@export var fade_speed: float = 4.0
## Seconds between picks of the nearest cars.
@export var pick_interval: float = 0.15
## Traffic headlight: range (m), cone half-angle (degrees), energy, how far it dips (degrees).
@export var spot_range: float = 28.0
@export var spot_angle: float = 30.0
@export var spot_energy: float = 6.0
@export var spot_dip: float = 7.0
## How hard a traffic headlight fades toward the edge of its cone (it has no cookie).
@export var spot_softness: float = 1.8
## The player's car: a longer, brighter beam.
@export var player_range: float = 44.0
@export var player_angle: float = 40.0
@export var player_energy: float = 24.0
## The player's beam dips less: its cookie draws the cut-off.
@export var player_dip: float = 1.0
## The player's red glow behind: energy with the tail lamps on, added on the brake, on reversing.
@export var rear_energy: float = 0.1
@export var rear_brake_energy: float = 1.2
@export var rear_reverse_energy: float = 1.0
@export var headlight_color: Color = Color(1.0, 0.95, 0.86)

var _slots: Array = [] # each [SpotLight3D, Vehicle or null, weight]
var _player_spot: SpotLight3D
var _player_rear: OmniLight3D
var _player_w: float = 0.0
var _wanted: Array = []
var _pick_t: float = 0.0
var _cookie: ImageTexture


## Makes the one instance, the first time a car enters the tree.
static func ensure(from: Node) -> void:
	if _inst != null and is_instance_valid(_inst):
		return
	if not supported():
		return
	var tree := from.get_tree()
	if tree == null:
		return
	_inst = CarLights.new()
	_inst.name = "CarLights"
	tree.root.add_child.call_deferred(_inst)


## Forward+ only (the clustered renderer takes a few dozen lights in its stride; the Compatibility
## renderer lights per object and the web keeps the quads), unless forced for a still.
static func supported() -> bool:
	if force:
		return true
	if OS.has_feature("web"):
		return false
	return RenderingServer.get_current_rendering_method() == "forward_plus"


static func instance() -> CarLights:
	return _inst if _inst != null and is_instance_valid(_inst) else null


func _ready() -> void:
	_cookie = low_beam_cookie()
	_player_spot = _make_spot(true)
	_player_rear = OmniLight3D.new()
	_player_rear.name = "PlayerRear"
	_player_rear.omni_range = 5.0
	_player_rear.omni_attenuation = 1.6
	_player_rear.shadow_enabled = false
	_player_rear.light_specular = 0.3
	_player_rear.visible = false
	add_child(_player_rear)


func _exit_tree() -> void:
	if _inst == self:
		_inst = null
		active_count = 0


## The low-beam pattern as a projector texture: a flat cut-off a little above the middle with the
## US kick up on the right, the hot spot just under it, a soft fall to the sides and the foreground.
## u runs across the beam (left to right as the driver sees it), v from the top of the cone down.
static func low_beam_cookie() -> ImageTexture:
	var w := 128
	var h := 64
	# RGBA, not L8: the projector atlas reads a one-channel image as red only.
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for j in h:
		var v := (float(j) + 0.5) / float(h) * 2.0 - 1.0 # -1 top .. 1 bottom
		for i in w:
			var u := (float(i) + 0.5) / float(w) * 2.0 - 1.0 # -1 left .. 1 right
			# The cut-off: level on the left, rising 15 degrees on the right of centre.
			var cut := -0.08 - maxf(u - 0.05, 0.0) * 0.27
			var above := smoothstep(cut - 0.12, cut + 0.1, v)
			# The hot spot, a wide ellipse just under the cut-off and a touch right.
			var hx := (u - 0.08) / 0.55
			var hy := (v - 0.12) / 0.35
			var hot := exp(-(hx * hx + hy * hy) * 1.4)
			# The spread: wide and flat, dimmer toward the edges and the bumper.
			var sx := u / 1.0
			var sy := (v - 0.25) / 0.85
			var spread := clampf(1.0 - (sx * sx * 0.8 + sy * sy), 0.0, 1.0)
			var lum := (0.12 + 0.88 * above) * (0.35 * spread + 0.75 * hot)
			img.set_pixel(i, j, Color(lum, lum, lum))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _make_spot(player: bool) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.name = "PlayerHeadlight" if player else "Headlight"
	s.light_color = headlight_color
	s.spot_range = player_range if player else spot_range
	s.spot_angle = player_angle if player else spot_angle
	s.spot_attenuation = 0.85
	s.spot_angle_attenuation = 0.7 if player else spot_softness
	# Only on a shadowed light: Godot maps a spot's projector through its shadow matrix, which
	# an unshadowed spot never gets, so a cookie on one draws NOTHING (measured on lavapipe
	# Forward+: the traffic cars' cookie lights were black). Traffic lights are soft plain cones.
	s.light_projector = _cookie if cookie_enabled and player else null
	s.light_specular = 0.6
	s.shadow_enabled = false
	s.shadow_bias = 0.06
	s.shadow_normal_bias = 1.5
	s.shadow_blur = 1.5
	s.light_energy = 0.0
	s.visible = false
	add_child(s)
	return s


func _process(delta: float) -> void:
	var lamp := lamp_override if lamp_override >= 0.0 else DayNight.lamp_now
	var cam := get_viewport().get_camera_3d()
	_pick_t -= delta
	if _pick_t <= 0.0:
		_pick_t = pick_interval
		_pick(cam, lamp)
	var count := 0
	var rate := fade_speed * delta
	# Traffic slots: a car no longer wanted fades out before its light moves on. Cars are held
	# untyped and tested before use: a traffic car can be freed, or pooled (out of the tree),
	# between two picks.
	for slot: Array in _slots:
		var car: Variant = slot[1]
		if car != null and not _usable(car):
			# Gone, pooled or dark: its light goes at once (there is nothing left to light from).
			slot[1] = null
			slot[2] = 0.0
			car = null
		var target := 0.0
		if car != null and _wanted.has(car):
			target = _distance_weight(car, cam)
		slot[2] = move_toward(float(slot[2]), target, rate)
		if car != null and float(slot[2]) <= 0.0 and target <= 0.0:
			slot[1] = null
			car = null
		count += _place(slot[0], car, float(slot[2]) * lamp, spot_energy, false)
	# Hand free slots to wanted cars that have none.
	for car: Variant in _wanted:
		if not _usable(car) or _slot_of(car) >= 0:
			continue
		var free := -1
		for i in _slots.size():
			if _slots[i][1] == null:
				free = i
				break
		if free < 0 and _slots.size() < budget:
			_slots.append([_make_spot(false), null, 0.0])
			free = _slots.size() - 1
		if free >= 0:
			_slots[free][1] = car
			_slots[free][2] = 0.0
	# Over budget after a Quality change: drop the extra slots once they are dark.
	while _slots.size() > budget and _slots.back()[1] == null:
		(_slots.pop_back()[0] as Node).queue_free()
	# The player's car.
	var mine := _player_car()
	_player_w = move_toward(_player_w, 1.0 if mine != null and player_light else 0.0, rate)
	if _player_spot.shadow_enabled != player_shadow:
		_player_spot.shadow_enabled = player_shadow
	count += _place(_player_spot, mine, _player_w * lamp, player_energy, true)
	_place_rear(mine, _player_w * lamp)
	active_count = count


## Picks the cars that should have a light: running, lamps whole, within reach, nearest first
## with cars behind the camera counted further away.
func _pick(cam: Camera3D, lamp: float) -> void:
	_wanted.clear()
	if cam == null or lamp <= 0.01 or budget <= 0:
		return
	var eye := cam.global_position
	var look := -cam.global_basis.z
	var scored: Array = []
	for node in get_tree().get_nodes_in_group("vehicle"):
		var car := node as Vehicle
		if car == null or car is Aircraft or car.driver != null or not car.has_headlights():
			continue
		var to := car.global_position - eye
		var d := to.length()
		if d > reach:
			continue
		# A car behind the camera still lights the road the camera sees, but less of it.
		if to.dot(look) < -8.0:
			d *= 1.8
		scored.append([d, car])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in mini(scored.size(), budget):
		_wanted.append(scored[i][1])


## A car a light may follow: still there, in the tree (not in the traffic pool), lamps on.
static func _usable(car: Variant) -> bool:
	return car != null and is_instance_valid(car) and (car as Node).is_inside_tree() and (car as Vehicle).has_headlights()


func _slot_of(car: Variant) -> int:
	for i in _slots.size():
		if _slots[i][1] == car:
			return i
	return -1


func _distance_weight(car: Node3D, cam: Camera3D) -> float:
	if cam == null:
		return 0.0
	var d := car.global_position.distance_to(cam.global_position)
	return 1.0 - smoothstep(reach * (1.0 - fade_share), reach, d)


func _player_car() -> Vehicle:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return null
	# The player's own car (Player.vehicle). Tools that stand a plain node in for the player
	# seat it as some car's driver, so only for one of those is the fleet searched.
	var car: Variant = p.get("vehicle")
	if not ("vehicle" in p):
		for node in get_tree().get_nodes_in_group("vehicle"):
			if (node as Vehicle) != null and (node as Vehicle).driver == p:
				car = node
				break
	if car == null or not is_instance_valid(car) or car is Aircraft or (car as Vehicle).driver != p or not _usable(car):
		return null
	return car


## Puts `light` at the front of `car`, dipped, at `level` x `energy`. Returns 1 if it draws.
func _place(light: SpotLight3D, car_v: Variant, level: float, energy: float, player: bool) -> int:
	if car_v == null or level <= 0.001 or not _usable(car_v):
		if light.visible:
			light.visible = false
		return 0
	var car := car_v as Vehicle
	light.global_transform = car.global_transform * car.headlight_transform(player_dip if player else spot_dip)
	light.light_energy = energy * level * car.headlight_share()
	if player:
		light.spot_range = player_range
		light.spot_angle = player_angle
		var cookie := _cookie if cookie_enabled and light.shadow_enabled else null
		if light.light_projector != cookie:
			light.light_projector = cookie
	if not light.visible:
		light.visible = true
	return 1


func _place_rear(car: Vehicle, level: float) -> void:
	if car == null or level <= 0.001 or not _usable(car):
		_player_rear.visible = false
		return
	var t := car.tail_point()
	_player_rear.global_position = car.global_transform * t
	var red := rear_energy + (rear_brake_energy if car.light_brake else 0.0)
	var white := rear_reverse_energy if car.light_reverse else 0.0
	var total := red + white
	_player_rear.light_color = Color(1.0, 0.1, 0.05).lerp(Color(1.0, 0.95, 0.9), white / maxf(total, 0.001))
	_player_rear.light_energy = total * level
	_player_rear.visible = true
