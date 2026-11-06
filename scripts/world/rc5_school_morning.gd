class_name RcSchoolMorning
extends RefCounted
## The elementary school's morning drop-off (wave 8 refcam5 `school_morning`, docs/HANDOFF.md "The
## school drop-off at 07:50"). What that view found and fixed, each behind RC5_SCHOOL_MORNING=0 (the
## A/B: exactly main):
##  1. The buses: a school whose loading zone is on its -x / -z kerb never parked them (that kerb
##     belongs to the chunk before the school's: Schools.park_kerb_buses()).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var _on: int = -1


## RC5_SCHOOL_MORNING=0 turns every part off.
static func enabled() -> bool:
	if _on < 0:
		_on = 0 if OS.get_environment("RC5_SCHOOL_MORNING") == "0" else 1
	return _on == 1
