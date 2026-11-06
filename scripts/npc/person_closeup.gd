class_name PersonCloseup
extends RefCounted
## A person at arm's length (refcam `person_closeup` in tools/refcams/cameras_w6.json, docs/HANDOFF.md
## "A person at arm's length"): what a crowd member gave away at 1.6 m, fixed where it is made.
##  - the stance: IdleRelax (the library idles' fighter stance -> arms by the thighs, feet in)
##  - the shopping bag: from the fist, cords meeting in the hand (CrowdLife.prop_mesh / BAG_GRIP)
##  - the hair: the shine broken into strands and clumps (crowd_hair.gdshader `strand_detail`)
##  - the lips: the photographed salmon gloss toned to a lip (character.gdshader `lip_tame`)
## PERSON_CLOSEUP=0 in the environment turns all of it off (the A/B; IDLE_RELAX=0 the stance alone).

## crowd_hair.gdshader's strand_detail and character.gdshader's lip_tame when on.
const STRAND_DETAIL := 1.0
const LIP_TAME := 1.0

static var _on: int = -1


static func enabled() -> bool:
	if _on < 0:
		_on = 0 if OS.get_environment("PERSON_CLOSEUP") == "0" else 1
	return _on == 1
