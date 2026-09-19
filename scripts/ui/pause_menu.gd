extends CanvasLayer
## Pause menu: Esc toggles it. Resume, a seed field that rebuilds the city, and quit.

@onready var panel: Control = $Panel
@onready var seed_edit: LineEdit = $Panel/Box/SeedRow/SeedEdit
@onready var info: Label = $Panel/Box/Info

var _open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	var city := get_tree().get_first_node_in_group("city")
	if city:
		seed_edit.text = str(city.get("world_seed"))
	$Panel/Box/Resume.pressed.connect(close)
	$Panel/Box/SeedRow/Apply.pressed.connect(_apply_seed)
	$Panel/Box/Quit.pressed.connect(func(): get_tree().quit())
	seed_edit.text_submitted.connect(func(_t): _apply_seed())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		if _open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	info.text = "Paused. Change the seed and press Rebuild for a brand new city."


func close() -> void:
	_open = false
	panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_seed() -> void:
	var text := seed_edit.text.strip_edges()
	var new_seed := text.to_int() if text.is_valid_int() else hash(text)
	WorldState.pending_seed = new_seed
	WorldState.reset_destruction()
	get_tree().paused = false
	_open = false
	get_tree().reload_current_scene()
