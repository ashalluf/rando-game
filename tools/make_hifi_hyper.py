#!/usr/bin/env python3
"""High-fidelity HYPERCAR body, built as a SUBDIVISION SURFACE in Blender's bpy module.

    python3 tools/make_hifi_hyper.py                 # build + export + verify
    python3 tools/make_hifi_hyper.py --no-verify     # skip re-reading the .glb

Writes assets/models/hifi_hyper_coupe.glb.

WHY THIS EXISTS
---------------
The owner looked at the generated cars and said they "look like N64 cars" and that everything
"still looks blocky", while liking the paint. That is a GEOMETRY verdict, not a shader one: the
old bodies were ~32 k-triangle low-poly cages with a 3 mm bevel, and at that density every curved
panel is a fan of flat facets. Faceting is a *shading normal* problem and the normals are wrong
because the surface is wrong. The only fix is to build a coarse all-quad CONTROL CAGE whose edge
flow follows the form and put a CATMULL-CLARK SUBDIVISION SURFACE on it. Sharpness then comes
from HOLDING LOOPS and EDGE CREASES, never from leaving an edge unsubdivided.

THE ONE IDEA THE WHOLE FILE RESTS ON
------------------------------------
The body shell is one structured quad grid, indexed by (f, g):

    f   longitudinal station, in metres, tail (-2.18) to nose (+2.15)
    g   position round the cross-section: 0 = floor centreline, 16 = right shoulder (widest),
        32 = roof centreline, 48 = left shoulder, wrapping at 64.

Because the grid is structured and the feature tables choose where its lines fall, EVERY feature
is the same operation on index ranges:

  * a SHUT LINE is FOUR grid lines - outer lip, floor, floor, outer lip - with the two middle
    ones pushed 5 mm in, the floor faces between them given the dark TRIM slot, and all four
    loops carrying a full EDGE CREASE. All three parts matter. The first version of this file
    used three lines, no crease and no material change, and shipped a car with literally zero
    visible panel gaps: Catmull-Clark averaged the 4.8 mm dip down to about 2 mm of soft ripple,
    3 mm of it was sub-pixel at any distance a player sees a car from, and a reviewer measuring
    the export found 90 concave sharp edges on 187,000 - all of them vent lips. The crease is
    what keeps the walls vertical, the trim floor is what makes the gap a line you can see, and
    5.6 mm of dark floor is the narrowest that survives a screen pixel.
  * an OPENING (intakes, grille, lamps, glass, deck louvres) is "delete the faces in this (f, g)
    rectangle, extrude the border inward twice, cap it". That gives a real mouth with visible
    inner walls. The cut loop carries an edge CREASE so the rim does not melt under subdivision.
  * a WHEEL ARCH is the same delete-and-extrude with the cut boundary snapped onto the arch circle
    first, and the skin just outside it pushed proud to make the arch LIP.
  * a CHANNEL (the deep sculpt ahead of the rear wheels) is a wide, smooth, tapered depression in
    the same (f, g) space, and - unlike a shut line - it is deep enough that the surface NORMAL
    has to be recomputed from the displaced surface, which is what makes it catch light as a
    hollow instead of as a decal.

So the tables (OPENINGS, GROOVES, CHANNELS, SCOOP) are the design. Nothing is placed by eye.

WHAT IS NOT PART OF THE SHELL
-----------------------------
Every aero element is real, separate, two-sided geometry with thickness, because that is what the
brief asked for and because a wing modelled as a lump on the bodywork is the single loudest "toy"
tell there is. The rear wing is a lofted NACA-style aerofoil with endplates on SWAN-NECK struts
swept from the deck; the splitter is a swept plate with upswept edges, fences and dive planes;
the diffuser is a curved expansion ramp with real strakes; the roof scoop is a duct with a rim
and inner walls you can see down. They are built from foil/sweep/plate primitives, not boxes.

And the WHEELS, which the first version of this file did not have AT ALL. Not a crude wheel -
none: the only geometry wearing the `tyre` slot was the lining of the arch wells, which is how a
reviewer came to measure "the wheel" as an out-of-round 0.83-0.90 m egg. It was measuring the
arch. That matters beyond the render, because Vehicle._add_wheel() ends with
`if _has_model: return  # the generated models have their own wheels` - a body model that does
not carry wheels puts a car on the street with nothing under the arches. build_wheels() now
makes four: a tyre with a bulged sidewall and rounded shoulders, an alloy with a flange lip and
a barrel, ten dished spokes with gaps you can see through, a centre-lock nut, a cross-drilled
vented disc with real holes bridged front to back, and a caliper. Every radius comes off TYRE_R,
so the wheel is exactly 0.720 m and exactly round, and its contact patch is the lowest point of
the whole model - which is also what stopped the splitter and skirts sitting 43 mm underground.

WHEEL POSE, if this model is ever wired into Vehicle.BODY_MODELS: half-track 0.821 front /
0.796 rear (the outer sidewall is at 0.972 either side), axles at y +/-1.350, hub height 0.360,
tyre radius 0.360, section width 0.302 front and 0.352 rear.

CONVENTIONS THE GAME DEPENDS ON
-------------------------------
Authored X = lateral, Y = longitudinal with the NOSE AT +Y, Z = up, ground at Z = 0. glTF's Y-up
conversion turns that into Godot's X right, Y up, nose at -Z, which is the game's forward.
Vehicle._add_body_model() scales the model so its longest horizontal axis equals the chassis
length and centres it on its own bounding box, and Vehicle._wheel_slots uses ONE wheel_z for both
axles - so the arches MUST be symmetric about the bbox centre. That is why the splitter tip and
the rear wing's trailing edge both land on |y| = 2.300: they are the two extremes of the bounding
box, so putting them at equal distances is what keeps the wheels centred in their own arches.

Material slots are a contract: index 0 is "paint" and the game tints ONLY that slot. Nothing that
is not bodywork may be merged into it. The six are paint / glass / trim / tyre / light_front /
light_rear and nothing else. `trim` carries a lot: lacquered carbon aero, intake interiors, the
arch linings, the alloys, the brake iron and the floors of the shut lines - which is why it is a
dark satin semi-metal rather than the dead matte black it started as, because an alloy wheel that
never catches a highlight reads as painted plastic whatever shape it is.

Everything is exported single-sided (glTF doubleSided=false): the shell is closed, and two-sided
materials both waste fill rate and let you see interior backfaces through the intakes. Glass is
alphaMode BLEND with transmission, not the opaque near-black slab it used to be - which is why
build_interior() exists, because transparent glass over an empty shell shows you the road through
the far door. And the mesh carries a UV set; without one, Godot's meshes/ensure_tangents=true
invents tangents from nothing and every normal map, dirt map, livery or decal is broken before it
starts.

ORIGINALITY
-----------
A CLASS study, not a copy. Cab-forward mid-engine proportions, a dished engine deck between
flying buttresses, a roof snorkel, a high swan-neck wing - none of that belongs to anybody. No
badge, no manufacturer's grille or lamp signature; the badge positions are empty recesses.
Name: "Ardent Kestrel HX". Invented.
"""

import math
import os
import sys

import bpy  # noqa: E402  (bpy must come before bmesh/mathutils)
import bmesh
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "assets", "models")
PREFIX = "hifi_hyper_"

# --- the contract with the game -------------------------------------------------------------
# name, colour, metallic, roughness. Index 0 is the tinted paint.
#
# THE COLOURS ARE WHAT GODOT MUST RENDER, NOT WHAT GOES IN THE FILE. Godot's glTF importer takes
# the linear baseColorFactor and sRGB-ENCODES it into StandardMaterial3D.albedo_color, which the
# shader then uses as linear - so an authored 0.026 comes out of the engine at 0.176, seven times
# too light. Measured, not guessed: a render of the first export put the wing at sRGB 81/255,
# which is the 0.176 answer, and the aero read as light grey plastic instead of carbon. So the
# table below is the value we want on screen and make_materials() writes srgb_to_linear() of it
# into the file, which cancels the importer exactly.
SLOTS = [
    # name,        colour,                 metal, rough, alpha
    ("paint",       (0.80, 0.81, 0.83), 0.85, 0.26, 1.0),
    # Glass is BLEND, not OPAQUE. It used to ship as an opaque near-black slab, which is exactly
    # what a cheap model does. alpha 0.40 is dark enough to read as a privacy-tinted screen and
    # light enough that you can see the cockpit tub through it - which is why there IS a cockpit
    # tub now: transparent glass over an empty shell shows you the inside of the far door.
    ("glass",       (0.055, 0.062, 0.074), 0.00, 0.06, 0.40),
    # Trim is carbon fibre, dark anodised alloy and brake iron all at once. It used to be a dead
    # matte dielectric; a touch of metal and a tighter roughness is what lets a wheel rim read as
    # metal instead of as painted plastic, and carbon under lacquer is semi-gloss anyway.
    ("trim",        (0.038, 0.038, 0.043), 0.26, 0.48, 1.0),
    ("tyre",        (0.016, 0.016, 0.018), 0.00, 0.90, 1.0),
    ("light_front", (0.46, 0.50, 0.56), 0.10, 0.05, 1.0),
    ("light_rear",  (0.44, 0.030, 0.028), 0.00, 0.09, 1.0),
]
PAINT, GLASS, TRIM, TYRE, LIGHT_F, LIGHT_R = range(6)

# --- stance ---------------------------------------------------------------------------------
# The wheel is 0.720 m across, dead round, and its contact patch is the LOWEST point of the whole
# model. Everything else - splitter, skirts, diffuser - has to clear it, or the car is parked in
# the tarmac. That is a hard invariant and verify() checks it.
TYRE_R = 0.360           # wheel radius: a 0.720 m wheel, exactly the spec
HUB_Z = TYRE_R           # wheel centre height, so the contact patch lands on z = 0
AXLE = 1.350             # arch centres, symmetric about the bbox centre (wheelbase 2.70)
ARCH_R = 0.395           # arch opening radius: 3.5 cm of gap over the 0.36 m tyre
RIM_R = 0.262            # alloy outer diameter 0.524 m - a 21 inch wheel under a 0.72 m tyre
TYRE_W = (0.302, 0.352)  # tread width, front and rear. The rear is wider; it always is.
TYRE_OUT = 0.972         # outer sidewall x. The arch lip is at ~1.00, so the tyre fills the arch
                         # instead of hiding under it, which is what "the wheels are buried" meant.
NOSE_F = 2.150           # front-most loft station (the splitter reaches further)
TAIL_F = -2.180          # rear-most loft station (the wing reaches further)
BBOX_F = 2.300           # splitter tip and wing trailing edge: the actual 4.60 m length

# --- cage density ---------------------------------------------------------------------------
# The feature lines below already put a lot of loops in; these only fill the gaps between them.
# They are the two knobs for the triangle budget - see the count printed at the end.
BASE_F_STEP = 1.250      # metres between filler stations
BASE_H_STEP = 16.00       # section-parameter units between filler ring samples
STATION_GAP = 0.084      # closest two FILLER stations may get, in metres
RING_GAP = 1.55          # closest two FILLER ring lines may get, in parameter units
# Opening edges and section keys are structure, not filler, so they get their own (much smaller)
# spacing floor - they have to land where the feature is, not where the grid happens to be.
STRUCT_GAP_F = 0.056
STRUCT_GAP_G = 0.74
SUBDIV = 2               # Catmull-Clark levels on the shell. This is the whole point of the file.

# --- shut lines ------------------------------------------------------------------------------
# A panel gap is FOUR grid lines, not three, and the two in the middle are a floor: [outer wall
# top, floor, floor, outer wall top]. The floor faces are given the TRIM material, so a shut line
# is a dark 3 mm slot you can actually see, and all four loops carry a full EDGE CREASE so
# Catmull-Clark keeps the walls vertical instead of relaxing the whole thing into a soft dimple.
# That relaxation is why the previous pass shipped a car with literally zero visible panel gaps:
# the geometry was there, subdivision averaged it down to a 2 mm ripple, and nothing showed.
GROOVE_WO_F = 0.0062     # outer (skin) line offset from the seam centre, metres
GROOVE_WI_F = 0.0028     # inner (floor) line offset from the seam centre, metres
GROOVE_HOLD_F = 0.0135   # holding loop each side, so the surrounding panel stays flat
GROOVE_WO_G = 0.128      # the same three, in section-parameter units (1 unit is about 65 mm)
GROOVE_WI_G = 0.058
GROOVE_HOLD_G = 0.270
GROOVE_DEPTH = 0.0050    # how deep a panel gap cuts
# A 3 mm gap on a 4.6 m car is a third of a pixel at any distance the player ever sees it from,
# and a detail nobody can resolve is a detail that is not there. 5.6 mm of dark floor inside a
# 12 mm slot is the smallest that survives a screen pixel, and at arm's length it still reads as
# a panel gap rather than a painted stripe.
GROOVE_CREASE = 1.0
RIM_CREASE = 0.85        # crease on an opening's cut loop, instead of a holding loop each side


# =============================================================================================
# Section shape
# =============================================================================================
# Twelve control points per half-section, sampled at these h values. h is the ring parameter on
# one side: 0 floor centre, 16 shoulder (max width), 32 roof centre. The named indices are what
# the feature tables are written in, so moving a control point moves every feature with it.
CUM = [0.0, 2.0, 4.0, 7.0, 10.0, 13.0, 16.0, 19.0, 23.0, 26.0, 29.0, 32.0]
H_MAX = 32.0

# Section parameters, in the order the key table uses them.
#   z0    underbody height on the centreline
#   wb    floor-pan half width
#   z1    shoulder height          w1  max half width (at the shoulder)
#   z2    roof-rail / deck-edge height
#   w2    roof-rail / buttress half width
#   crown height added on the roof centreline (NEGATIVE dishes it - that is the engine deck sunk
#         between the buttresses, and it is what stops the tail reading as a box)
#   tuck  how far the flank pulls back in below the shoulder (< 1 = undercut = hard shoulder)
#   low   fullness of the lower flank
NPARAM = 9

