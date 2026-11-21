"""Refresh materials used by the enabled character rig renderers."""
import argparse
from contextlib import ExitStack
import json
from pathlib import Path

from import_scenes import Source, material_asset


def extract(data, game):
    rigs = json.loads((game / "Characters/rigs.json").read_text(encoding="utf8"))
    paths = {path for bindings in rigs.values() for rig in bindings for mesh in rig["meshes"].values()
             if mesh["visible"] for path in mesh["surfaces"] if path}
    with ExitStack() as stack:
        source = Source(data, stack)
        for path in sorted(paths):
            asset, identifier = Path(path).stem.rsplit("_", 1)
            file = source.file(asset + ".assets")
            material_asset(source, file, {"m_FileID": 0, "m_PathID": int(identifier)}, game, character=True)
        print(f"{len(source.shader_materials)} toon materials across {len(paths)} visible rig bindings")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    extract(args.data, Path(__file__).resolve().parents[1] / "game")
