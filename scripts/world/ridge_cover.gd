class_name RidgeCover
extends Node
## Under a FULL chunk that builds some of the ridges in detail (RidgeBuild): while the chunk is
## drawn, RidgeSystem hides the far versions of those towers, masts and sites (`ids`, Ridges.far_id).

var ids: Array[int] = []
var _on := false


func _enter_tree() -> void:
	_sync()


func _exit_tree() -> void:
	_apply(false)


func _ready() -> void:
	var p := get_parent() as Node3D
	if p and not p.visibility_changed.is_connected(_sync):
		p.visibility_changed.connect(_sync)
	_sync()


func _sync() -> void:
	var p := get_parent() as Node3D
	_apply(p != null and p.is_inside_tree() and p.is_visible_in_tree())


func _apply(on: bool) -> void:
	if on == _on:
		return
	_on = on
	for id in ids:
		var n: int = int(RidgeSystem.covered.get(id, 0)) + (1 if on else -1)
		if n <= 0:
			RidgeSystem.covered.erase(id)
		else:
			RidgeSystem.covered[id] = n
	RidgeSystem.dirty = true
