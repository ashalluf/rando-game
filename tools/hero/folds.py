"""The tracksuit's fold field, shared by the modelling step (tracksuit.py, inside Blender) and the
texture step (prep_textures.py, plain python3). numpy only.

A fold is a height along the surface normal, in metres, as a function of where a point sits on
the body: how far along an arm or leg it is (u), which way round the limb it faces (az: 0 is
the front, +pi/2 the outside of the limb), and the torso's own landmarks. Three versions:

  geom   the low-frequency drape the game mesh itself carries (it has ~18k triangles, so
         anything finer than a few centimetres cannot live in the geometry)
  rest   everything a standing figure shows: cuff and ankle stacking, hem blousing, a soft
         crook at the elbow, the knee, the hip crease, drape
  bent   rest plus the folds that only appear when a joint closes: deep rings in the crook of
         the elbow and behind the knee, bags on the front of the knee

The normal maps are made from (rest - geom) and (bent - geom): the geometry already has its own
part, so the map only adds what the mesh cannot hold. The game blends rest -> bent per joint
from the skeleton every frame (shaders/hero_cloth.gdshader, HeroLook.update_wrinkles()).
"""
import numpy as np

# Blender-space landmarks (metres, Z up, the figure faces -Y) come in as a dict of 3-vectors.


def _hash3(ix, iy, iz, seed):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = h & 0xFFFFFFFF
    h = ((h ^ (h >> 15)) * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 3266489917) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / float(0xFFFFFF) * 2.0 - 1.0


def vnoise(p, seed=0):
    """Smooth 3D value noise in [-1, 1] (p: (N, 3))."""
    p = np.asarray(p, np.float64)
    i = np.floor(p).astype(np.int64)
    f = p - i
    u = f * f * (3.0 - 2.0 * f)
    out = 0.0
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1.0 - u[:, 0]
        for dy in (0, 1):
            wy = u[:, 1] if dy else 1.0 - u[:, 1]
            for dz in (0, 1):
                wz = u[:, 2] if dz else 1.0 - u[:, 2]
                out = out + wx * wy * wz * _hash3(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def ridge(v):
    """A sine turned into cloth: soft round crests, flatter valleys."""
    return np.maximum(v, 0.0) ** 1.35 - 0.22


def _v(L, k):
    return np.asarray(L[k], np.float64)


def limb_frame(p, a, b):
    """Distance along a->b from a, azimuth round it (0 = front, +pi/2 = the +X side) and radius."""
    ax = (b - a) / np.linalg.norm(b - a)
    d = p - a
    s = d @ ax
    r = d - np.outer(s, ax)
    fwd = np.array([0.0, -1.0, 0.0])
    fwd = fwd - ax * (fwd @ ax)
    fwd /= np.linalg.norm(fwd)
    lat = np.cross(ax, fwd)
    if lat[0] < 0:
        lat = -lat
    return s, np.arctan2(r @ lat, r @ fwd), np.linalg.norm(r, axis=1)


def chain_frame(p, a, b, c):
    """u along the two-segment chain a->b->c and the azimuth round whichever segment it is on."""
    L1 = np.linalg.norm(b - a)
    s1, a1, _ = limb_frame(p, a, b)
    s2, a2, _ = limb_frame(p, b, c)
    first = s1 <= L1
    return np.where(first, s1, L1 + s2), np.where(first, a1, a2), L1, L1 + np.linalg.norm(c - b)


def seg_dist(p, a, b):
    """Distance from points p to the segment a-b."""
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0.0, 1.0)
    return np.linalg.norm(p - (a + np.outer(t, ab)), axis=1)


def arm_mask(p, L, side, reach=0.085):
    """The sleeve: near the upper arm or the forearm on that side. By distance from the bones,
    not by |x|: bound with the arms hanging, the torso's sides are as far out as the sleeves."""
    sh, el, wr = _v(L, side + "Arm"), _v(L, side + "ForeArm"), _v(L, side + "Hand")
    same = (p[:, 0] > 0) == (sh[0] > 0)
    near = np.minimum(seg_dist(p, sh, el), seg_dist(p, el, wr)) < reach
    return same & near


