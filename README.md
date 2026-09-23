# Pokémon Emerald: Godot port

This is an early native Godot port, built alongside the pret source
decompilation in `../pokeemerald-master`.

## Run

Open this folder in Godot 4 and run the project. Move with WASD or arrow keys;
press Z or Enter to talk to the nearby character or dismiss dialogue.

## Current scope

The current field scene starts in Littleroot Town in one continuous map, with
Route 101 to its north, Oldale beyond that, and Route 103 north of Oldale.
These four areas render from their original map blocks, metatiles, palettes,
and tilesets. Matching object-event sprites and the first source dialogue
line are loaded where available. Route tall grass uses the source wild
encounter tables, with native turn-based Tackle battles and original Pokémon
sprites. The temporary party currently starts with Mudkip. Move one grid tile
at a time with WASD or the arrows, interact with Z or Enter, and use X to run
from a wild battle. Use `-` and `=` to change camera zoom. Tree canopy fills
the unused east side beside the 20-tile-wide towns and Route 101.

The importer at `tools/import_maps.py` converts staged indexed tilesheets,
map binaries, route encounter tables, Pokémon sprites, and base stats into
Godot-ready map textures and JSON. Re-run it after changing files in
`assets/source/`.

The renderer uses a 1920×1080 viewport and opens at the same resolution. Its
`canvas_items` stretch mode expands with the resizable window without changing
tile proportions. At the default camera zoom of 1.5, the field shows an
80×45-tile view; `-` and `=` select zoom levels from 1.0 to 2.0. The world
grid and movement remain in 16-pixel units. Dialogue and battle use separate
canvas layers and scale from their 320×180 layout to the viewport.

## Porting direction

The port is still incomplete. Additional maps and map connections, source event
scripts, menus, party and inventory, turn-based battles, audio, saves, and the
rest of the game's flow still need native Godot implementations. The original
GBA engine is not being run inside Godot.

# emerald-godot
