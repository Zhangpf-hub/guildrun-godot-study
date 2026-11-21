"""Copy the four open Noto Sans faces from an installed local demo."""
import argparse
from contextlib import ExitStack
from pathlib import Path

from import_scenes import Source


FACES = {
    866: ("NotoSansTC-Regular", 7_109_460),
    851: ("NotoSansTC-Bold", 7_104_212),
    863: ("NotoSansSC-Regular", 10_559_284),
    870: ("NotoSansSC-Bold", 10_549_020),
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path, help="Path to Guildrun_Data")
    parser.add_argument(
        "--output", type=Path,
        default=Path(__file__).resolve().parents[1] / "game/fonts/noto",
        help="Destination for the four unmodified TTF files",
    )
    args = parser.parse_args()

    fonts = {}
    with ExitStack() as stack:
        source = Source(args.data, stack).file("resources.assets")
        for path_id, (name, expected_size) in FACES.items():
            entry = source.objects[path_id]
            if entry.type.name != "Font":
                raise ValueError(f"PathID {path_id} is not a Font")
            record = entry.read_typetree()
            data = bytes(record["m_FontData"])
            if record["m_Name"] != name or len(data) != expected_size or data[:4] != b"\x00\x01\x00\x00":
                raise ValueError(f"Unexpected font data for PathID {path_id}")
            fonts[name] = data

    args.output.mkdir(parents=True, exist_ok=True)
    for name, data in fonts.items():
        target = args.output / f"{name}.ttf"
        target.write_bytes(data)
        print(f"{target.name} {len(data):,} bytes")


if __name__ == "__main__":
    main()
