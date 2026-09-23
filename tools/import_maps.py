#!/usr/bin/env python3
"""Convert Oldale Town's GBA tile data to a Godot-ready pixel map."""

from __future__ import annotations

import json
import re
import struct
import zlib
from collections import deque
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "source"
OUT = ROOT / "assets"
MAP_NAMES = ("LittlerootTown", "Route101", "OldaleTown", "Route103")
SPECIES_NAMES = ("MUDKIP", "WURMPLE", "POOCHYENA", "ZIGZAGOON", "LOTAD", "SEEDOT", "RALTS", "WINGULL")
MESSAGE_BOX_SOURCE = SOURCE / "ui" / "message_box.png"


def read_indexed_png(path: Path) -> tuple[int, int, list[int], list[int]]:
    raw = path.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a PNG: {path}")
    pos, width, height, depth, color_type, palette, alpha = 8, 0, 0, 0, 0, [], []
    compressed = bytearray()
    while pos < len(raw):
        size = struct.unpack_from(">I", raw, pos)[0]
        kind = raw[pos + 4 : pos + 8]
        data = raw[pos + 8 : pos + 8 + size]
        pos += size + 12
        if kind == b"IHDR":
            width, height, depth, color_type = struct.unpack_from(">IIBB", data)
        elif kind == b"PLTE":
            palette = list(data)
        elif kind == b"tRNS":
            alpha = list(data)
        elif kind == b"IDAT":
            compressed.extend(data)
        elif kind == b"IEND":
            break
    if depth != 4 or color_type != 3:
        raise ValueError(f"Expected 4-bit indexed PNG: {path}")
    packed_width = (width + 1) // 2
    decoded = zlib.decompress(compressed)
    rows: list[bytearray] = []
    cursor = 0
    bpp = 1
    for y in range(height):
        filt = decoded[cursor]
        scan = bytearray(decoded[cursor + 1 : cursor + 1 + packed_width])
        cursor += packed_width + 1
        prior = rows[y - 1] if y else bytearray(packed_width)
        for i in range(packed_width):
            left = scan[i - bpp] if i >= bpp else 0
            up = prior[i]
            upper_left = prior[i - bpp] if i >= bpp else 0
            if filt == 1:
                scan[i] = (scan[i] + left) & 255
            elif filt == 2:
                scan[i] = (scan[i] + up) & 255
            elif filt == 3:
                scan[i] = (scan[i] + ((left + up) // 2)) & 255
            elif filt == 4:
                p = left + up - upper_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upper_left)
                predictor = left if pa <= pb and pa <= pc else up if pb <= pc else upper_left
                scan[i] = (scan[i] + predictor) & 255
            elif filt != 0:
                raise ValueError(f"Unknown PNG filter {filt} in {path}")
        rows.append(scan)
    indices, opacity = [], []
    for row in rows:
        for x in range(width):
            byte = row[x // 2]
            index = byte >> 4 if x % 2 == 0 else byte & 15
            indices.append(index)
            opacity.append(alpha[index] if index < len(alpha) else 255)
    return width, height, indices, opacity


def read_indexed_palette(path: Path) -> list[tuple[int, int, int]]:
    """Read the embedded RGB palette from an indexed sprite sheet."""
    raw = path.read_bytes()
    pos = 8
    while pos < len(raw):
        size = struct.unpack_from(">I", raw, pos)[0]
        kind = raw[pos + 4 : pos + 8]
        data = raw[pos + 8 : pos + 8 + size]
        pos += size + 12
        if kind == b"PLTE":
            return [tuple(data[i : i + 3]) for i in range(0, len(data), 3)]
        if kind == b"IEND":
            break
    raise ValueError(f"Missing palette in indexed PNG: {path}")


def import_character_sprite(source: Path, destination: Path) -> None:
    """Convert GBA object palette index 0 into PNG transparency."""
    width, height, indices, opacity = read_indexed_png(source)
    palette = read_indexed_palette(source)
    pixels = bytearray(width * height * 4)
    for i, palette_index in enumerate(indices):
        if palette_index == 0:
            continue  # Index 0 is transparent for GBA OBJ graphics.
        alpha = opacity[i]
        if alpha == 0:
            continue
        color = palette[palette_index]
        pixels[i * 4 : i * 4 + 4] = bytes((*color, alpha))
    write_png(destination, width, height, pixels)


def import_character_sprites() -> None:
    """Convert staged indexed object sheets into runtime RGBA sprites."""
    out_dir = OUT / "people"
    out_dir.mkdir(exist_ok=True)
    for source in (SOURCE / "people").glob("*.png"):
        import_character_sprite(source, out_dir / source.name)
    import_character_sprite(OUT / "brendan_walking.png", out_dir / "brendan_walking.png")


def import_message_box() -> None:
    """Rebuild Emerald's 30×6-tile field dialogue frame from its 14 source tiles."""
    width, height, indices, opacity = read_indexed_png(MESSAGE_BOX_SOURCE)
    palette = read_indexed_palette(MESSAGE_BOX_SOURCE)
    if (width, height) != (56, 16):
        raise ValueError(f"Expected a 56×16 dialogue tile sheet, got {width}×{height}")

    # menu.c's WindowFunc_DrawDialogueFrame draws the frame around a 27×4-tile
    # message window at tilemap (2, 15), yielding a 30×6-tile screen-wide box.
    frame_width, frame_height = 30 * 8, 6 * 8
    pixels = bytearray(frame_width * frame_height * 4)
    # The window pixel buffer fills only the 27×4-tile interior. Keep the
    # surrounding frame transparent so it composites over the field correctly.
    for y in range(8, 40):
        for x in range(16, 232):
            i = (y * frame_width + x) * 4
            pixels[i : i + 4] = bytes((*palette[1], 255))

    def blit_tile(tile_id: int, tile_x: int, tile_y: int, flip_y: bool = False) -> None:
        source_x, source_y = (tile_id % 7) * 8, (tile_id // 7) * 8
        for dy in range(8):
            sy = source_y + (7 - dy if flip_y else dy)
            for dx in range(8):
                si = sy * width + source_x + dx
                color_index = indices[si]
                if color_index == 0 or opacity[si] == 0:
                    continue
                color = palette[color_index]
                di = ((tile_y * 8 + dy) * frame_width + tile_x * 8 + dx) * 4
                pixels[di : di + 4] = bytes((*color, 255))

    # The tile numbers and repeated spans match menu.c exactly. Tile 0 is the
    # transparent/background palette entry and leaves the white window intact.
    for x, tile in ((0, 1), (1, 3), (28, 5), (29, 6)):
        blit_tile(tile, x, 0)
    for x in range(2, 28):
        blit_tile(4, x, 0)
    for y in range(1, 6):
        blit_tile(7, 0, y)
        for x in range(1, 29):
            blit_tile(9, x, y)
        blit_tile(10, 29, y)
    for x, tile in ((0, 1), (1, 3), (28, 5), (29, 6)):
        blit_tile(tile, x, 5, flip_y=True)
    for x in range(2, 28):
        blit_tile(4, x, 5, flip_y=True)

    output = OUT / "ui" / "field_message_box.png"
    output.parent.mkdir(exist_ok=True)
    write_png(output, frame_width, frame_height, pixels)


def read_tileset(folder: Path) -> dict:
    image = read_indexed_png(folder / "tiles.png")
    palettes = []
    for i in range(16):
        rows = (folder / "palettes" / f"{i:02}.pal").read_text().splitlines()[3:]
        palettes.append([tuple(map(int, line.split())) for line in rows if line.strip()])
        if len(palettes[-1]) != 16:
            raise ValueError(f"Expected 16 colors in palette {i} under {folder}")
    return {
        "image": image,
        "metatiles": (folder / "metatiles.bin").read_bytes(),
        "attributes": (folder / "metatile_attributes.bin").read_bytes(),
        "palettes": palettes,
    }


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def write_png(path: Path, width: int, height: int, pixels: bytearray) -> None:
    rows = b"".join(b"\0" + pixels[y * width * 4 : (y + 1) * width * 4] for y in range(height))
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(rows, 9))
        + png_chunk(b"IEND", b"")
    )


def read_rgba_png(path: Path) -> tuple[int, int, bytes]:
    """Read one of this importer’s unfiltered RGBA map textures."""
    raw = path.read_bytes()
    pos, width, height, compressed = 8, 0, 0, bytearray()
    while pos < len(raw):
        size = struct.unpack_from(">I", raw, pos)[0]
        kind = raw[pos + 4 : pos + 8]
        data = raw[pos + 8 : pos + 8 + size]
        pos += size + 12
        if kind == b"IHDR":
            width, height, depth, color_type = struct.unpack_from(">IIBB", data)
            if depth != 8 or color_type != 6:
                raise ValueError(f"Expected RGBA map texture: {path}")
        elif kind == b"IDAT":
            compressed.extend(data)
        elif kind == b"IEND":
            break
    decoded = zlib.decompress(compressed)
    stride = width * 4
    pixels = bytearray(width * height * 4)
    for y in range(height):
        row_start = y * (stride + 1)
        if decoded[row_start] != 0:
            raise ValueError(f"Expected unfiltered RGBA map texture: {path}")
        pixels[y * stride : (y + 1) * stride] = decoded[row_start + 1 : row_start + 1 + stride]
    return width, height, bytes(pixels)


def render_metatile_layer(
    map_name: str, start_x: int, start_y: int, cells_wide: int, cells_high: int,
    layer: int, primary: dict, secondary: dict,
) -> tuple[int, int, bytearray]:
    """Render one layer of source map metatiles, retaining transparent pixels."""
    map_data = json.loads((SOURCE / "maps" / map_name / "map.json").read_text())
    layout = next(item for item in json.loads((SOURCE / "maps" / "layouts.json").read_text())["layouts"] if item["id"] == map_data["layout"])
    map_width = int(layout["width"])
    blocks = (SOURCE / "maps" / map_name / "map.bin").read_bytes()
    width, height = cells_wide * 16, cells_high * 16
    pixels = bytearray(width * height * 4)
    for cell_y in range(cells_high):
        for cell_x in range(cells_wide):
            source_cell = (start_y + cell_y) * map_width + start_x + cell_x
            block = struct.unpack_from("<H", blocks, source_cell * 2)[0]
            meta_id = block & 0x3FF
            metatiles = primary if meta_id < 512 else secondary
            local_meta = meta_id if meta_id < 512 else meta_id - 512
            meta_offset = local_meta * 16
            for quadrant in range(4):
                data = struct.unpack_from("<H", metatiles["metatiles"], meta_offset + (layer * 4 + quadrant) * 2)[0]
                tile_id, palette_id = data & 0x3FF, data >> 12
                if tile_id == 0:
                    continue
                sheet = primary if tile_id < 512 else secondary
                local_tile = tile_id if tile_id < 512 else tile_id - 512
                tw, th, indices, opacity = sheet["image"]
                if local_tile * 64 >= tw * th:
                    continue
                tile_x, tile_y = (local_tile % 16) * 8, (local_tile // 16) * 8
                origin_x = cell_x * 16 + (quadrant % 2) * 8
                origin_y = cell_y * 16 + (quadrant // 2) * 8
                palette = sheet["palettes"][palette_id]
                for y in range(8):
                    for x in range(8):
                        src = (tile_y + y) * tw + tile_x + x
                        alpha = opacity[src]
                        if not alpha or indices[src] == 0:
                            continue
                        color = palette[indices[src]]
                        dx = 7 - x if data & 0x400 else x
                        dy = 7 - y if data & 0x800 else y
                        dst = ((origin_y + dy) * width + origin_x + dx) * 4
                        pixels[dst : dst + 4] = bytes((*color, alpha))
    return width, height, pixels


def import_forest_border(primary: dict, secondary: dict) -> None:
    """Build ground and transparent tree layers from catalogued source art."""
    resources = json.loads((OUT / "built_resources.json").read_text())
    tree = resources["tree"]
    ground = resources["ground"]
    world_width, world_height, map_x, map_width, map_top = 110, 82, 30, 20, 22
    tile_size = 16
    width = world_width * tile_size
    ground_height = world_height * tile_size
    tree_height_world = (world_height - map_top) * tile_size
    ground_x, ground_y = ground["source_cell"]
    _, _, ground_tile = render_metatile_layer(
        ground["source_map"], ground_x, ground_y, 1, 1, 0, primary, secondary
    )
    ground_pixels = bytearray(width * ground_height * 4)
    for y in range(ground_height):
        for x in range(width):
            src = ((y % tile_size) * tile_size + x % tile_size) * 4
            dst = (y * width + x) * 4
            ground_pixels[dst : dst + 4] = ground_tile[src : src + 4]
    write_png(OUT / "maps" / "ForestGround.png", width, ground_height, ground_pixels)

    tree_x, tree_y = tree["source_cell"]
    tree_w, tree_h = tree["size_cells"]
    tree_width, tree_height, tree_pixels = render_metatile_layer(
        tree["source_map"], tree_x, tree_y, tree_w, tree_h, tree["layer"], primary, secondary
    )
    ground_colors = {
        tuple(ground_tile[offset : offset + 3])
        for offset in range(0, len(ground_tile), 4)
    }
    ground_colors.update(tuple(color) for color in tree.get("background_colors", []))
    # Map metatiles are opaque RGB art. Make only the connected ground palette
    # around the tree transparent, preserving similarly colored pixels inside it.
    background = bytearray(tree_width * tree_height)
    queue: deque[int] = deque()
    for x in range(tree_width):
        queue.extend((x, (tree_height - 1) * tree_width + x))
    for y in range(1, tree_height - 1):
        queue.extend((y * tree_width, y * tree_width + tree_width - 1))
    while queue:
        pixel = queue.popleft()
        if background[pixel]:
            continue
        offset = pixel * 4
        if tuple(tree_pixels[offset : offset + 3]) not in ground_colors:
            continue
        background[pixel] = 1
        tree_pixels[offset + 3] = 0
        x, y = pixel % tree_width, pixel // tree_width
        if x > 0:
            queue.append(pixel - 1)
        if x + 1 < tree_width:
            queue.append(pixel + 1)
        if y > 0:
            queue.append(pixel - tree_width)
        if y + 1 < tree_height:
            queue.append(pixel + tree_width)
    tree_step_x, tree_step_y = tree["spacing_cells"]
    overlay = bytearray(width * tree_height_world * 4)
    for cell_y in range(0, world_height - map_top, tree_step_y):
        y = cell_y * tile_size
        for cell_x in list(range(0, map_x, tree_step_x)) + list(range(map_x + map_width, world_width, tree_step_x)):
            x = cell_x * tile_size
            for py in range(tree_height):
                if y + py >= tree_height_world:
                    break
                for px in range(tree_width):
                    if x + px >= width:
                        break
                    src = (py * tree_width + px) * 4
                    dst = ((y + py) * width + x + px) * 4
                    if tree_pixels[src + 3]:
                        overlay[dst : dst + 4] = tree_pixels[src : src + 4]
    write_png(OUT / "maps" / "ForestTrees.png", width, tree_height_world, overlay)


def first_script_text(source: str, script_label: str) -> str:
    script = re.search(rf"(?m)^{re.escape(script_label)}::\s*$", source)
    if not script:
        return ""
    following = re.search(r"(?m)^[A-Za-z0-9_]+::\s*$", source[script.end() :])
    block = source[script.end() : script.end() + following.start()] if following else source[script.end() :]
    message = re.search(r"\bmsgbox\s+([A-Za-z0-9_]+)", block)
    if not message:
        return ""
    label = re.search(rf"(?m)^{re.escape(message.group(1))}:\s*$", source)
    if not label:
        return ""
    text_tail = source[label.end() :]
    next_label = re.search(r"(?m)^[A-Za-z0-9_]+(?:::|:)\s*$", text_tail)
    text_block = text_tail[: next_label.start()] if next_label else text_tail
    pieces = re.findall(r'\.string\s+"((?:[^"\\]|\\.)*)"', text_block)
    text = "".join(pieces).replace(r"\p", "\n\n").replace(r"\n", "\n").replace(r"\l", "\n")
    text = text.replace(r"\x", "")
    return text.rstrip("$").replace("$", "")


def import_map(name: str, layouts: list[dict], primary: dict, secondary: dict, wild_data: dict) -> None:
    map_data = json.loads((SOURCE / "maps" / name / "map.json").read_text())
    script_file = SOURCE / "maps" / name / "scripts.inc"
    scripts = script_file.read_text() if script_file.exists() else ""
    layout = next(entry for entry in layouts if entry["id"] == map_data["layout"])
    width, height = layout["width"], layout["height"]
    blocks = (SOURCE / "maps" / name / "map.bin").read_bytes()
    if len(blocks) != width * height * 2:
        raise ValueError(f"{name} block map size does not match layouts.json")
    out_w, out_h = width * 16, height * 16
    layer_pixels = [bytearray(out_w * out_h * 4), bytearray(out_w * out_h * 4)]
    collision = []
    terrain = []

    for cell in range(width * height):
        block = struct.unpack_from("<H", blocks, cell * 2)[0]
        meta_id = block & 0x3FF
        tileset = primary if meta_id < 512 else secondary
        local_meta = meta_id if meta_id < 512 else meta_id - 512
        meta_offset = local_meta * 16
        map_x, map_y = (cell % width) * 16, (cell // width) * 16
        attrs = struct.unpack_from("<H", tileset["attributes"], local_meta * 2)[0]
        layer_type = (attrs >> 12) & 15
        for layer in range(2):
            for quadrant in range(4):
                data = struct.unpack_from("<H", tileset["metatiles"], meta_offset + (layer * 4 + quadrant) * 2)[0]
                tile_id, palette_id = data & 0x3FF, data >> 12
                if tile_id == 0:
                    continue
                hflip, vflip = bool(data & 0x400), bool(data & 0x800)
                sheet = primary if tile_id < 512 else secondary
                local_tile = tile_id if tile_id < 512 else tile_id - 512
                tw, th, indices, opacity = sheet["image"]
                if local_tile * 64 >= tw * th:
                    continue  # Dynamically loaded/animated sheets are imported separately.
                tile_x, tile_y = (local_tile % 16) * 8, (local_tile // 16) * 8
                origin_x, origin_y = map_x + (quadrant % 2) * 8, map_y + (quadrant // 2) * 8
                palette = sheet["palettes"][palette_id]
                for y in range(8):
                    for x in range(8):
                        src = (tile_y + y) * tw + tile_x + x
                        alpha = opacity[src]
                        if not alpha or indices[src] == 0:
                            continue
                        color = palette[indices[src]]
                        dx, dy = (7 - x if hflip else x), (7 - y if vflip else y)
                        dst = ((origin_y + dy) * out_w + origin_x + dx) * 4
                        # Emerald uses COVERED metatiles' upper art below
                        # sprites. NORMAL and SPLIT upper art is above sprites.
                        target_layer = 0 if layer == 1 and layer_type == 1 else layer
                        layer_pixels[target_layer][dst : dst + 4] = bytes((*color, alpha))

        behavior = attrs & 255
        map_collision = (block >> 10) & 3
        collision.append(int(map_collision != 0 or behavior == 1 or 18 <= behavior <= 25 or 48 <= behavior <= 55))
        terrain.append(behavior)

    resource_data = json.loads((OUT / "built_resources.json").read_text())
    for x, y, cells_wide, cells_high in resource_data.get("house_collision_overrides", {}).get(name, []):
        for cell_y in range(y, y + cells_high):
            for cell_x in range(x, x + cells_wide):
                if 0 <= cell_x < width and 0 <= cell_y < height:
                    collision[cell_y * width + cell_x] = 1

    out_dir = OUT / "maps"
    out_dir.mkdir(exist_ok=True)
    # Layer 0 includes COVERED upper art; layer 1 contains NORMAL/SPLIT art
    # that Emerald draws above object sprites.
    write_png(out_dir / f"{name}_Layer0.png", out_w, out_h, layer_pixels[0])
    write_png(out_dir / f"{name}_Layer1.png", out_w, out_h, layer_pixels[1])
    events = map_data.get("object_events", [])
    for event in events:
        event["dialogue"] = first_script_text(scripts, event.get("script", "")) or event.get("dialogue", "")
    bg_events = map_data.get("bg_events", [])
    for event in bg_events:
        event["dialogue"] = first_script_text(scripts, event.get("script", ""))
        if not event["dialogue"] and event.get("script") == "Common_EventScript_ShowPokemonCenterSign":
            event["dialogue"] = "POKéMON CENTER\nHeal your tired, hurt, or fainted POKéMON."
        elif not event["dialogue"] and event.get("script") == "Common_EventScript_ShowPokemartSign":
            event["dialogue"] = "POKéMON MART\nA convenient shop for all your POKéMON needs."
    rates = next(field["encounter_rates"] for field in wild_data["wild_encounter_groups"][0]["fields"] if field["type"] == "land_mons")
    wild_entry = next((entry for group in wild_data["wild_encounter_groups"] if group.get("for_maps") for entry in group.get("encounters", []) if entry["map"] == "MAP_" + name.upper()), None)
    land = wild_entry.get("land_mons", {}) if wild_entry else {}
    wild_mons = []
    for i, mon in enumerate(land.get("mons", [])):
        wild_mons.append({
            "species": mon["species"].removeprefix("SPECIES_").lower(),
            "min_level": mon["min_level"],
            "max_level": mon["max_level"],
            "weight": rates[i] if i < len(rates) else 1,
        })
    result = {
        "name": name,
        "width": width,
        "height": height,
        "tile_size": 16,
        "collision": collision,
        "terrain": terrain,
        "object_events": events,
        "bg_events": bg_events,
        "connections": map_data.get("connections", []),
        "wild_encounter_rate": land.get("encounter_rate", 0),
        "wild_mons": wild_mons,
    }
    (out_dir / f"{name}.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"Imported {name}: {width} × {height} tiles, {len(result['object_events'])} object events.")


def main() -> None:
    layouts = json.loads((SOURCE / "maps" / "layouts.json").read_text())["layouts"]
    wild_data = json.loads((SOURCE / "wild_encounters.json").read_text())
    primary = read_tileset(SOURCE / "primary_general")
    secondary = read_tileset(SOURCE / "secondary_petalburg")
    for name in MAP_NAMES:
        import_map(name, layouts, primary, secondary, wild_data)
    import_forest_border(primary, secondary)
    import_character_sprites()
    import_message_box()
    import_pokemon()


def import_pokemon() -> None:
    species_source = (SOURCE / "pokemon" / "species_info.h").read_text()
    stats = {}
    for species in SPECIES_NAMES:
        key = species.lower()
        folder = SOURCE / "pokemon" / key
        palette_lines = (folder / "normal.pal").read_text().splitlines()[3:]
        palette = [tuple(map(int, line.split())) for line in palette_lines if line.strip()]
        for pose in ("front", "back"):
            width, height, indices, opacity = read_indexed_png(folder / f"{pose}.png")
            pixels = bytearray(width * height * 4)
            for index, color_index in enumerate(indices):
                alpha = opacity[index]
                if alpha:
                    dst = index * 4
                    pixels[dst : dst + 4] = bytes((*palette[color_index], alpha))
            write_png(OUT / "pokemon" / f"{key}_{pose}.png", width, height, pixels)
        match = re.search(rf"(?m)^\s*\[SPECIES_{species}\]\s*=\s*\{{", species_source)
        if not match:
            raise ValueError(f"Could not find base stats for {species}")
        tail = species_source[match.end() :]
        next_species = re.search(r"(?m)^\s*\[SPECIES_", tail)
        block = tail[: next_species.start()] if next_species else tail
        fields = {}
        for source_key, key_name in (("baseHP", "hp"), ("baseAttack", "attack"), ("baseDefense", "defense"), ("baseSpeed", "speed")):
            value = re.search(rf"\.({source_key})\s*=\s*(\d+)", block)
            fields[key_name] = int(value.group(2)) if value else 40
        stats[key] = fields
    (OUT / "pokemon" / "base_stats.json").write_text(json.dumps(stats, indent=2) + "\n")


if __name__ == "__main__":
    main()
