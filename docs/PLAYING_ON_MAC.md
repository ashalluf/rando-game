# Playing Rando Game on your Mac

Short version: the FIRST launch after an update is slow because your Mac has to build every
shader the city uses for its graphics chip. The game now shows its loading screen, with a moving
bar and a clock, for that whole time. You never see a frozen window, a Godot logo or a black
screen with city sounds any more. The second launch is much faster.

## What you saw on 2026-11-05, and why

You pressed Play on main `2f2fb8f5`. You saw the Godot logo for about 5 minutes, then city sounds
over the same frozen picture for 10 more. Three things caused it, all fixed on `wt/mac-launch`:

1. **No picture was drawn until the city was half built.** Starting the game compiled all
   ~650 game scripts, laid out the basin, painted the far ground, built the streets round you and
   the skyline. That is about 2 minutes on our cloud machine, all in one step, so the window
   showed nothing but the splash. Now a small boot scene puts the loading screen up in the first
   second (2.4 s on our machine) and every long step hands the window a new frame every 80 ms.
2. **Every loading-screen frame drew the whole city behind the screen.** On your Mac (Metal),
   Godot has to build a "pipeline" for every shader and every kind of mesh the first time it draws
   them. That is thousands of them, and the frame waits until they are all built. That wait was
   your 10 minutes of sound with no picture. Now the city is not drawn while it loads. Godot builds
   the same pipelines in the background on all your CPU cores, and the bar keeps moving. The city
   appears only when they are ready. In a test of this on our machine, 30 of the game's shaders
   froze the old way for 95 seconds in one frame. The new way never went more than 2 seconds
   without a frame, and finished in 46 seconds instead of 100.
3. **The city's sounds started before the picture.** The sound is now muted until the loading
   screen fades out.

A fourth fix you never noticed: the automatic graphics level judged your Mac by the loading
screen's frames, which take seconds each. So it could drop from HIGH to LOWEST before you even
started playing. It now ignores the loading screen.

Nothing was turned down to get this. The quality, the city and the settings are exactly the same.

## How long it should take

- **First launch after pulling an update** (new code, so every cache is cold): several minutes
  on the first launch is still expected while Metal builds the pipelines. The loading screen shows
  a clock and, near the end, "COMPILING GRAPHICS (FIRST LAUNCH ONLY)" with a count. Let it run.
- **The next launch with the same code:** much shorter. The shaders are cached by Godot
  (`~/Library/Application Support/Godot/app_userdata/Rando Game/shader_cache`) and by macOS's own
  Metal cache. The basin painting and the far skyline are cached too (`load_cache` in the same
  folder). Any code change starts the caches again, so the first launch of every new build is the
  slow one.
- Please don't force-quit during the first launch. Godot saves its caches as it goes and on exit,
  so a force-quit throws away part of the work and the next launch repeats it.

## The editor or the downloaded app?

Both work, and both show the same loading screen.

- **The downloaded app** (Releases page, `Rando Game.app`) is the better way to play. It skips
  the editor's own work, and each build's first launch is the slow one, once.
- **The editor (Play button):** after pulling many commits, the EDITOR first re-imports the
  assets (its own progress bar, before you press Play). That can take many minutes and is separate
  from the game's load. Running from the editor also compiles the game's scripts from source each
  time.

## Shader baking: why it is not switched on yet

Godot can pre-build ("bake") shaders into the exported app. That would shorten the first launch
of the downloaded app. We are not using it yet, for three reasons:

1. In Godot 4.7.2, apps exported with baked Metal shaders crash on start on Apple Silicon. Two
   open bug reports, godotengine/godot#123266 and #124539, say so. Worse, a crashed run leaves bad
   files in the shader cache, and they make later builds crash too, until that folder is deleted.
2. Baking Metal shaders has to run on a Mac with Apple's Metal compiler and a real GPU. Our
   automatic builds run headless on Linux, which cannot bake. Moving that job to a macOS build
   machine costs about 10 times the build minutes.
3. Baking only saves the first of the two steps. Godot's docs say the final pipeline step always
   happens on your Mac. That step is the one the new loading screen now runs in the background.

When a Godot release fixes those two bugs, we can bake with `shader_baker/enabled=true` in the
macOS export preset. That needs `application/min_macos_version_arm64` set to 14.00 (yours is
14.2.1) and the export run from the editor on a Mac (or a macOS build machine with a GPU).

## If it still seems stuck

The loading screen always moves (the bar has a light running along it and the clock ticks). If
the clock stops for more than a few seconds, run the app from Terminal so its log is visible:

    "/Applications/Rando Game.app/Contents/MacOS/Rando Game"

Then send us the lines that start with `LOADING`. The game now also prints
`LOADING frame gap: <ms> in '<step>'` whenever the window went more than 2 seconds without a new
frame. That line says exactly where it stalled. At the end it prints `LOADING memory: ...` with
how much memory the game uses.
