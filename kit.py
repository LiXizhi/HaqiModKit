"""Create and package a local Haqi mod. Python 3, standard library only."""

import argparse
import re
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="action", required=True)
    create = subs.add_parser("new")
    create.add_argument("name", help="For example HaqiMoon")
    create.add_argument("directory", type=Path, help="Project directory")
    pack = subs.add_parser("pack")
    pack.add_argument(
        "project", type=Path, help="Directory containing Mod/<name>/main.lua"
    )
    pack.add_argument("--out", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.action == "new":
        if (
            not re.fullmatch(r"Haqi[A-Za-z0-9_]+", args.name)
            or args.name == "HaqiWardrobe"
        ):
            parser.error("Choose a community name starting with Haqi, e.g. HaqiMoon")
        dest = args.directory / "Mod" / args.name
        dest.mkdir(parents=True, exist_ok=False)
        template = ROOT / "example/Mod/HaqiHello/main.lua"
        (dest / "main.lua").write_text(
            template.read_text(encoding="utf-8").replace("HaqiHello", args.name),
            encoding="utf-8",
        )
        print(dest / "main.lua")
    else:
        entries = list((args.project / "Mod").glob("*/main.lua"))
        if len(entries) != 1 or not re.fullmatch(
            r"Haqi[A-Za-z0-9_]+", entries[0].parent.name
        ):
            parser.error("Expected exactly one Mod/HaqiName/main.lua")
        src = entries[0].parent
        args.out.mkdir(parents=True, exist_ok=True)
        archive = args.out / (src.name + ".zip")
        if archive.resolve().is_relative_to(src.resolve()):
            parser.error("--out must be outside the packaged source folder")
        with ZipFile(archive, "x", ZIP_DEFLATED) as z:
            for entry in sorted(src.rglob("*")):
                if (
                    entry.is_file()
                    and not entry.is_symlink()
                    and not any(p.startswith(".") for p in entry.relative_to(src).parts)
                ):
                    z.write(entry, entry.relative_to(args.project).as_posix())
        print(archive)


if __name__ == "__main__":
    main()
