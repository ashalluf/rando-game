class_name PoliceGun
extends Weapon
## An officer's gun: a service pistol, or at five stars a short carbine. Only a model and the
## grips - the officer does the shooting (PoliceOfficer._shoot) - so it is never in a
## WeaponManager and never reads input. A Weapon so the same hand IK that holds the hero's guns
## (Avatar.hold_gun) holds this one: the hands go on `grip_right` / `grip_left`, the gun rides
## at `hold_hip` and comes up to `hold_aim`.

## Pistol (false) or carbine (true). Set before the gun joins the tree.
var carbine: bool = false

const STEEL := Color(0.075, 0.075, 0.08)
const POLY := Color(0.11, 0.11, 0.115)
const PARK := Color(0.16, 0.155, 0.15)


func _init() -> void:
	display_name = "Service pistol"
	lock_on = false
	alarm_radius = 0.0
	kick_distance = 0.04


func _ready() -> void:
	# Square to the target (the grips below were set on a square chest): no bladed stance.
	hold_twist = Vector2.ZERO
	if carbine:
		display_name = "Carbine"
		# The AK's grips and carry suit a carbine of the same size; only the pistol needs its own.
	else:
		# Two hands on a pistol: the right wrist behind the grip, the left cupped under and
		# beside it. Aimed, the arms reach out almost straight (0.45 m of the 0.52 m reach).
		grip_right = Vector3(0.0, -0.075, 0.085)
		grip_left = Vector3(-0.035, -0.09, 0.07)
		grip_right_fingers = Vector3(0.0, -0.75, -0.65)
		grip_right_palm = Vector3(-1.0, 0.0, 0.0)
		grip_left_fingers = Vector3(0.55, -0.55, -0.6)
		grip_left_palm = Vector3(0.85, 0.3, 0.0)
		hold_hip = Vector3(-0.13, -0.33, -0.28)
		hold_aim = Vector3(-0.17, -0.02, -0.47)
		hold_hip_rot = Vector3(-52.0, 12.0, 0.0)
	super._ready()


func _build_model() -> void:
	if carbine:
		_build_carbine()
		return
	# A compact service pistol, about 19 cm: slide, frame and dust cover, grip, trigger guard.
	_box(Vector3(0.028, 0.030, 0.186), STEEL, Vector3(0.0, 0.012, -0.045), Vector3.ZERO, 0.8, 0.4)
	_box(Vector3(0.026, 0.020, 0.150), POLY, Vector3(0.0, -0.012, -0.055), Vector3.ZERO, 0.0, 0.7)
	_box(Vector3(0.026, 0.105, 0.046), POLY, Vector3(0.0, -0.062, 0.030), Vector3(16.0, 0.0, 0.0), 0.0, 0.75)
	_box(Vector3(0.022, 0.008, 0.050), POLY, Vector3(0.0, -0.034, -0.030), Vector3.ZERO, 0.0, 0.7)
	_box(Vector3(0.010, 0.010, 0.010), PARK, Vector3(0.0, 0.031, -0.132), Vector3.ZERO, 0.5, 0.5)
	_make_muzzle(Vector3(0.0, 0.012, -0.142))


func _build_carbine() -> void:
	# A short black carbine: receiver, handguard, barrel, grip, magazine, collapsed stock.
	_box(Vector3(0.050, 0.070, 0.260), POLY, Vector3(0.0, 0.0, -0.02), Vector3.ZERO, 0.2, 0.6)
	_box(Vector3(0.052, 0.058, 0.200), PARK, Vector3(0.0, 0.004, -0.245), Vector3.ZERO, 0.4, 0.55)
	_cylinder(0.0085, 0.20, STEEL, Vector3(0.0, 0.006, -0.435), 0.8, -1.0, 0.4)
	_box(Vector3(0.030, 0.095, 0.045), POLY, Vector3(0.0, -0.072, 0.080), Vector3(18.0, 0.0, 0.0), 0.0, 0.75)
	_box(Vector3(0.026, 0.120, 0.060), STEEL, Vector3(0.0, -0.090, -0.070), Vector3(-10.0, 0.0, 0.0), 0.5, 0.5)
	_box(Vector3(0.044, 0.060, 0.170), POLY, Vector3(0.0, -0.020, 0.200), Vector3.ZERO, 0.0, 0.7)
	_box(Vector3(0.022, 0.030, 0.090), STEEL, Vector3(0.0, 0.052, -0.030), Vector3.ZERO, 0.6, 0.5)
	_make_muzzle(Vector3(0.0, 0.006, -0.54))