KEYS = [
    # A 0.72 m wheel puts the top of the arch cut at 0.755, so the shoulder (z1) over an arch has
    # to sit well above that or the cut eats the whole wing. Hence z1 ~0.85 over the front arch
    # and ~0.87 over the rear, dipping to 0.778 at the door: that dip and rise IS the haunch.
    #
    # Three things the first render got wrong and this table fixes:
    #  * THE BONNET. crown was near zero over the front wings, so the nose came out as one smooth
    #    dome - a whale, not a wedge. It is now -0.070 at f 1.35..1.78, which sinks the bonnet
    #    centreline ~9 cm BELOW the tops of the front wings. That dish, not the outline, is what
    #    makes a low nose read as low.
    #  * THE CABIN. The roof was at 1.02 with a 0.474 roof rail: too low and far too narrow, so
    #    the tumblehome was extreme, the side glass pointed at the sky and the screen lay at 14
    #    degrees. Roof 1.052 on a 0.576 rail puts the screen at 23 degrees and stands the side
    #    glass up.
    #  * THE TAIL. It tapered to w1 0.742 and then took a 5 cm cap bulge, which is an egg. It now
    #    holds 0.836 to the last station and the cap bulge is 1.8 cm: a Kamm tail with a real
    #    rear fascia for the lamps and the centre vent to sit in.
    #  * THE PLAN VIEW. w1 used to run 1.020 at the rear arch to 0.958 at the door: six
    #    centimetres of waist over a metre, which in plan reads as a rounded rectangle with the
    #    wheels buried under it. It now runs 1.005 - 0.898 - 0.990, so there is eleven
    #    centimetres of pinch each side at the doors and the arches stand proud of it. A hypercar
    #    in plan is an hourglass; that shape is the single strongest cue that the thing has
    #    wheels at its corners, and it was simply missing.
    #  * THE NOSE. It also tapers much harder in plan now (0.990 at the front arch to 0.470 at
    #    the prow), so the front wings read as separate volumes either side of a narrow snout.
    # f         z0     wb     z1     w1     z2     w2     crown   tuck   low
    (-2.180, (0.300, 0.430, 0.728, 0.834, 0.880, 0.624, -0.006, 0.956, 0.985)),
    (-2.120, (0.234, 0.498, 0.764, 0.900, 0.914, 0.698, -0.014, 0.950, 0.985)),
    (-2.050, (0.178, 0.546, 0.792, 0.944, 0.942, 0.740, -0.026, 0.944, 0.985)),
    (-1.960, (0.130, 0.574, 0.810, 0.966, 0.958, 0.758, -0.042, 0.940, 0.986)),  # ducktail crest
    (-1.860, (0.102, 0.594, 0.824, 0.983, 0.938, 0.764, -0.056, 0.935, 0.987)),
    (-1.680, (0.085, 0.610, 0.842, 0.998, 0.932, 0.758, -0.080, 0.928, 0.990)),
    (-1.480, (0.078, 0.618, 0.864, 1.004, 0.938, 0.732, -0.084, 0.922, 0.992)),
    (-1.350, (0.076, 0.620, 0.876, 1.005, 0.938, 0.710, -0.094, 0.919, 0.992)),  # rear arch peak
    (-1.180, (0.074, 0.620, 0.866, 0.996, 0.944, 0.676, -0.098, 0.912, 0.992)),
    (-1.020, (0.073, 0.618, 0.846, 0.976, 0.958, 0.638, -0.094, 0.896, 0.991)),
    (-0.820, (0.072, 0.612, 0.820, 0.940, 0.980, 0.594, -0.072, 0.870, 0.988)),
    (-0.620, (0.072, 0.606, 0.802, 0.916, 0.996, 0.558, -0.044, 0.858, 0.986)),
    (-0.450, (0.072, 0.602, 0.792, 0.905, 1.026, 0.546,  0.000, 0.864, 0.987)),
    (-0.200, (0.072, 0.598, 0.782, 0.898, 1.046, 0.560,  0.016, 0.884, 0.989)),
    (0.050,  (0.072, 0.598, 0.778, 0.898, 1.054, 0.570,  0.018, 0.894, 0.990)),  # roof crest
    (0.250,  (0.072, 0.600, 0.776, 0.900, 1.052, 0.574,  0.018, 0.896, 0.990)),
    (0.450,  (0.072, 0.602, 0.776, 0.906, 1.032, 0.580,  0.014, 0.898, 0.990)),  # screen header
    (0.700,  (0.072, 0.606, 0.778, 0.918, 0.930, 0.610,  0.000, 0.900, 0.990)),
    (0.930,  (0.073, 0.610, 0.786, 0.940, 0.826, 0.634, -0.014, 0.904, 0.990)),  # cowl
    (1.120,  (0.074, 0.608, 0.808, 0.968, 0.836, 0.650, -0.048, 0.910, 0.990)),
    (1.350,  (0.076, 0.604, 0.846, 0.990, 0.848, 0.666, -0.070, 0.914, 0.990)),  # front arch peak
    (1.560,  (0.078, 0.592, 0.828, 0.972, 0.838, 0.666, -0.076, 0.918, 0.990)),
    (1.780,  (0.082, 0.572, 0.766, 0.930, 0.816, 0.648, -0.070, 0.922, 0.989)),
    # The last 22 cm is a hard taper on purpose. A loft along Y turns whatever the final station
    # is into a flat end cap, and the front fascia is where the grille, the lamps and the corner
    # intakes live - so the nose has to pull in enough that those are real lofted faces with
    # forward-facing normals, and the cap is only the prow between them.
    (1.930,  (0.090, 0.536, 0.706, 0.882, 0.780, 0.618, -0.056, 0.926, 0.988)),
    (2.020,  (0.098, 0.502, 0.664, 0.842, 0.736, 0.590, -0.040, 0.930, 0.988)),
    (2.080,  (0.110, 0.456, 0.628, 0.786, 0.694, 0.544, -0.026, 0.934, 0.987)),
    (2.120,  (0.134, 0.372, 0.588, 0.700, 0.648, 0.462, -0.016, 0.940, 0.986)),
    (2.150,  (0.192, 0.212, 0.520, 0.470, 0.576, 0.268, -0.006, 0.948, 0.985)),
]


def control_points(p):
    """The twelve (half-width, height) control points of one half-section."""
    z0, wb, z1, w1, z2, w2, crown, tuck, low = p
    dz = z1 - z0
    dt = max(z2 - z1, 1e-4)
    return [
        (0.0,                       z0),                 # 0  floor centre
        (wb * 0.60,                 z0 + 0.004),         # 2  flat floor
        (wb,                        z0 + 0.020),         # 4  floor-pan edge
        (wb + (w1 - wb) * 0.60,     z0 + dz * 0.15),     # 7  rocker, tucked under
        (w1 * low,                  z0 + dz * 0.48),     # 10 lower flank
        (w1 * tuck,                 z0 + dz * 0.77),     # 13 waist: the undercut
        (w1,                        z1),                 # 16 HARD SHOULDER, max width
        (w1 * 0.950,                z1 + dt * 0.10),     # 19 shoulder radius, tight
        (w2 + (w1 - w2) * 0.48,     z1 + dt * 0.46),     # 23 tumblehome
        (w2,                        z2 - dt * 0.09),     # 26 roof rail / buttress top
        (w2 * 0.76,                 z2),                 # 29 roof crest / buttress inner
        (0.0,                       z2 + crown),         # 32 roof centre
    ]


def catmull(p0, p1, p2, p3, t):
    t2 = t * t
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                  + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t2 * t)


def section_xz(cp, h):
    """Catmull-Rom through the twelve control points, evaluated at continuous h in [0, 32]."""
    h = min(max(h, 0.0), H_MAX)
    i = 0
    while i < len(CUM) - 2 and h > CUM[i + 1]:
        i += 1
    t = (h - CUM[i]) / (CUM[i + 1] - CUM[i])

    def g(k):
        return cp[min(max(k, 0), len(cp) - 1)]
    p0, p1, p2, p3 = g(i - 1), g(i), g(i + 1), g(i + 2)
    return (catmull(p0[0], p1[0], p2[0], p3[0], t),
            catmull(p0[1], p1[1], p2[1], p3[1], t))


class Mono:
    """Fritsch-Carlson monotone cubic. Stations are 30 mm apart at the nose and half a metre apart
    at the cabin; a uniform spline through that OVERSHOOTS, sections cross, and the shell folds."""

    def __init__(self, xs, ys):
        self.xs, self.ys = xs, ys
        n = len(xs)
        h = [xs[i + 1] - xs[i] for i in range(n - 1)]
        d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
        m = [0.0] * n
        m[0], m[-1] = d[0], d[-1]
        for i in range(1, n - 1):
            if d[i - 1] * d[i] <= 0.0:
                m[i] = 0.0
            else:
                w1 = 2.0 * h[i] + h[i - 1]
                w2 = h[i] + 2.0 * h[i - 1]
                m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
        self.m, self.h = m, h

    def __call__(self, x):
        xs = self.xs
        if x <= xs[0]:
            return self.ys[0]
        if x >= xs[-1]:
            return self.ys[-1]
        lo, hi = 0, len(xs) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if xs[mid] <= x:
                lo = mid
            else:
                hi = mid
        hh = self.h[lo]
        t = (x - xs[lo]) / hh
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * self.ys[lo] + (t3 - 2 * t2 + t) * hh * self.m[lo]
                + (-2 * t3 + 3 * t2) * self.ys[hi] + (t3 - t2) * hh * self.m[hi])


class Loft:
    """The nine section scalars splined along the length, sampled at (f, g)."""

    def __init__(self, keys):
        xs = [k[0] for k in keys]
        self.curves = [Mono(xs, [k[1][i] for k in keys]) for i in range(NPARAM)]
        self._cp = {}

    def cp(self, f):
        key = round(f, 5)
        c = self._cp.get(key)
        if c is None:
            c = control_points(tuple(cu(f) for cu in self.curves))
            self._cp[key] = c
        return c

    def raw(self, f, g):
        """Undisplaced surface point. g wraps at 64; g > 32 is the -X side."""
        g = g % 64.0
        h = g if g <= 32.0 else 64.0 - g
        x, z = section_xz(self.cp(f), h)
        return Vector(((x if g <= 32.0 else -x), f, z))

    def raw_normal(self, f, g):
        df, dg = 0.0025, 0.06
        tf = self.raw(f + df, g) - self.raw(f - df, g)
        tg = self.raw(f, g + dg) - self.raw(f, g - dg)
        n = tf.cross(tg)
        if n.length < 1e-9:
            # Degenerate only on the centrelines, where the section tangent is parallel to X.
            return Vector((0.0, 0.0, 1.0)) if 8.0 < g < 56.0 else Vector((0.0, 0.0, -1.0))
        return n.normalized()


# =============================================================================================
# Feature tables. Everything the car has that is not a smooth panel lives here.
# =============================================================================================
def gmir(a, b):
    """The mirror image of a g-range on the other flank."""
    return ((64.0 - b) % 64.0, (64.0 - a) % 64.0)


# Openings: faces inside (f range, g range) are deleted and the border extruded inward, so the
# mouth has real inner walls. steps = [(depth, tangential shrink), ...] from the skin inward. The
# first step is short: it is the rim radius, and a rim is what tells the eye the opening has a
# thickness rather than being a hole cut in paper.
# An opening's `g` is its ring range at the FIRST station and `g2`, when present, the range at the
# last: the aperture is then a tapered quad, not a rectangle. A window or an intake cut as a plain
# rectangle is one of the loudest "this is a game asset" tells there is.
OPENINGS = [
    # --- front. The lamps straddle the shoulder: at the nose the section has almost no height
    #     above it, so anything placed up there comes out a 2 cm sliver on top of the wing.
    dict(name="grille_low",  f=(2.010, 2.146), g=(57.0, 7.0),
         steps=[(0.013, 0.995), (0.135, 0.80)], mat=TRIM),
    dict(name="intake_fnt",  f=(2.020, 2.142), g=(8.6, 13.6), mirror=True,
         steps=[(0.012, 0.995), (0.115, 0.78)], mat=TRIM),
    # Bigger than it was. 552 triangles over 0.05 m2 is a scratch, not a lamp unit, and from
    # the front it read as a bright smear with no structure in it. The aperture now runs from
    # just clear of the arch cut (f 1.745 + a margin) up onto the fascia, and it is deep
    # enough to hold three projector barrels with reflector bowls behind a cover lens.
    dict(name="lamp_front",  f=(1.775, 2.030), g=(12.9, 17.7), g2=(13.7, 18.5), mirror=True,
         steps=[(0.010, 0.995), (0.072, 0.93)], mat=TRIM),
    # the outlet in the dished bonnet: hot air from the radiators leaves through the top, and a
    # bonnet with a hole in it is the cheapest way to say the nose is doing work
    dict(name="bonnet_vent", f=(1.440, 1.740), g=(29.4, 34.6),
         steps=[(0.010, 0.996), (0.070, 0.86)], mat=TRIM),
    # --- flanks. The big one is the channel mouth; the low one feeds the floor. Both are kept
    #     clear of the rear arch cut in f, or the arch would have eaten their faces first and
    #     carve() would be extruding a torn selection.
    dict(name="intake_side", f=(-0.920, -0.400), g=(10.0, 15.2), g2=(11.4, 14.0), mirror=True,
         steps=[(0.014, 0.995), (0.265, 0.74)], mat=TRIM),
    dict(name="intake_low",  f=(-0.900, -0.440), g=(4.6, 7.8), g2=(5.2, 7.2), mirror=True,
         steps=[(0.011, 0.995), (0.130, 0.80)], mat=TRIM),
    dict(name="gill_front",  f=(0.720, 0.900), g=(9.6, 14.4), mirror=True,
         steps=[(0.010, 0.995), (0.085, 0.86)], mat=TRIM),
    dict(name="glass_side",  f=(-0.320, 0.300), g=(21.2, 24.4), g2=(20.2, 25.4), mirror=True,
         steps=[(0.008, 0.996), (0.095, 0.88)], mat=TRIM),
    # --- greenhouse ---
    dict(name="windscreen",  f=(0.470, 0.940), g=(26.6, 37.4),
         steps=[(0.009, 0.996), (0.125, 0.86)], mat=TRIM),
    # --- rear. No rear window: this is a mid-engine car and the deck behind the cabin is a
    #     louvred engine cover, which is also what the roof snorkel feeds. It used to run a full
    #     metre and read as a hole in the car; it is now shorter, narrower and much shallower,
    #     and the louvres sit near the top of it so they are what you see.
    dict(name="deck_vent",   f=(-1.560, -0.640), g=(28.9, 35.1),
         steps=[(0.009, 0.996), (0.044, 0.92)], mat=TRIM),
    dict(name="quarter_lvr", f=(-1.550, -1.220), g=(18.6, 21.8), mirror=True,
         steps=[(0.009, 0.996), (0.062, 0.90)], mat=TRIM),
    dict(name="lamp_rear",   f=(-2.146, -2.010), g=(10.4, 20.2), mirror=True,
         steps=[(0.010, 0.995), (0.058, 0.94)], mat=TRIM),
    dict(name="vent_rear",   f=(-2.146, -2.020), g=(53.6, 10.4),
         steps=[(0.013, 0.995), (0.120, 0.82)], mat=TRIM),
]
OPEN_BY_NAME = {o["name"]: o for o in OPENINGS}