def fields(p, jacket, L, which=("geom", "rest", "bent")):
    """Fold heights (metres) for points p (N, 3); jacket (N,) bool says jacket (else trousers)."""
    p = np.asarray(p, np.float64)
    n = len(p)
    n1 = vnoise(p * 7.0, 1)
    drape = 0.0028 * vnoise(p * 9.0 + np.array([3.1, 1.7, 0.3]), 2)
    geom = drape.copy()
    rest = drape.copy()
    bent_extra = np.zeros(n)
    z_hem = L["z_hem"]
    chest = _v(L, "Spine2")
    hips = _v(L, "Hips")
    sleeve_end = L["sleeve_end"]
    on_arm = np.zeros(n, bool)
    for side in ("Left", "Right"):
        sh, el, wr = _v(L, side + "Arm"), _v(L, side + "ForeArm"), _v(L, side + "Hand")
        m = jacket & arm_mask(p, L, side)
        # A point past the shoulder joint and not below the armpit is on the sleeve.
        s0, _, _ = limb_frame(p, sh, el)
        m &= s0 > -0.05
        on_arm |= m
        if not m.any():
            continue
        u, az, L1, Ltot = chain_frame(p[m], sh, el, wr)
        nn = n1[m]
        we = np.exp(-((u - L1) / 0.075) ** 2)
        crook = 0.45 + 0.55 * np.maximum(0.0, np.cos(az))
        rings = ridge(np.sin(2 * np.pi * u / 0.027 + 1.4 * np.sin(az) + 2.2 * nn))
        rest[m] += 0.0040 * we * crook * rings
        # closed elbow: deep rings bunched into the crook, and tension folds fanning round the
        # point of the elbow on the outside
        wb = np.exp(-((u - L1) / 0.06) ** 2)
        deep = ridge(np.sin(2 * np.pi * u / 0.021 + 1.8 * np.sin(az) + 2.6 * nn))
        inner = np.maximum(0.0, np.cos(az)) ** 1.5
        bent_extra[m] += 0.0085 * wb * inner * deep
        fan = ridge(np.sin(2 * np.pi * (u - L1) / 0.035 + 3.0 * az + 1.5 * nn))
        bent_extra[m] += 0.0035 * np.exp(-((u - L1) / 0.09) ** 2) * np.maximum(0.0, -np.cos(az)) * fan
        # sleeve stacking above the cuff (always there: the sleeve is longer than the arm)
        u_end = Ltot - sleeve_end
        wc = smoothstep(u_end - 0.16, u_end - 0.015, u)
        stack = 0.0055 * wc * ridge(np.sin(2 * np.pi * u / 0.023 + 0.9 * np.sin(2 * az) + 2.5 * nn))
        rest[m] += stack
        # upper arm drape under the shoulder: long soft diagonals
        wa = np.exp(-((u - 0.06) / 0.08) ** 2) * np.maximum(0.0, -np.sin(az))
        rest[m] += 0.0035 * wa * ridge(np.sin(2 * np.pi * (u * 0.7 + az * 0.03) / 0.03 + nn))
    torso = jacket & ~on_arm
    if torso.any():
        q = p[torso]
        nn = n1[torso]
        # blousing above the hem band
        wh = 1.0 - smoothstep(z_hem + 0.02, z_hem + 0.13, q[:, 2])
        back = np.where(q[:, 1] > hips[1], 0.55, 0.8)
        blouse = 0.0065 * wh * back * ridge(np.sin(2 * np.pi * q[:, 2] / 0.043 + 1.8 * nn + 1.1 * np.sin(q[:, 0] * 25)))
        rest[torso] += blouse
        geom[torso] += 0.5 * blouse
        # chest drape: long vertical folds from the shoulders, faint
        wd = smoothstep(z_hem + 0.1, chest[2], q[:, 2]) * np.where(q[:, 1] < chest[1], 1.0, 0.5)
        cd = 0.0025 * wd * np.sin(2 * np.pi * q[:, 0] / 0.085 + 2.0 * nn)
        rest[torso] += cd
        geom[torso] += cd
        # shoulder-blade tension on the back
        tb = (q[:, 1] > chest[1]) & (q[:, 2] > chest[2] - 0.05)
        rest[torso] += np.where(tb, 0.0009 * ridge(np.sin(2 * np.pi * (q[:, 2] + np.abs(q[:, 0]) * 0.6) / 0.06 + nn)), 0.0)
    legs = ~jacket
    if legs.any():
        q = p[legs]
        nn = n1[legs]
        out_r = np.zeros(len(q))
        out_g = np.zeros(len(q))
        out_b = np.zeros(len(q))
        for side, sgn in (("Left", 1.0), ("Right", -1.0)):
            ms = (q[:, 0] * sgn) > 0
            if not ms.any():
                continue
            hip, kn, an = _v(L, side + "UpLeg"), _v(L, side + "Leg"), _v(L, side + "Foot")
            u, az, L1, Ltot = chain_frame(q[ms], hip, kn, an)
            k = nn[ms]
            r = np.zeros(ms.sum())
            g = np.zeros(ms.sum())
            b = np.zeros(ms.sum())
            wk = np.exp(-((u - L1) / 0.06) ** 2)
            backk = 0.35 + 0.65 * np.maximum(0.0, -np.cos(az))
            r += 0.0030 * wk * backk * ridge(np.sin(2 * np.pi * u / 0.031 + 1.2 * np.sin(az) + 2.0 * k))
            # closed knee: tight rings behind it, two or three soft bags over the front
            wkb = np.exp(-((u - L1) / 0.055) ** 2)
            b += 0.0080 * wkb * np.maximum(0.0, -np.cos(az)) ** 1.4 * ridge(np.sin(2 * np.pi * u / 0.022 + 1.5 * np.sin(az) + 2.4 * k))
            b += 0.0040 * np.exp(-((u - L1 + 0.02) / 0.08) ** 2) * np.maximum(0.0, np.cos(az)) * ridge(np.sin(2 * np.pi * u / 0.05 + 0.8 * k))
            # ankle stacking over the cuff: the biggest folds on a track pant
            u_end = (L["z_pants_end"] - hip[2]) / (an[2] - hip[2]) * Ltot
            wa = smoothstep(u_end - 0.20, u_end - 0.02, u)
            st = 0.0095 * wa * ridge(np.sin(2 * np.pi * u / 0.036 + 1.1 * np.sin(az + 0.7) + 3.0 * k))
            r += st
            g += 0.5 * st
            # hip crease: diagonals on the front of the upper thigh
            wcr = np.exp(-((u - 0.10) / 0.09) ** 2) * np.maximum(0.0, np.cos(az))
            r += 0.004 * wcr * ridge(np.sin(2 * np.pi * (u * 0.75 - az * 0.05) / 0.045 + 1.5 * k))
            # seat folds below the buttocks
            wsb = np.exp(-((u - 0.22) / 0.07) ** 2) * np.maximum(0.0, -np.cos(az))
            r += 0.0015 * wsb * ridge(np.sin(2 * np.pi * u / 0.05 + k))
            # long drape hanging from the hip to the knee (loose fabric)
            wdr = smoothstep(0.05, 0.2, u) * (1.0 - smoothstep(L1 - 0.05, L1 + 0.1, u))
            dr = 0.0035 * wdr * np.sin(az * 5 + 1.7 * k + (0.6 if sgn > 0 else 2.1))
            r += dr
            g += dr
            out_r[ms] = r
            out_g[ms] = g
            out_b[ms] = b
        rest[legs] += out_r
        geom[legs] += out_g
        bent_extra[legs] += out_b
    out = {}
    if "geom" in which:
        out["geom"] = geom
    if "rest" in which:
        out["rest"] = rest
    if "bent" in which:
        out["bent"] = rest + bent_extra
    return out


def joint_weights(p, jacket, L):
    """How much of each closing joint's wrinkles a point takes: columns L elbow, R elbow,
    L knee, R knee (the game's wrinkle-mask RGBA)."""
    p = np.asarray(p, np.float64)
    w = np.zeros((len(p), 4))
    for i, side in enumerate(("Left", "Right")):
        sh, el, wr = _v(L, side + "Arm"), _v(L, side + "ForeArm"), _v(L, side + "Hand")
        m = jacket & arm_mask(p, L, side)
        if m.any():
            u, _, L1, _ = chain_frame(p[m], sh, el, wr)
            w[m, i] = np.exp(-((u - L1) / 0.11) ** 2)
        hip, kn, an = _v(L, side + "UpLeg"), _v(L, side + "Leg"), _v(L, side + "Foot")
        sgn = 1.0 if side == "Left" else -1.0
        m = ~jacket & ((p[:, 0] * sgn) > 0)
        if m.any():
            u, _, L1, _ = chain_frame(p[m], hip, kn, an)
            w[m, 2 + i] = np.exp(-((u - L1) / 0.12) ** 2)
    return w
