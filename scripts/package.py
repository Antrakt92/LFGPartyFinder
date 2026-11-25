"""Build and verify the installable LFG Party Finder ZIP."""

import argparse
from io import BytesIO
import os
import re
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
ADDON = "PartyFinderForever"
TOC = f"{ADDON}.toc"
RUNTIME = ("Data.lua", "Finder.lua", "Window.lua")
FILES = (TOC, *RUNTIME, "CHANGELOG.md", "LICENSE")
VERSION = r"(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){2}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "dist")
    parser.add_argument("--previous-changelog", type=Path, help="changelog from the previous release tag")
    args = parser.parse_args()

    payload = {name: (ROOT / name).read_bytes() for name in FILES}
    toc_lines = payload[TOC].decode("utf-8").splitlines()
    versions = []
    interfaces = []
    for line in toc_lines:
        header = re.fullmatch(r"\s*##\s*(Version|Interface)\s*:\s*(.*?)\s*", line, re.IGNORECASE | re.ASCII)
        if header:
            values = versions if header[1].lower() == "version" else interfaces
            values.append(header[2])
    if (
        interfaces != ["16001"]
        or len(versions) != 1
        or not re.fullmatch(VERSION, versions[0])
    ):
        parser.error("TOC must declare exactly one release version and Forever interface")
    version = versions[0]
    entries = (line.strip() for line in toc_lines)
    if tuple(entry for entry in entries if entry and not entry.startswith("#")) != RUNTIME:
        parser.error("TOC file inventory or load order does not match the package")
    changelog = payload["CHANGELOG.md"].decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
    heading = next((line for line in changelog.splitlines() if line.startswith("## ")), "")
    if not heading.startswith(f"## {version} - "):
        parser.error("latest changelog version must match the TOC")
    history_versions = re.findall(rf"^## ({VERSION}) - ", changelog, re.MULTILINE)
    if len(history_versions) != len(set(history_versions)):
        parser.error("changelog contains a duplicate release version")
    if args.previous_changelog:
        previous = args.previous_changelog.read_text(encoding="utf-8")
        first_release = re.search(r"^## ", previous, re.MULTILINE)
        if not first_release or not changelog.rstrip().endswith(previous[first_release.start():].rstrip()):
            parser.error("changelog must retain the previous release history")

    args.out.mkdir(parents=True, exist_ok=True)
    archive = args.out / f"LFGPartyFinder-{version}.zip"
    output = BytesIO()
    with ZipFile(output, "w") as zipped:
        for name, data in payload.items():
            zipped.writestr(ZipInfo(f"{ADDON}/{name}"), data, compress_type=ZIP_DEFLATED, compresslevel=9)
    with ZipFile(output) as zipped:
        if zipped.namelist() != [f"{ADDON}/{name}" for name in payload] or any(
            zipped.read(f"{ADDON}/{name}") != data for name, data in payload.items()
        ):
            raise RuntimeError("archive does not match the source inventory")
    contents = output.getvalue()
    with TemporaryDirectory(prefix=".package-", dir=args.out) as temporary:
        staged = Path(temporary) / archive.name
        with staged.open("xb") as destination:
            destination.write(contents)
        try:
            # Publish a complete file without replacing an existing version.
            if os.name == "nt":
                staged.rename(archive)
            else:
                os.link(staged, archive)
        except FileExistsError:
            if archive.read_bytes() != contents:
                parser.error(f"{archive} already exists with different contents. Use a separate --out directory.")
    print(archive)


if __name__ == "__main__":
    main()