# Shut lines. axis 'f' is a seam across the car at a station; axis 'g' is a seam running along it.
# rng is the extent on the other axis; the depth fades out over the last `fade` of each end so a
# seam never stops in a step.
GROOVES = [
    # Bonnet / frunk lid: two cross seams and the seams down the tops of the wings. Those side
    # seams sit on 20.4, the SAME ring line the door cut uses, on purpose - a shut line costs
    # four grid lines through the whole cage, and on a real car the bonnet edge and the door
    # shoulder do run along one character line.
    dict(axis='f', at=1.880,  rng=(20.4, 43.6)),
    dict(axis='f', at=1.060,  rng=(20.4, 43.6)),
    dict(axis='g', at=20.4,   rng=(1.060, 1.880), mirror=True),
    # front and rear bumper seams, round the lower body only
    dict(axis='f', at=1.620,  rng=(43.6, 20.4)),
    dict(axis='f', at=-1.870, rng=(43.6, 20.4)),
    # doors: two cross cuts and the top and bottom runs that close them into a rectangle
    dict(axis='f', at=0.700,  rng=(6.5, 20.4), mirror=True),
    dict(axis='f', at=-0.330, rng=(6.5, 20.4), mirror=True),
    dict(axis='g', at=6.5,    rng=(-0.330, 0.700), mirror=True),
    dict(axis='g', at=20.4,   rng=(-0.330, 0.700), mirror=True),
    # engine cover
    dict(axis='f', at=-1.690, rng=(25.2, 38.8)),
    dict(axis='g', at=25.2,   rng=(-1.690, -0.610), mirror=True),
]

# The rocker step under the doors is NOT a shut line: it is a change of plane a centimetre and a
# half deep and fifteen wide, so it wants a smooth cosine profile and no crease. Giving it the
# slot treatment would put a dark scratch along the sill and cost four more ring lines through
# every station for something that is not a panel gap at all.
SILL = dict(axis='g', at=4.0, rng=(-1.020, 1.020), mirror=True, smooth=True,
            depth=0.015, wo=0.34, wi=0.34, hold=0.80, fade=0.10)

# The deep side sculpt: a wide tapered valley running back from the door into the side intake.
# This is NOT a shut line - it is centimetres deep, so it needs the displaced normal (see
# Body.normal) or it lights like a painted stripe. Values are (at f_lo, at f_hi).
CHANNELS = [
    dict(f=(-0.420, 0.620), g=(11.6, 13.8), half=(3.6, 2.0), depth=(0.062, 0.004),
         mirror=True, fade=0.16),
    # a shallower one high on the rear quarter, leading into the louvre over the wheel
    dict(f=(-1.240, -0.560), g=(19.4, 20.8), half=(1.9, 1.2), depth=(0.026, 0.003),
         mirror=True, fade=0.12),
]

# Flush door pulls: a soft dish in the flank with a trim tab in it (built in the detail pass).
HANDLES = [(-0.220, 19.4), (-0.220, 44.6)]
HANDLE_R = (0.072, 1.40)     # metres in f, parameter units in g
HANDLE_DEPTH = 0.011

# The fuel flap, on the left rear quarter, clear of the arch and of the louvre.
FLAP = dict(f=-1.120, g=45.4, r=0.058)

# The roof snorkel. Built as its own lofted duct (see build_scoop): a fairing standing on the roof
# with a real mouth - rim, inner walls, a splitter vane - flowing back into the louvred deck.
SCOOP = dict(f_mouth=0.250, f_tail=-0.620,
             # f, half width, height above the roof. The first pass was 0.175 wide and came out
             # as a grey sliver between two grey panels; a ram-air fairing is a big object.
             prof=[(0.250, 0.208, 0.072), (0.100, 0.216, 0.072), (-0.060, 0.234, 0.068),
                   (-0.220, 0.258, 0.060), (-0.380, 0.288, 0.046), (-0.500, 0.316, 0.028),
                   (-0.620, 0.344, 0.008)])


# =============================================================================================
# Grid construction
# =============================================================================================
def wrap_in(v, a, b):
    """Is v inside the g-range [a, b], which may wrap through 64?"""
    v %= 64.0
    a %= 64.0
    b %= 64.0
    return (a <= v <= b) if a <= b else (v >= a or v <= b)


def fold(g):
    """g -> the half-section parameter h in [0, 32]."""
    g %= 64.0
    return g if g <= 32.0 else 64.0 - g


def gdist(a, b):
    """Shortest distance between two ring parameters."""
    return abs(((a - b + 32.0) % 64.0) - 32.0)


def opening_ranges(op):
    """Every g-range the opening occupies anywhere, for placing grid lines."""
    out = [op["g"]]
    if "g2" in op:
        out.append(op["g2"])
    if op.get("mirror"):
        out += [gmir(*r) for r in list(out)]
    return out


def op_range_at(op, t, mirror=False):
    """The opening's g-range a fraction t of the way along its f extent."""
    a0, b0 = op["g"]
    if "g2" in op:
        a1, b1 = op["g2"]
        a0, b0 = a0 + (a1 - a0) * t, b0 + (b1 - b0) * t
    return gmir(a0, b0) if mirror else (a0, b0)


def groove_ranges(gr):
    if gr["axis"] == 'f':
        return [gr["rng"]] if not gr.get("mirror") else [gr["rng"], gmir(*gr["rng"])]
    return [gr["at"]] if not gr.get("mirror") else [gr["at"], (64.0 - gr["at"]) % 64.0]


def merge_lines(protect, groups, base_lo, base_hi, base_step, min_gap):
    """Grid lines, in priority order. `protect` (the three lines a shut line needs) always goes
    in - they are 3 mm apart on purpose and must never be thinned against each other. Everything
    after it is added greedily and only if it clears `min_gap` from what is already there, so an
    opening edge wins over a section key and a section key wins over a filler line. Without that
    ordering the cage ends up with pairs of lines a millimetre apart, which subdivision reads as
    a crease and the paint shows as a scratch - and pays for them in triangles twice over."""
    out = sorted(set(round(v, 6) for v in protect))

    def ok(v, gap=None):
        return all(abs(v - u) > (min_gap if gap is None else gap) for u in out)
    for grp in groups:
        gap = None
        if isinstance(grp, tuple):
            grp, gap = grp
        for v in sorted(set(round(v, 6) for v in grp)):
            if ok(v, gap):
                out.append(v)
                out.sort()
    n = max(1, int(math.ceil((base_hi - base_lo) / base_step)))
    for i in range(n + 1):
        v = round(base_lo + (base_hi - base_lo) * i / n, 6)
        if ok(v):
            out.append(v)
            out.sort()
    return out


def groove_w(gr):
    if gr["axis"] == 'f':
        return (gr.get("wo", GROOVE_WO_F), gr.get("wi", GROOVE_WI_F))
    return (gr.get("wo", GROOVE_WO_G), gr.get("wi", GROOVE_WI_G))


def groove_lines(gr):
    """The grid lines one seam needs, in its own axis: [outer lip, floor, floor, outer lip]. A
    smooth one (the sill) is a plain three-line depression and gets no floor pair."""
    at = gr["at"]
    wo, wi = groove_w(gr)
    if gr.get("smooth"):
        return [at - wo, at, at + wo]
    return [at - wo, at - wi, at + wi, at + wo]


def groove_class(gr, v):
    """Where v sits across the seam: 'floor', 'wall' (the outer, skin-level lip) or None."""
    wo, wi = groove_w(gr)
    d = abs(v - gr["at"]) if gr["axis"] == 'f' else gdist(v, gr["at"])
    if gr.get("smooth"):
        return 'smooth' if d <= wo + 1e-6 else None
    if d <= wi + 1e-6:
        return 'floor'
    if d <= wo + 1e-6:
        return 'wall'
    return None


def build_stations():
    # Every section key is a grid line. Without that the loft is only sampled at the filler
    # spacing and a 3 cm feature like the ducktail crest lands between two stations and vanishes.
    # The two end stations are the cap rings: if an opening edge three millimetres away were
    # allowed to win the greedy pass the shell would simply stop short of its own nose.
    prot = [NOSE_F, TAIL_F]
    for gr in GROOVES + [SILL]:
        if gr["axis"] == 'f':
            prot += groove_lines(gr)
    edges = []
    for op in OPENINGS:
        edges += list(op["f"])
    for gr in GROOVES + [SILL]:
        if gr["axis"] == 'g':
            edges += list(gr["rng"])
    keys = [k[0] for k in KEYS]
    extra = []
    for op in OPENINGS:
        if "g2" in op:
            # A tapered aperture needs stations along its length or the slope comes out as two
            # or three steps instead of an edge.
            a, b = op["f"]
            extra += [a + (b - a) * k / 3.0 for k in range(1, 3)]
    for ch in CHANNELS:
        extra += list(ch["f"])
    extra += [HANDLES[0][0] - HANDLE_R[0], HANDLES[0][0] + HANDLE_R[0]]
    clip = lambda vs: [min(max(v, TAIL_F), NOSE_F) for v in vs]
    # Opening edges and section keys are STRUCTURE, not filler: they are allowed to land 8 mm
    # from a seam line. Only the filler pass is thinned at the full STATION_GAP. The previous
    # version thinned them all at 31 mm, which quietly deleted the 2.120 nose key (30 mm from
    # the cap ring) and with it the last of the nose taper.
    return merge_lines(clip(prot), [(clip(edges), STRUCT_GAP_F), (clip(keys), STRUCT_GAP_F),
                                    (clip(extra), STATION_GAP)],
                       TAIL_F, NOSE_F, BASE_F_STEP, STATION_GAP)


def build_ring():
    """Half-section samples in [0, 32], padded so the two halves have equal counts (the nose and
    tail caps are Coons patches and need four sides of matching length), then mirrored."""
    prot = [0.0, 16.0, 32.0]
    for gr in GROOVES + [SILL]:
        if gr["axis"] == 'g':
            for at in groove_ranges(gr):
                prot += [fold(v) for v in groove_lines(dict(gr, at=at))]
    edges = []
    for op in OPENINGS:
        for (a, b) in opening_ranges(op):
            edges += [fold(a), fold(b)]
    rims = []
    for gr in GROOVES + [SILL]:
        if gr["axis"] == 'f':
            for (a, b) in groove_ranges(gr):
                rims += [fold(a), fold(b)]
    clip = lambda vs: [min(max(v, 0.0), 32.0) for v in vs]
    half = merge_lines(clip(prot), [(clip(edges), STRUCT_GAP_G), (clip(rims), STRUCT_GAP_G)],
                       0.0, 32.0, BASE_H_STEP, RING_GAP)
    # Pad the sparser half until the two have the same number of spans.
    while True:
        lo = [v for v in half if v <= 16.0]
        hi = [v for v in half if v >= 16.0]
        if len(lo) == len(hi):
            break
        side = lo if len(lo) < len(hi) else hi
        gaps = sorted(((side[i + 1] - side[i], i) for i in range(len(side) - 1)), reverse=True)
        _, i = gaps[0]
        half = sorted(half + [0.5 * (side[i] + side[i + 1])])
    ring = list(half) + [64.0 - v for v in reversed(half[1:-1])]
    return ring


