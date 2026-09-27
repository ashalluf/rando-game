# Street wear (VISUAL_ROADMAP #27) - screenshots

opengl3 harness (Compatibility renderer, flat light: judge materials, not lighting), 960x540,
BEFORE = `STREET_WEAR=0`, AFTER = branch `wt/street-wear`. Same seed, same cameras.

- `wear_atlas_art.jpg` - the generated, original art: tag scribbles (shown pink here, painted
  black/silver/brights in game), throw-ups, roller letters, invented posters and stickers.
- `wear_industrial_east_noon.jpg` - industrial block (15,12): tags and a throw-up on the wall,
  grime along its foot, layered flyers on the utility pole, gum on the pavement.
- `wear_industrial_noon.jpg` / `wear_industrial_night.jpg` - industrial block (3,12) west face.
- `wear_downtown_noon.jpg` / `wear_downtown_night.jpg` - downtown block (4,1): gum, spills, posters
  and stickers on the shop piers.
- `wear_downtown_side_street_noon.jpg` - downtown block (3,2): gum and a spilt drink.
- `wear_pavement_close-up_noon.jpg` - looking down on a downtown pavement: pressed gum, a spilt
  soda, a coffee/oil stain (stains were shrunk and lightened a little after this shot).
- `wear_downtown_side_street_night.jpg` - the side street at 21:30.

Frame cost on these views (GEO, opengl3): +2 draw calls, +6-8k triangles (about 0.1 %).
