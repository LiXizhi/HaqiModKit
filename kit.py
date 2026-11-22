"""Create and package a local Haqi mod. Python 3, standard library only."""

import argparse
import json
import hashlib
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
        (dest / "mod.json").write_text(
            json.dumps(
                {"id": args.name, "name": args.name, "version": "1.0.0"}, indent=2
            )
            + "\n",
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
        manifest = src / "mod.json"
        meta = (
            json.loads(manifest.read_text(encoding="utf-8"))
            if manifest.exists()
            else None
        )
        if meta is not None:
            if (
                not isinstance(meta, dict)
                or meta.get("id") != src.name
                or not re.fullmatch(
                    r"\d{1,7}\.\d{1,7}\.\d{1,7}", str(meta.get("version", ""))
                )
            ):
                parser.error(
                    "mod.json requires the matching id and a numeric major.minor.patch version"
                )
            feed = meta.get("feed")
            if feed and (
                not isinstance(feed, str)
                or not re.fullmatch(
                    r"https://[\w.\-]+/[\w./~\-]*" + re.escape(src.name) + r"\.json",
                    feed,
                    re.ASCII,
                )
                or ".." in feed
                or feed.rsplit("/", 1)[-1] != src.name + ".json"
            ):
                parser.error("feed must be an HTTPS URL ending in /<mod id>.json")
            if (
                not isinstance(meta.get("name"), str)
                or not 0 < len(meta["name"].encode()) <= 80
                or any(ord(c) < 32 for c in meta["name"])
            ):
                parser.error("name must be 1–80 UTF-8 bytes on a single line")
            comment = json.dumps(
                {k: meta[k] for k in ("id", "name", "version", "feed") if k in meta},
                ensure_ascii=False,
            ).encode()
            if len(comment) > 4096 or (feed and len(feed) > 512):
                parser.error("Mod metadata is too large")
            if feed and archive.with_suffix(".json").exists():
                parser.error("Update descriptor already exists")
        with ZipFile(archive, "x", ZIP_DEFLATED) as z:
            if meta is not None:
                z.comment = comment
            for entry in sorted(src.rglob("*")):
                if (
                    entry.is_file()
                    and not entry.is_symlink()
                    and not any(p.startswith(".") for p in entry.relative_to(src).parts)
                ):
                    z.write(entry, entry.relative_to(args.project).as_posix())
        if meta and meta.get("feed"):
            data = {
                "id": src.name,
                "version": meta["version"],
                "sha1": hashlib.sha1(archive.read_bytes()).hexdigest(),
            }
            archive.with_suffix(".json").write_text(
                json.dumps(data, indent=2) + "\n", encoding="utf-8"
            )
        print(archive)


if __name__ == "__main__":
    main()
