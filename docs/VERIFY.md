# The verify pack: ten pictures from your Mac

Every picture the fleet looks at is drawn on a Linux box with the **web renderer**
(Compatibility). Your Mac draws the game with the **real renderer** (Forward+: global
illumination, reflections, the volumetric clouds, temporal anti-aliasing). Nobody has seen wave 3
on it. The verify pack takes the same ten views the fleet measures every build with (the
reference cameras: street at noon, street at night in the rain, the sunset, two aerials, the
beach, the hills, the freeway, MacArthur Park, the pier at night), on YOUR Mac, so we can see what
you see and fix what looks wrong there.

It takes about two minutes. You do not need Terminal or Godot.

## What to do

1. Download the newest build from
   https://github.com/ashalluf/rando-game/releases/latest and open **Rando Game.app**
   (the first time: System Settings > Privacy & Security > **Open Anyway**).
2. Wait for the city to load, then press **Esc** (the pause menu).
3. Click **Verify pack (10 pictures)**, near the bottom of the left column.
4. Hands off for about two minutes. The game jumps to each of the ten views, sets its time of day
   and weather, holds it for three seconds and takes a picture. The top-left corner says which
   one it is on ("VERIFY PACK 3 / 10 ..."). The jumps can stutter: that is the city being built
   at each place, it is expected. **Esc** stops it early (what it took so far is kept).
5. A card says "10 of 10 pictures taken" and where they are. Click **Open folder** (Finder opens
   it), then **Done**: you are back where you were, at the hour and weather you had.

The folder is **Pictures > Rando Game > verify_396** (the number is the build). A second run of
the same build makes `verify_396_2`, so nothing is overwritten.

## What to send back

Open the **send** folder inside it and send everything in it:

- `sheet.jpg` - all ten pictures on one page, with the frame rate and numbers under each;
- `report.txt` - your Mac, its graphics chip, the renderer, the window size, the graphics level,
  and per picture the frame rate, the worst frame, CPU / GPU time and the brightness numbers;
- `01_street_noon.jpg` ... `10_pier_night.jpg` - the ten pictures, 1280 wide (small enough to
  attach to a chat message).

On a phone: AirDrop the `send` folder to the phone (or select its files, right click, Share),
then attach them to the chat. Add a line about anything that looks wrong to you on the Mac that
does not show in the pictures (stutter, a flicker, a sound).

The full-size PNGs (`01_street_noon.png` ...) and `report.json` stay in the main folder; send
them only if asked.

## Good to know

- The pictures are taken at the graphics level the game is on (the pause menu's GRAPHICS row).
  Leave it on **Auto** unless asked; the pack holds the level steady while it runs and puts Auto
  back afterwards.
- The HUD is hidden in the pictures and the player is parked out of sight; he is put back where
  he stood.
- If the card says nothing could be saved, the Pictures folder could not be written; the pack
  then tries the game's own data folder
  (`~/Library/Application Support/Godot/app_userdata/Rando Game/verify`).

## For the fleet

- The pack is `VerifyPack` (`scripts/ui/verify_pack.gd`), added beside the pause menu. Its camera
  table is `tools/refcams/cameras.json`'s, copied into the script (the export ships no .json;
  `tests/mac_verify_pack_checks.gd` holds the two equal). Change a camera in both.
- Command line: `-- --verify` runs it once the city has loaded; `VERIFY_QUIT=1` quits after;
  `VERIFY_DIR=<dir>` writes there; `VERIFY_ONLY=beach,hills` a subset; `VERIFY_HOLD=<s>` the hold;
  `VERIFY_PACK=0` removes it (the A/B).
- The build number comes from `BuildInfo` (`scripts/util/build_info.gd`), stamped by the workflow
  just before the export ("Stamp the build number"); a local run says `dev`.
- Reading a pack: the brightness numbers (p5 / p50 / p95) are `tools/refcams/refcams.py`'s
  (PIL's L), so a Mac shot reads against the same camera's opengl3 numbers in a refcams run. The
  Mac shots are at the window's size, the fleet's at 1280 x 720.
- Harness (opengl3 under Xvfb, how this was proved):
  `VERIFY_DIR=$PWD/build/verify_run VERIFY_QUIT=1 xvfb-run -a -s "-screen 0 1280x720x24" godot
  --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path .
  --resolution 1280x720 -- --verify` (about 6 minutes on a 4-core box, the load included).