# =============================================================================================
# Displacement. Split in two on purpose:
#   SMOOTH  - channels and arch lips. Centimetres deep, so the surface NORMAL has to be
#             recomputed from the displaced surface, or the sculpt lights like a decal and the
#             carved intakes inherit normals from a surface that is no longer there.
#   SHARP   - shut lines and door pulls. Millimetres deep, deliberately normal-preserving: finite
#             differences across a 3 mm groove would hand back garbage normals.
# =============================================================================================
def smoothstep(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def band(v, a, b, fade):
    """1 inside [a, b], fading to 0 over `fade` at each end."""
    if b < a:
        a, b = b, a
    if v <= a or v >= b:
        return 0.0
    return min(smoothstep((v - a) / fade), smoothstep((b - v) / fade))


def band_g(v, a, b, fade):
    if not wrap_in(v, a, b):
        return 0.0
    da = (v - a) % 64.0
    db = (b - v) % 64.0
    return min(smoothstep(da / fade), smoothstep(db / fade))


def groove_along(gr, f, g):
    """How far into the seam's run (f, g) is: 1 in the middle, fading to 0 at the two ends. A
    seam that stops in a step reads as damage; a seam that fades out reads as a panel edge
    disappearing round a corner, which is what they do."""
    if gr["axis"] == 'f':
        return max(band_g(g, a, b, gr.get("fade", 1.2)) for (a, b) in groove_ranges(gr))
    a, b = gr["rng"]
    return band(f, a, b, gr.get("fade", 0.055))


def groove_at(f, g):
    """(depth, class) of the deepest seam covering (f, g). `class` is what the face material and
    the edge crease are chosen from, so the FLOOR of a shut line can be given the dark TRIM slot
    and the four loops can be creased only where the seam is really cut. Without the crease
    Catmull-Clark averages a 4 mm slot down into a 1 mm ripple that nobody can see - which is
    exactly what shipped last time, and why the car had no visible panel gaps at all."""
    best, cls = 0.0, None
    for gr in GROOVES + [SILL]:
        v = f if gr["axis"] == 'f' else g
        k = None
        if gr["axis"] == 'g':
            for at in groove_ranges(gr):
                k = groove_class(dict(gr, at=at), v) or k
        else:
            k = groove_class(gr, v)
        if k is None:
            continue
        run = groove_along(gr, f, g)
        if run <= 0.0:
            continue
        dep = gr.get("depth", GROOVE_DEPTH)
        if k == 'floor':
            best = max(best, dep * run)
            if run > 0.55:
                cls = 'floor'
        elif k == 'smooth':
            # A cosine across the step, not a slot: the sill is a change of plane.
            at = min(groove_ranges(gr), key=lambda a: gdist(v, a)) if gr["axis"] == 'g' else gr["at"]
            d = (abs(v - at) if gr["axis"] == 'f' else gdist(v, at)) / groove_w(gr)[0]
            best = max(best, dep * run * 0.5 * (1.0 + math.cos(math.pi * min(d, 1.0))))
        elif cls is None and run > 0.55:
            cls = 'wall'
    return best, cls


def groove_depth(f, g):
    return groove_at(f, g)[0]


def groove_edge_crease(fa, ga, fb, gb):
    """Crease value for the cage edge from (fa, ga) to (fb, gb). An edge is creased when it runs
    ALONG a seam - both ends on the same one of its four lines - and only inside the seam's run,
    so a shut line never leaves a sharp scratch out on open bodywork where it has faded away."""
    for gr in GROOVES:
        if gr.get("smooth"):
            continue
        ats = [gr["at"]] if gr["axis"] == 'f' else groove_ranges(gr)
        for at in ats:
            g2 = dict(gr, at=at)
            if gr["axis"] == 'f':
                if abs(fa - fb) > 1e-6:
                    continue
                if groove_class(g2, fa) is None:
                    continue
            else:
                if gdist(ga, gb) > 1e-6:
                    continue
                if groove_class(g2, ga) is None:
                    continue
            if min(groove_along(gr, fa, ga), groove_along(gr, fb, gb)) > 0.55:
                return GROOVE_CREASE
    return 0.0


def handle_depth(f, g):
    d = 0.0
    for (hf, hg) in HANDLES:
        du = (f - hf) / HANDLE_R[0]
        dv = (((g - hg + 32.0) % 64.0) - 32.0) / HANDLE_R[1]
        r = math.hypot(du, dv)
        if r < 1.0:
            d = max(d, HANDLE_DEPTH * smoothstep(1.0 - r))
    return d


def channel_depth(f, g):
    """The deep flank sculpt. A cosine valley whose centre, width and depth all taper along f, so
    it opens out as it runs back into the side intake instead of stopping in a step."""
    d = 0.0
    for ch in CHANNELS:
        fa, fb = ch["f"]
        if f <= fa or f >= fb:
            continue
        t = (f - fa) / (fb - fa)
        env = min(smoothstep((f - fa) / ch["fade"]), smoothstep((fb - f) / ch["fade"]))
        gc = ch["g"][0] + (ch["g"][1] - ch["g"][0]) * t
        hw = ch["half"][0] + (ch["half"][1] - ch["half"][0]) * t
        dep = ch["depth"][0] + (ch["depth"][1] - ch["depth"][0]) * t
        for centre in ([gc, (64.0 - gc) % 64.0] if ch.get("mirror") else [gc]):
            r = gdist(g, centre) / hw
            if r < 1.0:
                d = max(d, dep * env * 0.5 * (1.0 + math.cos(math.pi * r)))
    return d


def arch_lip(f, g, z):
    """Push the skin just outside an arch cut proud, so the arch has a blistered lip. Bigger than
    the first pass (20 mm over 13 cm, not 16 over 10): the arch lip is what gives the plan view
    its four corners, and a lip you have to look for is a lip that is not doing its job."""
    if fold(g) < 4.2 or fold(g) > 20.5:
        return 0.0
    best = 0.0
    for fa in (AXLE, -AXLE):
        d = math.hypot(f - fa, z - HUB_Z)
        if ARCH_R < d < ARCH_R + 0.130:
            t = (d - ARCH_R) / 0.130
            best = max(best, 0.020 * (1.0 - t) ** 1.5)
    return best


class Body:
    """The displaced shell surface. pos() is where the skin is; normal() is the normal of the
    SMOOTH displaced surface, which is what carves and mounted parts must use."""

    def __init__(self, loft):
        self.loft = loft

    def smooth(self, f, g):
        p = self.loft.raw(f, g)
        n = self.loft.raw_normal(f, g)
        return p + n * (arch_lip(f, g, p.z) - channel_depth(f, g))

    def normal(self, f, g):
        df, dg = 0.006, 0.20
        tf = self.smooth(f + df, g) - self.smooth(f - df, g)
        tg = self.smooth(f, g + dg) - self.smooth(f, g - dg)
        n = tf.cross(tg)
        if n.length < 1e-9:
            return self.loft.raw_normal(f, g)
        return n.normalized()

    def surface(self, f, g):
        n = self.normal(f, g)
        return self.smooth(f, g) - n * (groove_depth(f, g) + handle_depth(f, g)), n

    def pos(self, f, g):
        return self.surface(f, g)[0]

    def on(self, f, g, depth):
        """A point `depth` below the skin at (f, g), and the surface normal there."""
        p, n = self.surface(f, g)
        return p - n * depth, n


# =============================================================================================
# Blender plumbing
# =============================================================================================
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb_to_linear(c):
    """Undo the sRGB encode Godot's glTF importer applies to baseColorFactor (see SLOTS)."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_materials():
    """Backface culling is ON for every slot (glTF doubleSided=false). The old file shipped all
    six two-sided, including the closed paint shell, which wastes fill rate and lets you see the
    inside of the far body panel through every intake."""
    mats = []
    for name, col0, metal, rough, alpha in SLOTS:
        col = tuple(srgb_to_linear(c) for c in col0)
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        m.use_backface_culling = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (col[0], col[1], col[2], alpha)
        bsdf.inputs["Metallic"].default_value = metal
        bsdf.inputs["Roughness"].default_value = rough
        if alpha < 1.0:
            # glTF reads alphaMode from this. Godot's importer then builds a transparent
            # StandardMaterial3D, which is what stops the screen being a black plate.
            m.blend_method = 'BLEND'
            bsdf.inputs["Alpha"].default_value = alpha
            if "Transmission Weight" in bsdf.inputs:
                bsdf.inputs["Transmission Weight"].default_value = 0.55
            if "IOR" in bsdf.inputs:
                bsdf.inputs["IOR"].default_value = 1.52
        mats.append(m)
    return mats


def new_object(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    for m in mats:
        ob.data.materials.append(m)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def apply_modifiers(ob):
    bpy.context.view_layer.objects.active = ob
    for mod in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def subsurf(ob, levels):
    mod = ob.modifiers.new("sub", 'SUBSURF')
    mod.levels = levels
    mod.render_levels = levels
    mod.quality = 3
    mod.use_limit_surface = True
    mod.boundary_smooth = 'PRESERVE_CORNERS'
    apply_modifiers(ob)


def bevel(ob, width, segments=2, angle=36.0):
    mod = ob.modifiers.new("bev", 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle)
    mod.miter_outer = 'MITER_ARC'
    apply_modifiers(ob)


def solidify(ob, thickness):
    mod = ob.modifiers.new("sol", 'SOLIDIFY')
    mod.thickness = thickness
    mod.offset = -1.0
    apply_modifiers(ob)


def shade(ob, sharp_deg=52.0):
    """Smooth everywhere; sharp only where two faces really do meet at an angle. If a body panel
    still shows facets after this, the surface is wrong, not the shading."""
    me = ob.data
    for poly in me.polygons:
        poly.use_smooth = True
    lim = math.cos(math.radians(sharp_deg))
    faces = {}
    for poly in me.polygons:
        for ek in poly.edge_keys:
            faces.setdefault(ek, []).append(poly.index)
    for e in me.edges:
        fl = faces.get(e.key, [])
        if len(fl) != 2:
            e.use_edge_sharp = True
            continue
        if me.polygons[fl[0]].normal.dot(me.polygons[fl[1]].normal) < lim:
            e.use_edge_sharp = True


def join(parts):
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    return parts[0]


def bmesh_recalc(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()


# =============================================================================================
# The shell
# =============================================================================================
def coons_cap(bm, ring_verts, mats_idx, bulge, outward):
    """Fill an end ring with a quad grid (a Coons patch between its four sides), so the nose and
    tail panels are quads like everything else. An n-gon cap would put a 60-valence pole in the
    middle of the front of the car and subdivision would pinch it into a dimple."""
    n = len(ring_verts)
    q = n // 4
    corner = [0, q, 2 * q, 3 * q]
    bottom = [ring_verts[i] for i in range(corner[0], corner[1] + 1)]
    right = [ring_verts[i] for i in range(corner[1], corner[2] + 1)]
    top = [ring_verts[(corner[3] - i) % n] for i in range(q + 1)]
    left = [ring_verts[(n - i) % n] for i in range(q + 1)]
    Q00, Q10, Q11, Q01 = bottom[0].co, bottom[-1].co, right[-1].co, left[-1].co
    grid = []
    for iu in range(q + 1):
        u = iu / q
        row = []
        for iv in range(q + 1):
            v = iv / q
            if iv == 0:
                vert = bottom[iu]
            elif iv == q:
                vert = top[iu]
            elif iu == 0:
                vert = left[iv]
            elif iu == q:
                vert = right[iv]
            else:
                p = ((1 - v) * bottom[iu].co + v * top[iu].co
                     + (1 - u) * left[iv].co + u * right[iv].co
                     - ((1 - u) * (1 - v) * Q00 + u * (1 - v) * Q10
                        + u * v * Q11 + (1 - u) * v * Q01))
                p = p + outward * (bulge * math.sin(math.pi * u) * math.sin(math.pi * v))
                vert = bm.verts.new(p)
            row.append(vert)
        grid.append(row)
    for iu in range(q):
        for iv in range(q):
            f = bm.faces.new((grid[iu][iv], grid[iu + 1][iv],
                              grid[iu + 1][iv + 1], grid[iu][iv + 1]))
            f.material_index = mats_idx
    return grid


def build_cage(body, stations, ring):
    """The control cage. Every face remembers the (f, g) cell it came from, which is how the
    feature tables select faces exactly instead of by a nearest-point search over the skin."""
    bm = bmesh.new()
    nS, nR = len(stations), len(ring)
    verts = [[None] * nR for _ in range(nS)]
    nrm, vfg = {}, {}
    for i, f in enumerate(stations):
        for j, g in enumerate(ring):
            p, n = body.surface(f, g)
            v = bm.verts.new(p)
            verts[i][j] = v
            nrm[v] = n
            vfg[v] = (f, g)
    bm.verts.index_update()
    fg = {}
    for i in range(nS - 1):
        fc = 0.5 * (stations[i] + stations[i + 1])
        for j in range(nR):
            j2 = (j + 1) % nR
            a, b, c, d = verts[i][j], verts[i + 1][j], verts[i + 1][j2], verts[i][j2]
            if len({a, b, c, d}) < 4:
                continue
            face = bm.faces.new((a, b, c, d))
            g2 = ring[j2] if j2 > j else ring[j2] + 64.0
            gc = (0.5 * (ring[j] + g2)) % 64.0
            fg[face] = (fc, gc)
            # The FLOOR strip of a shut line is dark: you are looking down a gap between two
            # panels, not at paint. This is what turns a 4 mm groove from a thing a normal map
            # might have faked into a line you can see across a car park.
            face.material_index = TRIM if groove_at(fc, gc)[1] == 'floor' else PAINT
    # Nose and tail caps. They get no (f, g), so no opening can ever select them.
    coons_cap(bm, verts[-1], PAINT, 0.018, Vector((0.0, 1.0, 0.0)))
    coons_cap(bm, verts[0], PAINT, 0.018, Vector((0.0, -1.0, 0.0)))
    bm.faces.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    crease = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
    # Crease every cage edge that runs ALONG a shut line. Four creased loops per seam - the two
    # outer lips and the two floor lines - is what holds the slot's walls vertical through two
    # levels of Catmull-Clark. Holding loops would cost a whole extra ring of geometry each and
    # still round the corner; a crease costs one float.
    n_cre = 0
    for e in bm.edges:
        ca, cb = vfg.get(e.verts[0]), vfg.get(e.verts[1])
        if ca is None or cb is None:
            continue
        cv = groove_edge_crease(ca[0], ca[1], cb[0], cb[1])
        if cv > 0.0:
            e[crease] = cv
            n_cre += 1
    print("  creased %d seam edges" % n_cre)
    return bm, verts, nrm, fg, vfg, crease


# --- carving ---------------------------------------------------------------------------------
def carve(bm, faces, nrm, steps, mat, crease=None, crease_val=0.0):
    """Delete a patch of skin and push its border inward, twice, then cap it. That second ring is
    the inner wall you can see down the intake; the first is only a rim radius."""
    fset = set(faces)
    if not fset:
        return []
    bedges = set()
    for f in fset:
        for e in f.edges:
            if len(e.link_faces) != 2 or any(lf not in fset for lf in e.link_faces):
                bedges.add(e)
    ring_verts = set()
    for e in bedges:
        ring_verts.update(e.verts)
    cen = Vector((0.0, 0.0, 0.0))
    for v in ring_verts:
        cen += v.co
    cen /= max(len(ring_verts), 1)
    axis = Vector((0.0, 0.0, 0.0))
    for v in ring_verts:
        axis += nrm.get(v, Vector((0.0, 0.0, 1.0)))
    axis = axis.normalized() if axis.length > 1e-6 else Vector((0.0, 0.0, 1.0))

    bmesh.ops.delete(bm, geom=list(fset), context='FACES')
    cur_edges = [e for e in bedges if e.is_valid]
    if crease is not None and crease_val > 0.0:
        for e in cur_edges:
            e[crease] = crease_val
    cur_n = {v: nrm.get(v, axis) for v in ring_verts if v.is_valid}
    made = []
    for (depth, shrink) in steps:
        ret = bmesh.ops.extrude_edge_only(bm, edges=cur_edges)
        geom = ret["geom"]
        new_verts = [g for g in geom if isinstance(g, bmesh.types.BMVert)]
        new_faces = [g for g in geom if isinstance(g, bmesh.types.BMFace)]
        made += new_faces
        nxt_n = {}
        old_set = set(cur_n)
        for nv in new_verts:
            src = None
            for e in nv.link_edges:
                o = e.other_vert(nv)
                if o in old_set:
                    src = o
                    break
            n = cur_n.get(src, axis) if src else axis
            base = (src.co if src else nv.co) - n * depth
            t = base - cen
            along = axis * t.dot(axis)
            nv.co = cen + along + (t - along) * shrink
            nxt_n[nv] = n
        cur_n = nxt_n
        cur_edges = [g for g in geom
                     if isinstance(g, bmesh.types.BMEdge) and all(v in nxt_n for v in g.verts)]
    if cur_edges:
        res = bmesh.ops.contextual_create(bm, geom=cur_edges)
        made += res.get("faces", [])
    for f in made:
        f.material_index = mat
    return made


def snap_taper(body, fset, op, mirror, vfg):
    """Slide the cut boundary onto the aperture's true edge, for the long sides only: the two end
    edges already sit on stations and must stay there. Without this a tapered aperture comes out
    with a staircase down its long edge, which is the single most obvious low-effort tell."""
    fa, fb = op["f"]
    border = set()
    for f in fset:
        for e in f.edges:
            if len(e.link_faces) != 2 or any(lf not in fset for lf in e.link_faces):
                border.update(e.verts)
    for v in border:
        cell = vfg.get(v)
        if cell is None:
            continue
        vf, vg = cell
        if vf < fa + 1e-4 or vf > fb - 1e-4:
            continue
        t = min(max((vf - fa) / (fb - fa), 0.0), 1.0)
        a, b = op_range_at(op, t, mirror)
        da, db = gdist(vg, a), gdist(vg, b)
        if min(da, db) > 1.6:
            continue
        v.co = body.surface(vf, a if da < db else b)[0]


def carve_openings(bm, body, nrm, fg, vfg, crease):
    """Every opening in one pass. Face selection is by (f, g) rectangle, and because the grid
    lines were placed at exactly those bounds the cut lands ON them and not near them."""
    for op in OPENINGS:
        fa, fb = op["f"]
        for m in ([False, True] if op.get("mirror") else [False]):
            sel = []
            for f in bm.faces:
                cell = fg.get(f)
                if cell is None or not (fa < cell[0] < fb):
                    continue
                t = (cell[0] - fa) / (fb - fa)
                if wrap_in(cell[1], *op_range_at(op, t, m)):
                    sel.append(f)
            if not sel:
                print("  !! opening %s selected nothing" % op["name"])
                continue
            if "g2" in op:
                snap_taper(body, set(sel), op, m, vfg)
            carve(bm, sel, nrm, op["steps"], op["mat"], crease, RIM_CREASE)


def carve_arches(bm, nrm, fg, crease):
    """The wheel arches. Selection is the arch circle in the (Y, Z) plane; the cut boundary is
    snapped onto that circle BEFORE the extrusion, so the well inherits a round mouth instead of
    a stair-stepped one - and only above the hub line, because below it a real arch runs straight
    down into the sill rather than curling back under the car."""
    for fa in (AXLE, -AXLE):
        sel = []
        for f in bm.faces:
            cell = fg.get(f)
            if cell is None or fold(cell[1]) < 3.2:
                continue
            c = f.calc_center_median()
            if abs(c.x) > 0.42 and math.hypot(c.y - fa, c.z - HUB_Z) < ARCH_R:
                sel.append(f)
        if not sel:
            continue
        fset = set(sel)
        border = set()
        for f in fset:
            for e in f.edges:
                if len(e.link_faces) != 2 or any(lf not in fset for lf in e.link_faces):
                    border.update(e.verts)
        for v in border:
            if v.co.z < HUB_Z - 0.170:
                continue
            d = Vector((0.0, v.co.y - fa, v.co.z - HUB_Z))
            # Only snap what is already near the rim. A vertex at a third of the radius that
            # happened to touch the cut gets catapulted outward into a spike otherwise.
            if not (ARCH_R * 0.72 < d.length < ARCH_R * 1.40):
                continue
            k = ARCH_R / d.length
            v.co.y = fa + d.y * k
            v.co.z = HUB_Z + d.z * k
        # TRIM, not TYRE. The well lining is an inner wing, and while it wore the tyre slot
        # it was the ONLY thing in the file wearing it - which is how a reviewer came to measure
        # "the wheel" as a 0.83-0.90 m object that was 63 mm out of round. It was measuring the
        # arch. With the lining on trim, `tyre` means the four tyres and nothing else.
        carve(bm, sel, nrm, [(0.018, 0.995), (0.235, 0.90)], TRIM, crease, RIM_CREASE)


def build_shell(body, mats):
    stations = build_stations()
    ring = build_ring()
    bm, verts, nrm, fg, vfg, crease = build_cage(body, stations, ring)
    carve_arches(bm, nrm, fg, crease)
    carve_openings(bm, body, nrm, fg, vfg, crease)
    bm.faces.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = new_object(PREFIX + "shell", bm, mats)
    cage = len(ob.data.polygons)
    subsurf(ob, SUBDIV)
    return ob, len(stations), len(ring), cage


# =============================================================================================
# Glass and lamp lenses
# =============================================================================================
def panel(body, bm, f_rng, g_rng, inset, mat, nu=26, nv=18, shrink=0.012, g_end=None,
          crown=0.0, frit=None):
    """A pane conformed to the skin and set `inset` below it, so glass sits in a frame instead of
    lying flush on the body. `g_end` gives it the same taper as its aperture.

    `crown` bulges the middle of the pane back out toward the skin. A windscreen is a doubly
    curved shell; the first version of this panel simply followed the (locally almost flat) skin
    and dropped five millimetres across half a metre, which is why it read as a grey quadrilateral
    dropped into a rectangular hole.

    `frit` = (rings, material, edge_depth) reproduces the black ceramic frit band every bonded
    screen has: the outer `rings` of cells are given that material and lifted to `edge_depth`
    below the skin, so the pane's edge climbs into its aperture and meets the bodywork in a
    visible seal instead of floating at the bottom of a slot."""
    fa, fb = f_rng
    f0, f1 = fa, fb
    fa, fb = fa + (fb - fa) * shrink, fb - (fb - fa) * shrink
    f_rings, f_mat, f_depth = frit if frit else (0, mat, inset)

    def depth_at(i, j):
        bump = math.sin(math.pi * i / nu) * math.sin(math.pi * j / nv)
        core = inset - crown * bump
        if not f_rings:
            return core
        d = min(i, nu - i, j, nv - j)
        t = smoothstep(min(d / float(f_rings), 1.0))
        return f_depth + (core - f_depth) * t
    grid = []
    for i in range(nu + 1):
        f = fa + (fb - fa) * i / nu
        ga, gb = g_rng
        if g_end is not None:
            t = (f - f0) / (f1 - f0)
            ga = ga + (g_end[0] - ga) * t
            gb = gb + (g_end[1] - gb) * t
        span = (gb - ga) % 64.0
        ga2 = ga + span * shrink
        span2 = span * (1.0 - 2.0 * shrink)
        row = []
        for j in range(nv + 1):
            g = ga2 + span2 * j / nv
            p, n = body.surface(f, g)
            row.append(bm.verts.new(p - n * depth_at(i, j)))
        grid.append(row)
    for i in range(nu):
        for j in range(nv):
            f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
            d = min(i, nu - 1 - i, j, nv - 1 - j)
            f.material_index = f_mat if (f_rings and d < f_rings) else mat
    return grid


def build_glass(body, mats):
    """Glass taken straight from the aperture table, so a pane can never drift away from the hole
    it belongs in. Negative shrink: the pane overhangs its hole, because a pane cut to the exact
    aperture leaves a sliver of dark frame showing at every edge, which reads as a gap."""
    bm = bmesh.new()
    for name, inset, nu, nv, crown in (("windscreen", 0.030, 26, 20, 0.030),
                                       ("glass_side", 0.024, 18, 12, 0.012)):
        op = OPEN_BY_NAME[name]
        for m in ([False, True] if op.get("mirror") else [False]):
            panel(body, bm, op["f"], op_range_at(op, 0.0, m), inset, GLASS, nu, nv,
                  shrink=-0.010, g_end=op_range_at(op, 1.0, m) if "g2" in op else None,
                  crown=crown, frit=(2, TRIM, 0.008))
    ob = new_object(PREFIX + "glass", bm, mats)
    bpy.context.view_layer.objects.active = ob
    solidify(ob, 0.006)
    return ob


def build_interior(body, mats):
    """A liner inside the greenhouse. It exists because the glass is transparent now: with a
    backface-culled shell there is nothing behind a window but the road on the far side, and a
    car you can see straight through is worse than one with black plastic windows. Sampling the
    body's own surface 5.5 cm in gives a headliner that follows the roof and the pillars exactly
    and costs a few hundred quads."""
    bm = bmesh.new()
    panel(body, bm, (-0.560, 0.980), (17.0, 47.0), 0.055, TRIM, 22, 26, shrink=0.0)
    return new_object(PREFIX + "interior", bm, mats)


def cone(bm, base, axis, profile, mat, segs=16):
    """An oriented tube: `profile` is [(distance along axis, radius), ...] from the base outward.
    Used for the projector barrels and reflector bowls inside the lamps - the parts that make a
    headlight a unit with depth rather than a bright rectangle painted at the bottom of a slot."""
    ax = Vector(axis).normalized()
    up = Vector((0.0, 0.0, 1.0)) if abs(ax.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    u = ax.cross(up).normalized()
    v = ax.cross(u).normalized()
    rings = [super_ring(bm, Vector(base) + ax * d, u, v, r, r, 2.0, segs) for (d, r) in profile]
    loft_rings(bm, rings, mat)


def build_lenses(body, mats):
    """Lamp UNITS, not lamp lenses. The old pass put one flat coloured quad and three flat blades
    at the bottom of each recess - 552 triangles of headlight over five hundred square
    centimetres, which from the front is a bright smear with no structure in it. Each lamp now
    has a dark housing plate, projector barrels with reflector bowls and domed lenses, a raised
    signature blade, and a clear cover lens across the aperture, all built off the surface normal
    so they sit square in the hole. No manufacturer's light signature: a plain three-element
    front and a single full-width rear bar."""
    bm = bmesh.new()
    for name, mat, inset in (("lamp_front", LIGHT_F, 0.034), ("lamp_rear", LIGHT_R, 0.032)):
        op = OPEN_BY_NAME[name]
        fa, fb = op["f"]
        front = name == "lamp_front"
        for m in (False, True):
            g0 = op_range_at(op, 0.0, m)
            g1 = op_range_at(op, 1.0, m) if "g2" in op else g0

            def lerp(r, u):
                return r[0] + ((r[1] - r[0]) % 64.0) * u
            # dark backing plate right at the bottom of the recess
            panel(body, bm, op["f"], g0, inset + 0.020, TRIM, 10, 6, shrink=0.02, g_end=g1)
            # projectors: a reflector bowl opening forward with a domed lens in its mouth
            nproj = 3 if front else 2
            for k in range(nproj):
                c = (k + 0.5) / nproj
                gg0 = lerp(g0, c)
                gg1 = lerp(g1, c)
                ff = fa + (fb - fa) * 0.5
                gg = gg0 + (gg1 - gg0) * 0.5
                p, n = body.surface(ff, gg)
                base = p - n * (inset + 0.018)
                rr = 0.030 if front else 0.026
                cone(bm, base, n, [(0.0, rr * 0.30), (0.008, rr * 0.86), (0.019, rr)],
                     TRIM, 18)
                cone(bm, base + n * 0.019, n, [(0.0, rr), (0.006, rr * 0.97),
                                               (0.012, rr * 0.80), (0.015, rr * 0.42)], mat, 18)
            # the signature blade, standing proud of the projectors
            panel(body, bm, (fa + (fb - fa) * 0.08, fb - (fb - fa) * 0.08),
                  (lerp(g0, 0.06), lerp(g0, 0.94)), inset - 0.012, mat, 10, 3,
                  shrink=0.02, g_end=(lerp(g1, 0.06), lerp(g1, 0.94)))
            # clear cover lens across the whole aperture, crowned so it catches a highlight
            panel(body, bm, op["f"], g0, inset - 0.024, mat, 12, 7, shrink=0.0, g_end=g1,
                  crown=0.010, frit=(1, TRIM, 0.004))
    return new_object(PREFIX + "lens", bm, mats)


# =============================================================================================
# Solid primitives. Everything here is a CLOSED solid with real thickness, because the brief is
# "every aero element should be a real surface with thickness, visible from both sides" and
# because a single-sided plane is invisible from behind and lights wrong from in front.
# =============================================================================================
def bm_box(bm, centre, size, mat, rot_x=0.0, rot_z=0.0, taper=1.0):
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    pts = []
    for sz in (-1, 1):
        k = taper if sz > 0 else 1.0
        for sy in (-1, 1):
            for sx in (-1, 1):
                pts.append(Vector((sx * hx * k, sy * hy, sz * hz)))
    cx, sx_ = math.cos(rot_x), math.sin(rot_x)
    cz, sz_ = math.cos(rot_z), math.sin(rot_z)
    vs = []
    for p in pts:
        y, z = p.y * cx - p.z * sx_, p.y * sx_ + p.z * cx
        x, y = p.x * cz - y * sz_, p.x * sz_ + y * cz
        vs.append(bm.verts.new(Vector((x, y, z)) + Vector(centre)))
    for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6),
              (0, 2, 6, 4), (1, 5, 7, 3)):
        f = bm.faces.new([vs[i] for i in q])
        f.material_index = mat
    return vs


def bm_tube(bm, centre, r_out, r_in, depth, mat, segs=24, squash=0.82):
    """A real tube with an inner wall you can see down. An exhaust drawn as a black disc is the
    single most obvious tell of a cheap car model."""
    rings = []
    for (r, y) in ((r_out, -depth * 0.5), (r_out, depth * 0.5),
                   (r_in, depth * 0.5), (r_in, -depth * 0.5)):
        ring = []
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            ring.append(bm.verts.new(Vector((math.cos(a) * r, y, math.sin(a) * r * squash))
                                     + Vector(centre)))
        rings.append(ring)
    for ri in range(4):
        a, b = rings[ri], rings[(ri + 1) % 4]
        for k in range(segs):
            k2 = (k + 1) % segs
            f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            f.material_index = mat


def bm_sphere(bm, centre, radius, mat, su=26, sv=16, scale=(1.0, 1.0, 1.0)):
    grid = []
    for i in range(sv + 1):
        th = math.pi * i / sv
        row = []
        for j in range(su):
            ph = 2.0 * math.pi * j / su
            p = Vector((math.sin(th) * math.cos(ph) * scale[0],
                        math.sin(th) * math.sin(ph) * scale[1],
                        math.cos(th) * scale[2])) * radius
            row.append(bm.verts.new(p + Vector(centre)))
        grid.append(row)
    for i in range(sv):
        for j in range(su):
            j2 = (j + 1) % su
            f = bm.faces.new((grid[i][j], grid[i][j2], grid[i + 1][j2], grid[i + 1][j]))
            f.material_index = mat


def bm_disc(bm, centre, normal, radius, depth, mat, segs=28, scale_u=1.0):
    """A flat disc lying ON the skin, oriented by the surface normal. A sphere sunk into the body
    reads as a blister, not a recess."""
    n = Vector(normal).normalized()
    up = Vector((0.0, 1.0, 0.0)) if abs(n.z) > 0.9 else Vector((0.0, 0.0, 1.0))
    u = n.cross(up).normalized() * scale_u
    v = n.cross(u).normalized()
    c = Vector(centre)
    front, back = [], []
    for k in range(segs):
        a = 2.0 * math.pi * k / segs
        r = u * (math.cos(a) * radius) + v * (math.sin(a) * radius)
        front.append(bm.verts.new(c + r))
        back.append(bm.verts.new(c + r - n * depth))
    f = bm.faces.new(front)
    f.material_index = mat
    for k in range(segs):
        k2 = (k + 1) % segs
        f = bm.faces.new((front[k], front[k2], back[k2], back[k]))
        f.material_index = mat


def fan_cap(bm, ring, mat, reverse=False):
    """Close a ring with a triangle fan from its centroid. A fan, not an n-gon: these rings are
    aerofoil sections and are not planar, and a non-planar n-gon shades like a crumpled bag."""
    c = Vector((0.0, 0.0, 0.0))
    for v in ring:
        c += v.co
    cv = bm.verts.new(c / len(ring))
    n = len(ring)
    for k in range(n):
        a, b = ring[k], ring[(k + 1) % n]
        tri = (cv, b, a) if reverse else (cv, a, b)
        f = bm.faces.new(tri)
        f.material_index = mat


def loft_rings(bm, rings, mat, cap_first=True, cap_last=True):
    """Bridge a list of equal-length rings into a tube. This is what makes the rear wing, the
    swan-neck struts and the roof duct one continuous smooth surface instead of a stack of boxes."""
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        n = len(a)
        for k in range(n):
            k2 = (k + 1) % n
            if len({a[k], a[k2], b[k2], b[k]}) < 4:
                continue
            f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            f.material_index = mat
    if cap_first:
        fan_cap(bm, rings[0], mat, reverse=True)
    if cap_last:
        fan_cap(bm, rings[-1], mat)


def naca_half(t, x):
    """Half-thickness of a NACA 4-digit symmetric section at chord fraction x, closed at the TE."""
    return 5.0 * t * (0.2969 * math.sqrt(x) - 0.1260 * x - 0.3516 * x * x
                      + 0.2843 * x ** 3 - 0.1036 * x ** 4)


def foil_ring(bm, origin, chord_dir, up_dir, chord, thick, camber, aoa, mat_free=True, n=20):
    """One closed aerofoil section, built in the plane spanned by chord_dir and up_dir, with the
    leading edge at `origin`. Cosine spacing, so the nose radius is resolved properly - uniform
    spacing turns the leading edge into a visible chamfer, which is exactly the sort of faceting
    the owner is complaining about."""
    cd = Vector(chord_dir).normalized()
    ud = Vector(up_dir).normalized()
    xs = [0.5 * (1.0 - math.cos(math.pi * i / n)) for i in range(n + 1)]
    pts = []
    for x in xs:                       # upper surface, LE -> TE
        yc = camber * 4.0 * x * (1.0 - x)
        pts.append((x, yc + naca_half(thick, x)))
    for x in reversed(xs[1:-1]):       # lower surface, TE -> LE
        yc = camber * 4.0 * x * (1.0 - x)
        pts.append((x, yc - naca_half(thick, x)))
    ca, sa = math.cos(aoa), math.sin(aoa)
    ring = []
    for (x, y) in pts:
        xc, yc = x * chord, y * chord
        ring.append(bm.verts.new(Vector(origin) + cd * (xc * ca - yc * sa)
                                 + ud * (xc * sa + yc * ca)))
    return ring


def super_ring(bm, centre, u_dir, v_dir, hu, hv, power=2.6, segs=28):
    """A closed rounded-rectangle (superellipse) ring. Used for the roof duct and the strut
    blades: a plain rectangle creases, a plain ellipse has no shoulders, this has both."""
    cu, cv = Vector(u_dir), Vector(v_dir)
    ring = []
    for k in range(segs):
        a = 2.0 * math.pi * k / segs
        ca, sa = math.cos(a), math.sin(a)
        su = math.copysign(abs(ca) ** (2.0 / power), ca)
        sv = math.copysign(abs(sa) ** (2.0 / power), sa)
        ring.append(bm.verts.new(Vector(centre) + cu * (su * hu) + cv * (sv * hv)))
    return ring


def bm_plate(bm, nu, nv, pos, thick, mat, thick_dir=None):
    """A double-sided plate from a parametric top surface, offset by `thick` to make the
    underside, with four rim walls. Splitter, canards, diffuser ramp, endplates, strakes."""
    eps = 1e-3
    top, bot = [], []
    for i in range(nu + 1):
        u = i / nu
        rt, rb = [], []
        for j in range(nv + 1):
            v = j / nv
            p = pos(u, v)
            if thick_dir is not None:
                n = Vector(thick_dir).normalized()
            else:
                du = pos(min(u + eps, 1.0), v) - pos(max(u - eps, 0.0), v)
                dv = pos(u, min(v + eps, 1.0)) - pos(u, max(v - eps, 0.0))
                n = du.cross(dv)
                n = n.normalized() if n.length > 1e-9 else Vector((0.0, 0.0, 1.0))
                if n.z < 0.0:
                    n = -n
            rt.append(bm.verts.new(p))
            rb.append(bm.verts.new(p - n * thick))
        top.append(rt)
        bot.append(rb)
    for i in range(nu):
        for j in range(nv):
            f = bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
            f.material_index = mat
            f = bm.faces.new((bot[i][j], bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j]))
            f.material_index = mat
    for j in range(nv):                      # u = 0 and u = 1 rims
        for (row_t, row_b, flip) in ((top[0], bot[0], False), (top[nu], bot[nu], True)):
            quad = (row_t[j], row_b[j], row_b[j + 1], row_t[j + 1])
            f = bm.faces.new(quad[::-1] if flip else quad)
            f.material_index = mat
    for i in range(nu):                      # v = 0 and v = 1 rims
        for (jj, flip) in ((0, True), (nv, False)):
            quad = (top[i][jj], bot[i][jj], bot[i + 1][jj], top[i + 1][jj])
            f = bm.faces.new(quad[::-1] if flip else quad)
            f.material_index = mat


def bezier(p0, p1, p2, p3, t):
    u = 1.0 - t
    return (p0 * (u ** 3) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t ** 3))


# =============================================================================================
# The roof snorkel: a real duct, not a bump
# =============================================================================================
def build_scoop(body, mats):
    """A fairing standing on the roof with a forward-facing MOUTH: outer lip, a rim you can see
    the thickness of, inner walls running back and down, a dark cap and a splitter vane. It
    flows back into the louvred engine deck, which is what a ram-air scoop on a mid-engine car
    actually does. Built as its own loft so the shell's grid does not have to carry it."""
    bm = bmesh.new()
    prof = SCOOP["prof"]
    fs = [p[0] for p in prof]
    w_of = Mono(list(reversed(fs)), [p[1] for p in reversed(prof)])
    h_of = Mono(list(reversed(fs)), [p[2] for p in reversed(prof)])

    def ring_at(f, wscale=1.0, hscale=1.0, drop=0.0, power=3.0, segs=22):
        """A closed section of the fairing: a squared arch over a flat base sunk into the roof."""
        base = body.pos(f, 32.0).z - 0.035 + drop
        w = w_of(f) * wscale
        h = h_of(f) * hscale
        ring = []
        for k in range(segs):
            a = math.pi * k / (segs - 1)          # 0 .. pi over the top
            ca, sa = math.cos(a), math.sin(a)
            x = math.copysign(abs(ca) ** (2.0 / power), ca) * w
            z = base + 0.035 + abs(sa) ** (2.0 / power) * h
            ring.append(bm.verts.new(Vector((x, f, z))))
        for k in range(1, segs - 1):              # flat base, left back to right
            x = -w + 2.0 * w * k / (segs - 1)
            ring.append(bm.verts.new(Vector((-x, f, base))))
        return ring

    fsamp = [SCOOP["f_mouth"]]
    n = 16
    for k in range(1, n + 1):
        t = k / n
        fsamp.append(SCOOP["f_mouth"] + (SCOOP["f_tail"] - SCOOP["f_mouth"]) * (t ** 1.15))
    outer = [ring_at(f) for f in fsamp]
    loft_rings(bm, outer, PAINT, cap_first=False, cap_last=True)

    # The mouth: rim ring, then two inner rings going back and down, then a dark cap.
    inner = [ring_at(SCOOP["f_mouth"] - 0.014, 0.93, 0.88, drop=0.010),
             ring_at(SCOOP["f_mouth"] - 0.080, 0.84, 0.72, drop=0.026),
             ring_at(SCOOP["f_mouth"] - 0.200, 0.70, 0.54, drop=0.044)]
    loft_rings(bm, [outer[0]] + inner, TRIM, cap_first=False, cap_last=True)

    # A vertical splitter vane down the middle of the mouth, and two horizontal ones.
    roof = body.pos(SCOOP["f_mouth"] - 0.06, 32.0).z
    bm_box(bm, (0.0, SCOOP["f_mouth"] - 0.080, roof + 0.034), (0.016, 0.160, 0.070), TRIM)
    for sgn in (-1.0, 1.0):
        bm_box(bm, (sgn * 0.098, SCOOP["f_mouth"] - 0.074, roof + 0.036),
               (0.130, 0.150, 0.012), TRIM)
    return new_object(PREFIX + "scoop", bm, mats)


# =============================================================================================
# Aero: splitter, canards, diffuser, wing, endplates, swan-neck struts
# =============================================================================================
def build_aero(body, mats):
    bm = bmesh.new()

    # ---- front splitter -------------------------------------------------------------------
    # The rear half-width used to be a flat 0.885, but the body at that station is only about
    # 0.62 across the floor pan, so the plate stuck out a QUARTER OF A METRE either side and
    # rendered as a white shelf bolted under the nose - the single loudest wrong thing in the
    # last render. A splitter is a lip: it follows the car's own lower edge with a constant
    # overhang and only becomes a blade where it runs out ahead of the fascia.
    OVERHANG = 0.052

    def splitter_half(y):
        base = abs(body.pos(min(y, NOSE_F - 0.004), 5.2).x) + OVERHANG
        t = smoothstep(min(max((y - 1.955) / 0.330, 0.0), 1.0))
        return base + (0.408 - base) * t

    def splitter(u, v):
        s = 2.0 * u - 1.0
        a = abs(s)
        y_fr = BBOX_F - 0.0010 - 0.250 * a ** 1.7   # the bevel is what reaches BBOX_F
        y_bk = 1.606 + 0.062 * a
        y = y_bk + (y_fr - y_bk) * v
        # Upswept outer edges and a raised leading lip, so it catches light as a curved blade
        # rather than as one flat facet aimed at the sky.
        z = 0.074 + 0.052 * a ** 1.7 + 0.018 * (1.0 - v) ** 1.4 + 0.014 * v ** 3.0
        return Vector((s * splitter_half(y), y, z))
    bm_plate(bm, 30, 12, splitter, 0.020, TRIM)

    # Splitter fences. They used to be three loose boxes hanging in space under the nose and
    # they read exactly like that. Each is now a swept plate whose TOP edge lies on the splitter
    # surface itself and whose bottom edge is a raked curve, so it grows out of the plate instead
    # of being parked near it, and its ends are chamfered rather than square.
    for sgn in (-1.0, 1.0):
        for (px, y0, y1, drop) in ((0.244, 1.900, 2.168, 0.050),
                                   (0.408, 1.858, 2.096, 0.044),
                                   (0.556, 1.812, 2.004, 0.036)):
            def fence(u, v, sgn=sgn, px=px, y0=y0, y1=y1, drop=drop):
                y = y0 + (y1 - y0) * v
                a = px / 0.72
                top = 0.0745 + 0.052 * a ** 1.7
                taper = math.sin(math.pi * min(max(v, 0.02), 0.98)) ** 0.45
                return Vector((sgn * (px + 0.006 * u), y, top - (drop * taper + 0.004) * u))
            bm_plate(bm, 4, 9, fence, 0.011, TRIM, thick_dir=(1.0, 0.0, 0.0))
    # ---- dive planes (canards) on the front corners ----------------------------------------
    # They used to be two flat rectangles standing off the corner, ends square, and they read as
    # loose plates parked next to the car. Now the root is buried 4 cm inside the skin, the chord
    # tapers to the tip, the planform sweeps back and the tip lifts - so each one is a wing
    # growing out of the wing, which is what a dive plane is.
    for sgn in (-1.0, 1.0):
        for (zc, sp, ch, ang) in ((0.372, 0.190, 0.196, -0.34), (0.502, 0.166, 0.162, -0.27)):
            def canard(u, v, sgn=sgn, zc=zc, sp=sp, ch=ch, ang=ang):
                chord = ch * (1.0 - 0.42 * u * u)
                x = sgn * (0.798 + sp * u)
                y = 2.018 - 0.104 * u ** 1.7 - chord * v
                z = zc + math.sin(ang) * (chord * v) + 0.052 * u ** 2.2
                return Vector((x, y, z))
            bm_plate(bm, 9, 10, canard, 0.011, TRIM)

    # ---- rear diffuser ---------------------------------------------------------------------
    DIF_Y0, DIF_Y1 = -1.480, -2.240
    def dif_z(v):
        return 0.072 + 0.266 * smoothstep(v) ** 1.25

    def diffuser(u, v):
        s = 2.0 * u - 1.0
        half = 0.828 - 0.048 * v
        return Vector((s * half, DIF_Y0 + (DIF_Y1 - DIF_Y0) * v, dif_z(v)))
    bm_plate(bm, 26, 16, diffuser, 0.022, TRIM)

    # strakes: real fins standing down off the ramp, stopped above the splitter plane
    for xs in (0.115, 0.360, 0.600, 0.810):
        for sgn in (-1.0, 1.0):
            def fin(u, v, xs=xs, sgn=sgn):
                v0 = 0.20 + 0.80 * v
                y = DIF_Y0 + (DIF_Y1 - DIF_Y0) * v0
                top = dif_z(v0)
                bot = max(0.052, top - 0.030 - 0.115 * v0)
                return Vector((sgn * (xs + 0.012 * v0), y, bot + (top - bot) * u))
            bm_plate(bm, 5, 12, fin, 0.013, TRIM, thick_dir=(1.0, 0.0, 0.0))

    # ---- rear wing --------------------------------------------------------------------------
    # A lofted aerofoil, not a plank: chord tapers and sweeps toward the tips and the tips curl
    # up. The trailing edge lands on BBOX_F so the wing is the rear extreme of the bounding box
    # and the splitter tip is the front one - that symmetry is what keeps the game's single
    # wheel_z centred in both arches.
    # PLANFORM, not a plank. The first pass tapered the chord by twelve per cent over the span
    # and from behind it read as a broomstick across the tail. This one holds the trailing edge
    # dead straight on BBOX_F (which is also what keeps the bounding box symmetric) and sweeps
    # the LEADING edge back, so the chord goes 0.392 at the root to 0.214 at the tip - a 45 per
    # cent taper, a visible planform, and a wing you can tell is a wing in silhouette. The
    # section changes with it: thicker and more cambered at the root, thin and flat at the tip,
    # with two degrees of washout. A constant section is the other half of "plank".
    WING_TE_Y, WING_LE_Z = BBOX_F * -1.0, 1.062
    WING_SPAN, WING_N = 0.952, 22

    def wing_geom(x):
        a = abs(x) / WING_SPAN
        chord = 0.392 - 0.178 * a ** 1.35
        aoa = math.radians(12.5 - 2.0 * a * a)
        le_z = WING_LE_Z + 0.046 * a ** 2.8            # tips curled up
        le_y = WING_TE_Y + chord * math.cos(aoa)
        return chord, aoa, le_y, le_z

    def wing_ring(x):
        a = abs(x) / WING_SPAN
        chord, aoa, le_y, le_z = wing_geom(x)
        return foil_ring(bm, Vector((x, le_y, le_z)), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0),
                         chord, 0.135 - 0.038 * a, -0.062 + 0.020 * a, aoa, n=15)
    rings = [wing_ring(-WING_SPAN + 2.0 * WING_SPAN * k / WING_N) for k in range(WING_N + 1)]
    loft_rings(bm, rings, TRIM)
    # Gurney flap: a 14 mm lip standing up off the trailing edge, right across the span. It is
    # the one detail that says "this wing was designed by somebody" rather than extruded.
    def gurney(u, v, sp=WING_SPAN):
        x = -sp + 2.0 * sp * u
        chord, aoa, le_y, le_z = wing_geom(x)
        te_z = le_z + chord * math.sin(aoa) - 0.062 * chord * 0.0
        return Vector((x, WING_TE_Y + 0.004 * v, te_z + 0.016 * v))
    bm_plate(bm, 22, 3, gurney, 0.009, TRIM, thick_dir=(0.0, -1.0, 0.0))

    # ---- endplates ---------------------------------------------------------------------------
    # u runs leading edge -> trailing edge, v bottom -> top. The outline is raked down at the
    # front and stepped up at the back; the first pass used a plain quadrilateral and it read as
    # a grey slab bolted to the tail.
    for sgn in (-1.0, 1.0):
        def plate(u, v, sgn=sgn):
            y = -2.012 - 0.288 * u
            lo = 1.034 + 0.046 * smoothstep(min(u * 1.8, 1.0))
            hi = 1.156 + 0.070 * smoothstep(min(u * 1.2, 1.0))
            return Vector((sgn * (0.956 + 0.022 * u * (1.0 - u)), y, lo + (hi - lo) * v))
        bm_plate(bm, 14, 8, plate, 0.013, TRIM, thick_dir=(1.0, 0.0, 0.0))

    # ---- swan-neck struts --------------------------------------------------------------------
    # They arch over the leading edge and come down onto the wing's UPPER surface, which is what
    # a swan neck is: the low-pressure side stays clean. Each is a blade swept along a Bezier.
    for sgn in (-1.0, 1.0):
        P = [Vector((0.0, -1.800, 0.926)), Vector((0.0, -2.170, 1.010)),
             Vector((0.0, -2.250, 1.218)), Vector((0.0, -2.078, 1.104))]
        steps = 13
        srings = []
        for k in range(steps + 1):
            t = k / steps
            pp = bezier(P[0], P[1], P[2], P[3], t)
            d = (bezier(P[0], P[1], P[2], P[3], min(t + 0.01, 1.0))
                 - bezier(P[0], P[1], P[2], P[3], max(t - 0.01, 0.0)))
            d = d.normalized() if d.length > 1e-9 else Vector((0.0, 0.0, 1.0))
            nrm = Vector((0.0, -d.z, d.y))        # in-plane normal to the path
            hw = 0.064 + 0.032 * (1.0 - t) ** 2
            ht = 0.017 + 0.010 * (1.0 - t) ** 2
            srings.append(super_ring(bm, pp + Vector((sgn * 0.425, 0.0, 0.0)),
                                     nrm, Vector((1.0, 0.0, 0.0)), hw, ht, 3.0, 18))
        loft_rings(bm, srings, TRIM)

    # ---- side skirts: the blade under the rocker step ------------------------------------
    for sgn in (-1.0, 1.0):
        def skirt(u, v, sgn=sgn):
            f = -1.000 + 2.000 * v
            p, n = body.surface(f, 4.6 if sgn > 0 else 59.4)
            out = Vector((sgn * 1.0, 0.0, 0.0))
            return p + out * (0.004 + 0.052 * u) + Vector((0.0, 0.0, -0.004 - 0.026 * u))
        bm_plate(bm, 4, 18, skirt, 0.020, TRIM)

    return new_object(PREFIX + "aero", bm, mats)


