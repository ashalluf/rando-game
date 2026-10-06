# shots/engine-audio

Vehicle audio has no picture, so these are the ENGINE_AUDIO_HUD=1 debug panel (opengl3 stills,
not the Mac's Forward+) and a spectrogram sheet of the synthesised loops.

- `01_hud_bus_idling_at_stop.jpg` - a BASIN TRANSIT bus at its stop (BIG=bus): one voice, the bus
  diesel profile in first gear at its 600 rpm idle, only the idle layer playing.
- `02_hud_before_squeal_fix_freeway_cars.jpg` - under the 110 downtown (STREET=queue): four voices
  (a four, two V8s, a V12 with its turbo) on freeway traffic overhead, gears 3-6 at 24-30 m/s,
  the layer gains crossfading; the two SQUEAL flags are the bug this still found (heading steps
  on the lane polylines read as cornering), fixed after it.
- `03_engine_loops_spectrograms.jpg` - every loop's first second, 0-4 kHz: the four's and the
  V-twin's firing pulses at idle, the V8's low rumble, the diesels' knock, the V12's harmonics.
