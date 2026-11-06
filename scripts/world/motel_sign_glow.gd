class_name MotelSignGlow
extends RefCounted
## A Googie motel pole sign's light (rc5-googie-motel, 2026-11-06; docs/HANDOFF.md "The Googie motel
## at 21:00"). The sign was emission only: its bulbs, starburst and VACANCY neon lit nothing and had
## no air round them, so at 21:00 it read as a flat lit decal against the sky. Now it carries, in its
## own prop record (out with the sign when it is broken), NightAtmos' broad halos round the
## starburst, the arrow's chase and the VACANCY box (each in its own colour,
## sized and faded by night_halo.gdshader off the `night_atmos` global), and two coloured pools of
## light on the ground under the arrow's head and the board (light_pool.gdshader, by lamp_factor).
## All of it collapses by day. MOTEL_SIGN_GLOW=0 in the environment is the A/B.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("MOTEL_SIGN_GLOW") != "0"

const POOL_KEY := "motel_sign_pool"
## Halos: [x, y (sign space: x into the lot, y up), radius, which paint (SignKit.MOTEL_PAINT index),
## strength].
const HALOS := [
	[0.0, 12.95, 1.3, 2, 0.75],    # the starburst
	[4.25, 9.4, 0.7, 5, 0.3],      # the arrow, down its bar
	[3.6, 6.4, 0.7, 5, 0.3],
	[2.2, 4.85, 0.85, 5, 0.45],    # the arrow's head
	[1.45, 8.05, 1.5, 4, 0.7],     # the VACANCY box
]
## Pools on the ground: [x, size (m), which paint, strength].
const POOLS := [
	[2.6, 9.0, 5, 0.9],
	[1.2, 6.5, 4, 0.45],
]


## The batch instances ([key, mesh, transform, colour, custom]) of a motel sign at `xf` (its pole's
## foot, the sign's frame), variant `a`, flags (1: NO lit).
static func parts(xf: Transform3D, a: int, flags: int) -> Array:
	var out: Array = []
	if not enabled:
		return out
	var paint: Array = SignKit.MOTEL_PAINT[a % SignKit.MOTELS]
	if NightAtmos.enabled:
		for h: Array in HALOS:
			var c: Color = paint[int(h[3])]
			var at := xf * Vector3(float(h[0]), float(h[1]), 0.0)
			out.append([NightAtmos.SHOP_KEY, NightAtmos.halo_mesh(),
				Transform3D(Basis.from_scale(Vector3.ONE * float(h[2])), at), Color(c.r, c.g, c.b), Color(float(h[4]), 1.0, 0.0, 0.0)])
	for q: Array in POOLS:
		var c: Color = paint[int(q[2])]
		var s := float(q[1])
		var at := xf * Vector3(float(q[0]), 0.07, 0.0)
		out.append([POOL_KEY + str(int(q[2])) + "_" + str(a % SignKit.MOTELS), PropFactory.light_pool(c, float(q[3]), 2.0),
			Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(s, 1.0, s)), at)])
	return out
