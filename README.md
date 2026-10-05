# Reflection probes and the street HDRI (wt/reflection-probes)

All stills are **Forward+** (lavapipe, the renderer the Mac uses), 1280x720, 15:00, in a small
street of real generated Buildings with the city's own Environment, sun and DayNight
(`tools/reflections/probe_shot.gd`; SDFGI and volumetric fog off, i.e. the MEDIUM level's effects,
because lavapipe cannot render SDFGI in minutes). "Before" is `PROBES=0 HDRI=0` (today's look); "after" is
the shipped setting (probes without shadows, the street HDRI).

| File | What |
|---|---|
| 01 / 02 | A dark car's door and bonnet from the pavement: before (sky radiance + flat grey street) / after (the street's probe) |
| 03 / 04 | The bonnet from the driver's seat height: after, it mirrors the brick facades and the dark street instead of bright sky |
| 05 / 06 | A glass tower from the street: after, its lower floors (under 30 m, inside the probes' reach) mirror the real street through a tinted mirror |
| 07 / 08 | Down the street: shop and office glass at street level |
| 09 / 10 / 11 | A chrome ball in mid-street: before (sky + flat grey), the street HDRI only (what reflections out of a probe's reach see), with the probe (the canyon's facades, box-projected) |
| 12 | Crop of 05 / 06, the tower glass |
