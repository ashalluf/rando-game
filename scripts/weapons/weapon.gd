class_name Weapon
extends Node3D
## Base class for held weapons. Unlimited ammo, instant switching.
## Subclasses build a primitive model in _build_model() and implement _fire(aim).
## `aim` is the dictionary from Player.get_aim(): origin, direction, point, collider, normal.

@export_group("Weapon")
@export var display_name: String = "Weapon"
## Shots per second.
@export var fire_rate: float = 5.0
## Hold the trigger to keep firing.
@export var automatic: bool = false
## How far the gun kicks back per shot (meters).
@export var kick_distance: float = 0.12
## How fast the gun settles back after a kick.
@export var kick_recover_speed: float = 14.0
## Camera pitch kick per shot (degrees).
@export var camera_kick_deg: float = 0.5
## People within this many metres of the shooter panic and run when it fires (0 = a quiet gun).
@export var alarm_radius: float = 45.0
## How many of the newly frightened scream per shot.
@export var alarm_screams: int = 3
## Holding aim (alt_fire) with this gun pulls the camera over the shoulder and locks onto the
## target nearest the crosshair (Player.lock_on). Off for a gun whose alt fire does something.
@export var lock_on: bool = true

@export_group("Hold")
## Where the right and left WRISTS go on this gun, in its own space (forward -Z): behind the
## pistol grip, and under the handguard. Two-bone IK pulls the hero's hands there
## (Avatar.hold_gun), so the gun is held whatever the legs are doing. The defaults are the AK.
@export var grip_right: Vector3 = Vector3(0.03, -0.075, 0.14)
@export var grip_left: Vector3 = Vector3(-0.04, -0.075, -0.12)
## Which way each hand's fingers run and its palm faces, in the gun's space: the right hand
## round the pistol grip (fingers down and forward, palm against the grip's right side), the
## left under the handguard (palm up, fingers wrapping its right side).
@export var grip_right_fingers: Vector3 = Vector3(0.0, -0.6, -0.8)
@export var grip_right_palm: Vector3 = Vector3(-1.0, 0.0, 0.0)
@export var grip_left_fingers: Vector3 = Vector3(0.7, 0.2, -0.7)
@export var grip_left_palm: Vector3 = Vector3(0.0, 1.0, 0.0)
## Where the gun's origin sits relative to the hero's right shoulder joint (in the body's
## space: +X right, +Y up, -Z forward), carried at the hip and raised to aim. Everything the
## hands hold has to be within an arm's reach of its shoulder (0.52 m to the wrist on these
## rigs): past that the arm goes dead straight and the hand stops short of the grip.
@export var hold_hip: Vector3 = Vector3(-0.12, -0.27, -0.26)
@export var hold_aim: Vector3 = Vector3(-0.10, -0.05, -0.36)
## The carry angle at the hip (degrees: muzzle down, then across the body to the left) - low
## ready. Raised to aim the gun turns straight along the camera.
@export var hold_hip_rot: Vector3 = Vector3(-24.0, 20.0, 0.0)
## How far the hero's chest turns toward the gun side behind it, at the hip and aimed
## (degrees; AimTwist): the bladed stance that brings the support hand within reach.
@export var hold_twist: Vector2 = Vector2(12.0, 30.0)
## How far each finger joint closes round this gun (knuckle, middle, tip; degrees), for a rig
## with finger bones (the hero): the right hand's middle, ring and little fingers round the
## pistol grip, its index on the trigger, its thumb; the left hand's fingers and thumb round
## what it holds. Fitted per gun by tools/grip_fit.gd.
@export var curl_right: Vector3 = Vector3(62.0, 78.0, 45.0)
@export var curl_trigger: Vector3 = Vector3(22.0, 38.0, 20.0)
@export var curl_thumb: Vector3 = Vector3(15.0, 25.0, 20.0)
@export var curl_left: Vector3 = Vector3(62.0, 78.0, 45.0)
@export var curl_left_thumb: Vector3 = Vector3(15.0, 25.0, 20.0)
## How far the right and left thumbs roll across the grip at their base (degrees; the
## opposition that wraps a thumb round the far side, which curling alone cannot do).
@export var thumb_wrap: Vector2 = Vector2.ZERO

var player: Player
## Where shots and effects start. Set by _build_model().
var muzzle: Node3D
var _cooldown: float = 0.0
## True while the last trigger pull was refused because the shot would reach a sanctuary.
var blocked_by_sanctuary: bool = false
var _kick: float = 0.0
var _rest_position: Vector3


func _ready() -> void:
	_rest_position = position
	_build_model()
	if muzzle == null:
		muzzle = self


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-kick_recover_speed * delta))
	position = _rest_position + Vector3(0.0, 0.0, _kick)


## Called by the WeaponManager every physics tick while this weapon is equipped.
func tick(delta: float) -> void:
	var wants_fire := Input.is_action_pressed("fire") if automatic else Input.is_action_just_pressed("fire")
	# A sanctuary (the masjid) is never shot at: not with the crosshair on it, not through it,
	# not with a blast landing beside it, and not from its own grounds. The shot is simply not
	# fired - no recoil, no alarm, no cooldown spent. See Sanctuary.
	var aim := {}
	if wants_fire and _cooldown <= 0.0:
		aim = player.get_aim()
		var splash: float = float(get("explosion_radius")) if get("explosion_radius") != null else 0.0
		if Sanctuary.blocks_fire(player, aim, splash):
			wants_fire = false
			blocked_by_sanctuary = true
		else:
			blocked_by_sanctuary = false
	if wants_fire and _cooldown <= 0.0:
		_cooldown = 1.0 / fire_rate
		_kick = kick_distance
		_fire(aim)
		player.camera_rig.kick(camera_kick_deg)
		player.notify_fired()
		Pedestrian.alarm(get_tree(), player.global_position, alarm_radius, alarm_screams)
	if Input.is_action_just_pressed("alt_fire"):
		_alt_fire(player.get_aim())
	_update(delta)


func on_equip() -> void:
	visible = true


func on_unequip() -> void:
	visible = false


# --- Overridables ----------------------------------------------------------------

func _build_model() -> void:
	pass


func _fire(_aim: Dictionary) -> void:
	pass


func _alt_fire(_aim: Dictionary) -> void:
	pass


func _update(_delta: float) -> void:
	pass


# --- Model helpers ---------------------------------------------------------------

func _mat(color: Color, metallic: float = 0.0, roughness: float = 0.7) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _box(size: Vector3, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, metallic: float = 0.0, roughness: float = 0.7) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _mat(color, metallic, roughness)
	mesh.position = pos
	mesh.rotation_degrees = rot_deg
	add_child(mesh)
	return mesh


## Cylinder along local Z (pointing forward, -Z) after rotation.
func _cylinder(radius: float, length: float, color: Color, pos: Vector3, metallic: float = 0.0, top_radius: float = -1.0, roughness: float = 0.7, rot_deg: Vector3 = Vector3(90.0, 0.0, 0.0)) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = radius
	cyl.top_radius = radius if top_radius < 0.0 else top_radius
	cyl.height = length
	cyl.radial_segments = 10
	mesh.mesh = cyl
	mesh.material_override = _mat(color, metallic, roughness)
	mesh.position = pos
	mesh.rotation_degrees = rot_deg
	add_child(mesh)
	return mesh


func _make_muzzle(pos: Vector3) -> void:
	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = pos
	add_child(muzzle)
