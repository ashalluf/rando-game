# Wave 4 task: gunplay-feel (kind: new)

Branch `wt/gunplay-feel`, stills on `shots/gunplay-feel`.

The guns' feedback at arm's length: muzzle flash (volumetric, lights the hands and the wall), the smoke after a burst, the brass in flight, the recoil animation on the hero's arms and the camera, the impact decals' variety by surface, tracers' look, the shotgun's spread marks. WeaponFX / the weapons' _fire; strips with post_room_shot.gd MODE=fire and hero_shot.gd. Never route round Weapon.tick (the Sanctuary rule). Another session (explosions-3) owns the explosion and fire; another (blood-gore-2) the blood.

If `origin/wt/gunplay-feel` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/gunplay-feel`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