# =============================================================================================
# Wheels
# =============================================================================================
# The previous export had NO WHEELS. Not a crude wheel - none at all: the only `tyre` material in
# the file was the lining of the arch wells, which is why a reviewer measured the "wheel" as an
# out-of-round 0.83-0.90 m egg. It was reading the arch. And Vehicle._add_wheel() returns early
# with `if _has_model: return # the generated models have their own wheels`, so a body model that
# does not carry wheels puts a car on the street with nothing under the arches at all.
#
# So: a real wheel, four times. Tyre with a bulged sidewall and rounded tread shoulders, an alloy
# with a flange lip and a barrel, ten dished spokes with gaps you can see the brake through, a
# centre-lock nut, a cross-drilled vented disc with real holes through it, and a caliper. Every
# radius comes off TYRE_R, so the thing is exactly 0.720 m across and exactly round.
WHEEL_SEG = 48           # segments round the tyre: a 40 mm facet before subdivision, smooth-shaded
SPOKES = 10
DISC_R = 0.246           # brake disc: fills the alloy, which is what a hypercar's brakes do
DISC_SEG = 32


def lathe(bm, centre, axis_x, profile, mat, segs=WHEEL_SEG, closed=True):
    """Spin a (width, radius) profile about the X axis. `profile` runs from one end of the solid
    round to the other; `closed` joins the last point back to the first so the result is a shell
    with no open border - important now that every material is backface-culled."""
    cx, cy, cz = centre
    rings = []
    for (w, r) in profile:
        ring = []
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            ring.append(bm.verts.new(Vector((cx + axis_x * w,
                                             cy + math.cos(a) * r,
                                             cz + math.sin(a) * r))))
        rings.append(ring)
    seq = rings + ([rings[0]] if closed else [])
    for i in range(len(seq) - 1):
        a, b = seq[i], seq[i + 1]
        for k in range(segs):
            k2 = (k + 1) % segs
            f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            f.material_index = mat
    return rings


