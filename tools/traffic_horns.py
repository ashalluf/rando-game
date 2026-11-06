"""Close-range car horns for the traffic (TrafficAI honks, Sfx `car_horn` / `car_horn_long`).

    python3 tools/ambience_audio.py get 182474 434878 423990 461679 349922
    python3 tools/traffic_horns.py
    godot --headless --path . --import

The same five CC0 Freesound recordings the ambience's far horns are cut from (tools/ambience_audio.py
SHOTS, docs/ASSETS.md), cut here into short taps and double taps (`car_horn`: somebody who will
not go on green, a pedestrian in the road) and long leans on the horn (`car_horn_long`: a near
miss, a car blocking the lane). Peak -1 dB, mono, 44.1 kHz Vorbis; the loudest-50 ms number each
prints is what Sfx.SAMPLE_LOUDNESS_DB records.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ambience_audio as A  # noqa: E402

SHOTS = [
    ("car_horn_0", 434878, (0.0, 0.5), {"fade": 0.08}),
    ("car_horn_1", 423990, (0.08, 0.6), {"fade": 0.08}),
    ("car_horn_2", 461679, (0.5, 0.86), {"fade": 0.08}),
    ("car_horn_3", 349922, (0.0, 0.34), {"fade": 0.07}),
    ("car_horn_4", 349922, (1.43, 2.04), {"fade": 0.08}),
    ("car_horn_long_0", 182474, (1.2, 2.72), {"fade": 0.15}),
    ("car_horn_long_1", 349922, (1.43, 3.1), {"fade": 0.15}),
    ("car_horn_long_2", 461679, (1.88, 2.38), {"fade": 0.1}),
]

if __name__ == "__main__":
    for name, sid, span, o in SHOTS:
        r = A.make_shot(A.OUT, name, sid, span, o)
        print("%-16s %6d %5.2f s %3d KB  loudest %.2f  %s" % (name, sid, r["dur"], r["kb"], r["loud"], r["where"]))
