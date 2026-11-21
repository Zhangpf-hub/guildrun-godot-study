"""Import the four placement Tile records and their two sprites from the demo's Battle scene."""
import argparse
from contextlib import ExitStack
import json
from pathlib import Path
import struct

from import_scenes import Source


TILES = {"ally": 65251, "enemy": 65252, "invalid": 65253, "open": 65254}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    game = Path(__file__).resolve().parents[1] / "game"
    styles = {}
    with ExitStack() as stack:
        source = Source(args.data, stack)
        shared = source.file("sharedassets3.assets")
        saved = set()
        for name, tile_id in TILES.items():
            raw = shared.objects[tile_id].get_raw_data()
            # Built-in Unity Tile serialization begins with the 28-byte MonoBehaviour header.
            name_size = struct.unpack_from("<I", raw, 28)[0]
            sprite_offset = (32 + name_size + 3) & ~3
            tile_name = raw[32:32 + name_size].decode()
            if not tile_name.startswith("PointyTopHex_"):
                raise ValueError(f"Unexpected tile record {tile_id}: {tile_name}")
            file_id, sprite_id, *color = struct.unpack_from("<iq4f", raw, sprite_offset)
            owner, reader = source.resolve(shared, {"m_FileID": file_id, "m_PathID": sprite_id})
            sprite = reader.read()
            texture = f"sprites/{Path(owner.name).stem}_{sprite_id}.png"
            if texture not in saved:
                sprite.image.save(game / texture)
                saved.add(texture)
            styles[name] = {"texture": "res://" + texture, "pixel_size": 1 / sprite.m_PixelsToUnits,
                            "color": color, "unity_tile": tile_id}
    path = game / "balancing/deployment_grid.json"
    path.write_text(json.dumps(styles, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