def brake_disc(bm, centre, axis_x, mat):
    """A cross-drilled disc: two friction faces built as matching polar grids with cells deleted
    to make the holes, and the four quads round each deleted cell bridged front to back so the
    hole has walls. Drilling it for real costs about 500 quads and is the difference between a
    brake and a grey coaster."""
    cx, cy, cz = centre
    r_in, r_out = 0.112, DISC_R
    nrad = 4
    half = 0.017
    grids = []
    for side in (-1.0, 1.0):
        g = []
        for i in range(nrad + 1):
            r = r_in + (r_out - r_in) * i / nrad
            row = []
            for k in range(DISC_SEG):
                a = 2.0 * math.pi * k / DISC_SEG
                row.append(bm.verts.new(Vector((cx + axis_x * side * half,
                                                cy + math.cos(a) * r,
                                                cz + math.sin(a) * r))))
            g.append(row)
        grids.append(g)
    holes = set()
    for i in (1, 2):
        for k in range(DISC_SEG):
            if (k + i) % 3 == 0:
                holes.add((i, k))
    for gi, g in enumerate(grids):
        for i in range(nrad):
            for k in range(DISC_SEG):
                if (i, k) in holes:
                    continue
                k2 = (k + 1) % DISC_SEG
                q = (g[i][k], g[i][k2], g[i + 1][k2], g[i + 1][k])
                f = bm.faces.new(q if gi == 0 else q[::-1])
                f.material_index = mat
    a_, b_ = grids
    for (i, k) in holes:                       # the four walls of each drilling
        k2 = (k + 1) % DISC_SEG
        loop = [(i, k), (i, k2), (i + 1, k2), (i + 1, k)]
        for t in range(4):
            (ia, ka), (ib, kb) = loop[t], loop[(t + 1) % 4]
            f = bm.faces.new((a_[ia][ka], b_[ia][ka], b_[ib][kb], a_[ib][kb]))
            f.material_index = mat
    for (ridx, flip) in ((0, True), (nrad, False)):   # inner bore and outer edge bands
        for k in range(DISC_SEG):
            k2 = (k + 1) % DISC_SEG
            q = (a_[ridx][k], b_[ridx][k], b_[ridx][k2], a_[ridx][k2])
            f = bm.faces.new(q[::-1] if flip else q)
            f.material_index = mat
    # cooling vanes between the two friction plates, visible through the drillings
    for k in range(0, DISC_SEG, 2):
        a = 2.0 * math.pi * (k + 0.5) / DISC_SEG
        ca, sa = math.cos(a), math.sin(a)
        for t in (0.30, 0.72):
            r = r_in + (r_out - r_in) * t
            bm_box(bm, (cx, cy + ca * r, cz + sa * r), (0.030, 0.016, 0.016), mat,
                   rot_x=a)


