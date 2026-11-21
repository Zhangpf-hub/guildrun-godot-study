"""Follow each character's authored visual-config prefab reference."""
import argparse
import json
from pathlib import Path
from contextlib import ExitStack

from import_scenes import Source, import_scene


def extract(data, game):
    with ExitStack() as stack:
        src = Source(data, stack)
        file = src.file("sharedassets1.assets")
        records = json.loads((game / "balancing/sharedassets1.json").read_text())["records"]
        index = {}
        for record in records:
            if record["type"] != "CharacterVisualConfig":
                continue
            ptr = record["fields"]["Prefab"]
            if not ptr["m_PathID"]:
                continue
            owner, root = src.resolve(file, ptr)
            name = root.read_typetree()["m_Name"]
            scene = "Assets/Characters/" + name + ".unity"
            result = import_scene(src, record["id"], scene, game, (owner, root))
            index[str(record["id"])] = "res://" + result["scene"]
        (game / "Characters/index.json").write_text(json.dumps(index, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    extract(parser.parse_args().data, Path(__file__).resolve().parents[1] / "game")
