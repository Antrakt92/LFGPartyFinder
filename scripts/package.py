"""Build and verify the installable LFG Party Finder ZIP."""

import argparse
from io import BytesIO
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
ADDON = "PartyFinderForever"
TOC = f"{ADDON}.toc"
RUNTIME = ("Data.lua", "Finder.lua", "Window.lua")
FILES = (TOC, *RUNTIME, "CHANGELOG.md", "LICENSE")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "dist")
    args = parser.parse_args()

    toc = (ROOT / TOC).read_text(encoding="utf-8")
    version = re.search(r"^## Version: (\d+\.\d+\.\d+)$", toc, re.MULTILINE)
    if not version or "## Interface: 16001" not in toc.splitlines():
        parser.error("TOC must declare the release version and Forever interface")
    entries = (line.strip() for line in toc.splitlines())
    if tuple(entry for entry in entries if entry and not entry.startswith("#")) != RUNTIME:
        parser.error("TOC file inventory or load order does not match the package")
    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    heading = next((line for line in changelog.splitlines() if line.startswith("## ")), "")
    if not heading.startswith(f"## {version[1]} - "):
        parser.error("latest changelog version must match the TOC")

    args.out.mkdir(parents=True, exist_ok=True)
    archive = args.out / f"LFGPartyFinder-{version[1]}.zip"
    payload = {f"{ADDON}/{name}": (ROOT / name).read_bytes() for name in FILES}
    output = BytesIO()
    with ZipFile(output, "w") as zipped:
        for name, data in payload.items():
            zipped.writestr(ZipInfo(name), data, compress_type=ZIP_DEFLATED, compresslevel=9)
    with ZipFile(output) as zipped:
        if zipped.namelist() != list(payload) or any(zipped.read(name) != data for name, data in payload.items()):
            raise RuntimeError("archive does not match the source inventory")
    contents = output.getvalue()
    try:
        with archive.open("xb") as destination:
            destination.write(contents)
    except FileExistsError:
        if archive.read_bytes() != contents:
            parser.error(f"{archive} already exists with different contents. Use a separate --out directory.")
    print(archive)


if __name__ == "__main__":
    main()