def build_wheel(bm, side, front, mats_unused=None):
    """One corner. side = +1 right, front = True for the front axle."""
    hw = TYRE_W[0 if front else 1] * 0.5
    cx = side * (TYRE_OUT - hw)
    cy = AXLE if front else -AXLE
    cz = HUB_Z
    axis = side                                # +1 points outboard
    bead = RIM_R - 0.010
    hb = hw * 0.80
    # --- tyre: bead -> sidewall bulge -> shoulder -> tread -> and back, then a closing wall
    prof = [(hb, RIM_R - 0.014), (hb, bead), (hw * 1.00, 0.288), (hw * 1.045, 0.316),
            (hw * 0.995, 0.3455), (hw * 0.915, TYRE_R - 0.0062), (hw * 0.78, TYRE_R - 0.0016),
            (0.0, TYRE_R), (-hw * 0.78, TYRE_R - 0.0016), (-hw * 0.915, TYRE_R - 0.0062),
            (-hw * 0.995, 0.3455), (-hw * 1.045, 0.316), (-hw * 1.00, 0.288),
            (-hb, bead), (-hb, RIM_R - 0.014)]
    lathe(bm, (cx, cy, cz), axis, prof, TYRE, closed=True)
    # --- alloy: outer flange lip, barrel, inner flange. One closed lathe.
    rim = [(hb * 1.10, RIM_R - 0.022), (hb * 1.12, RIM_R - 0.004), (hb * 1.10, RIM_R + 0.010),
           (hb * 0.98, RIM_R + 0.012), (hb * 0.88, RIM_R - 0.004), (hb * 0.40, RIM_R - 0.030),
           (-hb * 0.30, RIM_R - 0.034), (-hb * 0.88, RIM_R - 0.006),
           (-hb * 1.02, RIM_R + 0.008), (-hb * 1.10, RIM_R - 0.004),
           (-hb * 1.10, RIM_R - 0.022)]
    lathe(bm, (cx, cy, cz), axis, rim, TRIM, closed=True)
    # --- spokes. Dished: the hub end sits 6 cm inboard of the rim end, which is what makes a
    #     wheel look like a wheel from three-quarters instead of like a printed disc.
    x_rim = hb * 0.90
    x_hub = hb * 0.90 - 0.062
    r0, r1 = 0.086, RIM_R - 0.004
    for s in range(SPOKES):
        a0 = 2.0 * math.pi * (s + 0.5) / SPOKES
        rings = []
        nr = 5
        for i in range(nr + 1):
            t = i / nr
            r = r0 + (r1 - r0) * t
            a = a0 + 0.13 * (1.0 - t) ** 1.3           # a little sweep, so it is not a spoke wheel
            x = x_hub + (x_rim - x_hub) * (t ** 0.75)
            hu = 0.019 + 0.020 * t ** 1.5              # tangential half width, widening outward
            hv = 0.021 - 0.009 * t                     # axial half thickness, thinning outward
            ca, sa = math.cos(a), math.sin(a)
            tang = Vector((0.0, -sa, ca))              # tangential in the wheel plane
            axl = Vector((1.0, 0.0, 0.0))
            rings.append(super_ring(bm, (cx + axis * x, cy + ca * r, cz + sa * r),
                                    tang, axl, hu, hv, 3.2, 10))
        loft_rings(bm, rings, TRIM)
    # --- hub face and centre-lock nut
    lathe(bm, (cx, cy, cz), axis, [(x_hub - 0.004, 0.030), (x_hub + 0.020, 0.040),
                                   (x_hub + 0.022, 0.098), (x_hub - 0.012, 0.104),
                                   (x_hub - 0.016, 0.030)], TRIM, segs=24, closed=True)
    lathe(bm, (cx, cy, cz), axis, [(x_hub + 0.020, 0.004), (x_hub + 0.040, 0.026),
                                   (x_hub + 0.030, 0.038), (x_hub + 0.006, 0.038),
                                   (x_hub + 0.006, 0.004)], TRIM, segs=6, closed=True)
    # --- brake disc and caliper, behind the spokes
    brake_disc(bm, (cx - axis * 0.018, cy, cz), axis, TRIM)
    a_cal = math.radians(118.0 if front else 62.0)
    def caliper(u, v, a_cal=a_cal, cx=cx, cy=cy, cz=cz, axis=axis):
        a = a_cal + (v - 0.5) * 1.05
        r = 0.176 + 0.090 * u
        return Vector((cx - axis * 0.018 + 0.040, cy + math.cos(a) * r, cz + math.sin(a) * r))
    bm_plate(bm, 5, 10, caliper, 0.080, TRIM, thick_dir=(1.0 * axis, 0.0, 0.0))


