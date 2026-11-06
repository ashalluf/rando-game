extends Node
## The _check() tests/freight_checks.gd calls back, for tools/freight/checks.gd.
var fails := 0


func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1
