class_name WeaponManager
extends Node3D
## Sits at the player's hand. Owns the weapons, switches between them instantly, and
## points them along the camera pitch.

@export var start_weapon: int = 0

var weapons: Array[Weapon] = []
var current: Weapon
## True while the weapon wheel (WeaponWheel) is open: the gun neither fires nor switches, but its
## own update keeps running, so a crate held by the gravity gun stays up while you choose.
var wheel_open: bool = false
var _player: Player


func _ready() -> void:
	_player = owner as Player
	if _player == null:
		_player = get_parent().get_parent() as Player
	for weapon in [AssaultRifle.new(), RocketLauncher.new(), GravityGun.new()]:
		weapon.player = _player
		weapon.visible = false
		add_child(weapon)
		weapons.append(weapon)
	equip(start_weapon)


func equip(index: int) -> void:
	if weapons.is_empty():
		return
	index = wrapi(index, 0, weapons.size())
	if current:
		if current == weapons[index]:
			return
		current.on_unequip()
	current = weapons[index]
	current.on_equip()


func current_index() -> int:
	return weapons.find(current)


func _physics_process(delta: float) -> void:
	if _player and _player.is_driving():
		return
	if wheel_open:
		if current:
			current._update(delta)
	elif Input.is_action_just_pressed("weapon_1"):
		equip(0)
	elif Input.is_action_just_pressed("weapon_2"):
		equip(1)
	elif Input.is_action_just_pressed("weapon_3"):
		equip(2)
	elif Input.is_action_just_pressed("next_weapon"):
		equip(current_index() + 1)
	elif Input.is_action_just_pressed("prev_weapon"):
		equip(current_index() - 1)
	if current and not wheel_open:
		current.tick(delta)
	# Tilt the gun with the camera so it points where you are looking.
	if _player:
		rotation.x = _player.camera_rig.rotation.x
