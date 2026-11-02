class_name InteriorsGlass
extends RefCounted
## The glass at arm's length (docs/HANDOFF.md "The glass at arm's length"): what a storefront and a
## lit window show from two to six metres off. People in the shops - a clerk at the till, shoppers
## down the aisles and at the shelves, a barista behind the counter, diners on the cafe's chairs, a
## customer in the barber's chair, tellers, a lobby's guard - ray-marched as bodies (head, shoulders,
## arms, legs that swing as they walk) in shaders/interior_people.gdshaderinc, laid out against the
## fittings shop_interior() traces (shaders/shop_interior.gdshaderinc, shop_person()). The same
## bodies stand in for the capsules in the homes and offices near the camera
## (shaders/window_rooms.gdshaderinc).
## `INTERIORS_GLASS=0` in the environment turns it off (the A/B): the `interiors_glass` global goes
## to 0 and the glass is what it was.

static var enabled: bool = OS.get_environment("INTERIORS_GLASS") != "0"


## Pushes the switch to the shaders (DayNight._ready()).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("interiors_glass", 1.0 if enabled else 0.0)


static func set_enabled(on: bool) -> void:
	enabled = on
	install()