def build_wheels(mats):
    bm = bmesh.new()
    for side in (-1.0, 1.0):
        for front in (True, False):
            build_wheel(bm, side, front)
    ob = new_object(PREFIX + "wheels", bm, mats)
    bmesh_recalc(ob)
    return ob


# =============================================================================================
# The rest of the detail: grille meshes, vanes, louvres, mirrors, handles, exhausts, interior
# =============================================================================================
def build_details(body, mats):
    """Everything that is not skin or aero. Positions come from the loft surface wherever a part
    has to sit on or in the body, so moving a section key moves the parts with it instead of
    leaving slats floating in the middle of an intake."""
    bm = bmesh.new()
    on = body.on

    # --- honeycomb behind the low front mouth. A grille has to be a MESH: a black-painted flat
    #     face is exactly what makes a nose read as a toy. Two crossed sets of thin bars in the
    #     recess, so light gets through the gaps and the depth is visible. ------------------
    def honeycomb(f_at, g_a, g_b, depth, nx, ny, bar, mirror_side=None):
        pa, _ = on(f_at, g_a, depth)
        pb, _ = on(f_at, g_b, depth)
        cx, cz = 0.5 * (pa.x + pb.x), 0.5 * (pa.z + pb.z)
        w = abs(pa.x - pb.x)
        h = abs(pa.z - pb.z)
        span = max(w, 0.05)
        for k in range(nx):
            x = cx - span * 0.5 + span * (k + 0.5) / nx
            bm_box(bm, (x, 0.5 * (pa.y + pb.y), cz), (bar, 0.020, h + 0.020), TRIM)
        for k in range(ny):
            z = cz - h * 0.5 + h * (k + 0.5) / ny
            bm_box(bm, (cx, 0.5 * (pa.y + pb.y) - 0.012, z), (span + 0.020, 0.020, bar), TRIM)

    honeycomb(2.075, 58.6, 5.4, 0.105, 13, 4, 0.013)
    # corner intakes: vertical vanes, angled outboard
    for sgn in (-1.0, 1.0):
        for k in range(4):
            g = 9.6 + k * 1.05
            pt, _ = on(2.075, g if sgn > 0 else (64.0 - g) % 64.0, 0.072)
            bm_box(bm, (pt.x, pt.y, pt.z), (0.014, 0.080, 0.150), TRIM, rot_z=sgn * 0.22)

    # --- side intake vanes, hung off the surface the intake was cut from -------------------
    for sgn in (-1.0, 1.0):
        for k in range(4):
            f = -0.500 - k * 0.096
            pt, _ = on(f, 12.6 if sgn > 0 else 51.4, 0.120)
            bm_box(bm, (pt.x, pt.y, pt.z), (0.085, 0.024, 0.210), TRIM, rot_z=sgn * 0.12)
        for k in range(3):
            f = -0.520 - k * 0.110
            pt, _ = on(f, 6.2 if sgn > 0 else 57.8, 0.062)
            bm_box(bm, (pt.x, pt.y, pt.z), (0.048, 0.022, 0.080), TRIM, rot_z=sgn * 0.10)
        for k in range(3):
            pt, _ = on(0.762 + k * 0.045, 12.0 if sgn > 0 else 52.0, 0.048)
            bm_box(bm, (pt.x, pt.y, pt.z), (0.044, 0.022, 0.100), TRIM, rot_z=sgn * 0.16)

    # --- engine deck louvres, lying in the dish between the buttresses --------------------
    for k in range(15):
        f = -0.700 - k * 0.056
        pt, _ = on(f, 32.0, 0.014)
        pe, _ = on(f, 29.6, 0.014)
        bm_box(bm, (0.0, pt.y, pt.z - 0.004), (abs(pe.x) * 2.0 - 0.02, 0.024, 0.030),
               TRIM, rot_x=0.52)
    # --- slats in the bonnet outlet ---
    for k in range(5):
        f = 1.480 + k * 0.062
        pt, _ = on(f, 32.0, 0.020)
        pe, _ = on(f, 30.2, 0.020)
        bm_box(bm, (0.0, pt.y, pt.z - 0.003), (abs(pe.x) * 2.0 - 0.02, 0.022, 0.024),
               TRIM, rot_x=-0.44)
    # --- louvres over the rear arches -----------------------------------------------------
    for sgn in (-1.0, 1.0):
        for k in range(4):
            f = -1.280 - k * 0.068
            pt, _ = on(f, 20.2 if sgn > 0 else 43.8, 0.028)
            bm_box(bm, (pt.x, pt.y, pt.z), (0.150, 0.024, 0.026), TRIM, rot_x=0.40)

    # --- mirrors on proper stalks, anchored on the skin at the door top -------------------
    for sgn in (-1.0, 1.0):
        root, _ = on(0.840, 20.4 if sgn > 0 else 43.6, 0.006)
        tip = Vector((sgn * 0.998, root.y - 0.046, root.z + 0.052))
        mid = root * 0.42 + tip * 0.58
        # A round blob on a hairline arm read as an egg floating over the wing. A real door
        # mirror is a flattened shell on a visible strut, so: a chunky tapered stalk and a
        # housing that is a box the bevel rounds off, with the glass recessed in its back face.
        bm_box(bm, tuple(mid), (abs(tip.x - root.x) + 0.03, 0.040, 0.028), TRIM, rot_x=-0.30)
        bm_box(bm, (tip.x, tip.y, tip.z), (0.046, 0.126, 0.062), PAINT,
               rot_z=sgn * 0.10, taper=0.82)
        bm_box(bm, (tip.x + sgn * 0.010, tip.y - 0.050, tip.z), (0.026, 0.024, 0.052),
               GLASS, rot_z=sgn * 0.10)

    # --- door pulls: a trim tab lying in the dish the skin already has --------------------
    for (hf, hg) in HANDLES:
        pt, _ = on(hf, hg, 0.005)
        bm_box(bm, (pt.x, pt.y, pt.z), (0.024, 0.124, 0.026), TRIM,
               rot_z=(0.03 if pt.x > 0 else -0.03))

    # --- fuel flap: a paint disc inside a dark ring, which is all a flap ever is -----------
    pt, nf = on(FLAP["f"], FLAP["g"], 0.004)
    bm_disc(bm, pt, nf, FLAP["r"], 0.012, TRIM, 20)
    bm_disc(bm, pt - nf * 0.0035, nf, FLAP["r"] - 0.007, 0.010, PAINT, 20)

    # --- badge recesses. A recess, never a badge: badges are somebody's trademark ----------
    for (bf, bg) in ((1.830, 32.0), (-2.040, 32.0)):
        pt, nb = on(bf, bg, 0.010)
        bm_disc(bm, pt, nb, 0.045, 0.016, TRIM, 18, scale_u=1.7)

    # --- exhausts: real tubes with visible inner walls, above the diffuser ------------------
    #     Bigger and further proud than the first pass, where they read as two drawn-on rings.
    for sgn in (-1.0, 1.0):
        for dx in (-0.082, 0.082):
            bm_tube(bm, (sgn * 0.250 + dx, -2.150, 0.508), 0.064, 0.048, 0.260, TRIM, 20)
            bm_tube(bm, (sgn * 0.250 + dx, -2.258, 0.508), 0.076, 0.062, 0.030, TRIM, 20)
            bm_tube(bm, (sgn * 0.250 + dx, -2.272, 0.508), 0.070, 0.050, 0.016, TRIM, 20)

    # --- rear light bar. The tail is a Kamm cut, and a flat red panel with two slashes at the
    #     corners is what it looked like without this: one lit band across the whole width is
    #     the thing that says "modern" from behind. It follows the cap's slight dome so it sits
    #     on the surface instead of cutting into it at the edges.
    for k in range(17):
        t = (k + 0.5) / 17.0
        x = -0.706 + 1.412 * t
        a = min(abs(x) / 0.720, 1.0)
        y = -2.184 - 0.014 * (1.0 - a * a)
        bm_box(bm, (x, y - 0.014, 0.752 - 0.060 * a * a), (0.108, 0.066, 0.082), TRIM)
        bm_box(bm, (x, y - 0.030, 0.752 - 0.060 * a * a), (0.094, 0.050, 0.050), LIGHT_R)

    # --- windscreen wiper, parked on the cowl ---------------------------------------------
    bm_box(bm, (-0.18, 0.965, 0.818), (0.030, 0.140, 0.016), TRIM, rot_z=0.5)
    bm_box(bm, (0.10, 0.920, 0.858), (0.540, 0.020, 0.012), TRIM, rot_z=0.28)

    # --- a suggestion of an interior, seen through the screen ------------------------------
    bm_box(bm, (0.0, 0.610, 0.880), (1.28, 0.30, 0.10), TRIM, rot_x=-0.26)       # dash top
    for sgn in (-1.0, 1.0):
        bm_box(bm, (sgn * 0.315, 0.090, 0.610), (0.44, 0.44, 0.10), TRIM)        # cushion
        bm_box(bm, (sgn * 0.315, -0.170, 0.850), (0.42, 0.10, 0.46), TRIM, rot_x=0.22)
    bm_sphere(bm, (-0.36, 0.470, 0.880), 0.140, TRIM, 16, 7, scale=(1.0, 0.16, 1.0))

    ob = new_object(PREFIX + "detail", bm, mats)
    bmesh_recalc(ob)
    bevel(ob, 0.0045, segments=1, angle=34.0)
    return ob


# =============================================================================================
# Build / export / verify
# =============================================================================================
def build():
    reset_scene()
    mats = make_materials()
    body = Body(Loft(KEYS))
    shell, nS, nR, cage = build_shell(body, mats)
    scoop = build_scoop(body, mats)
    aero = build_aero(body, mats)
    parts = [shell, build_glass(body, mats), build_interior(body, mats),
             build_lenses(body, mats), scoop, aero, build_details(body, mats),
             build_wheels(mats)]
    for p in (scoop, aero):
        bmesh_recalc(p)
    bevel(aero, 0.0040, segments=2, angle=30.0)
    ob = join(parts)
    ob.name = PREFIX + "coupe"
    ob.data.name = ob.name
    shade(ob)
    body_uv(ob)
    print("  cage %d quads, %d stations x %d ring, subdiv %d" % (cage, nS, nR, SUBDIV))
    return ob


def body_uv(ob, v_scale=0.21, axis_z=0.46):
    """A UV set. The old file exported POSITION and NORMAL only, so Godot's
    meshes/ensure_tangents=true fabricated tangents from nothing and any normal map, dirt map,
    livery or decal on this body was broken before it started.

    Cylindrical about the car's own long axis: u is the angle round the section, v is the
    distance along the car. Two reasons it is not the obvious per-face triplanar box projection:
    a car body IS a tube, so this is close to how one is really unwrapped; and because the UV
    depends only on the VERTEX position, every loop of a vertex gets the same UV and the
    exporter splits nothing. A per-face projection flips its axis all over a curved panel and
    would have shipped a mesh with thousands of UV seams in the middle of the bodywork."""
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    co = [v.co for v in me.vertices]
    loops = me.loops
    data = uvl.data
    inv = 1.0 / (2.0 * math.pi)
    uvs = [(math.atan2(p[0], p[2] - axis_z) * inv + 0.5, p[1] * v_scale + 0.5) for p in co]
    for li in range(len(loops)):
        data[li].uv = uvs[loops[li].vertex_index]


def export(ob, name):
    path = os.path.join(OUT_DIR, PREFIX + name + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True,
        export_apply=True, export_materials='EXPORT', export_yup=True,
        export_normals=True, export_texcoords=True, export_tangents=False,
        export_skins=False, export_animations=False, export_cameras=False,
        export_lights=False,
    )
    return path


def verify(path):
    """Read the numbers back out of the file that was actually written, not out of the scene."""
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    tris = 0
    per = {}
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    names = []
    for ob in list(bpy.context.scene.objects):
        if ob.type != 'MESH':
            continue
        me = ob.data
        me.calc_loop_triangles()
        slots = [ms.material.name if ms.material else "<none>" for ms in ob.material_slots]
        for n in slots:
            if n not in names:
                names.append(n)
        for t in me.loop_triangles:
            tris += 1
            si = me.polygons[t.polygon_index].material_index
            k = slots[si] if si < len(slots) else "<none>"
            per[k] = per.get(k, 0) + 1
        for v in me.vertices:
            w = ob.matrix_world @ v.co
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return tris, mn, mx, per, names


def main(argv):
    os.makedirs(OUT_DIR, exist_ok=True)
    ob = build()
    path = export(ob, "coupe")
    if "--no-verify" in argv:
        print("  -> " + path)
        return
    tris, mn, mx, per, names = verify(path)
    # The importer converts glTF's Y-up back to Blender's Z-up, so this is the authored frame:
    # X lateral, Y longitudinal, Z up - the same numbers the KEYS table is written in.
    print("READ BACK FROM %s" % os.path.basename(path))
    print("  triangles : %d" % tris)
    print("  bbox      : width %.3f  length %.3f  height %.3f"
          % (mx.x - mn.x, mx.y - mn.y, mx.z - mn.z))
    print("  extents   : y %+.3f .. %+.3f (centre %+.4f)  z %.4f .. %.4f"
          % (mn.y, mx.y, 0.5 * (mn.y + mx.y), mn.z, mx.z))
    print("  stance    : wheel centres %.3f above the lowest vertex, arches at y %+.3f/%+.3f"
          % (HUB_Z - mn.z, AXLE, -AXLE))
    print("  slots     : " + ", ".join(names))
    print("  per slot  : " + ", ".join("%s=%d" % (k, v) for k, v in sorted(per.items())))
    print("  -> " + path)


if __name__ == "__main__":
    main(sys.argv[1:])
