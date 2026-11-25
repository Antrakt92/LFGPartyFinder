import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from io import BytesIO, StringIO
from pathlib import Path
from unittest.mock import patch
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]


class PackageTests(unittest.TestCase):
    def assert_rejects_package(self, change, message):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "scripts").mkdir()
            for name in ("PartyFinderForever.toc", "Data.lua", "Finder.lua", "Window.lua", "LICENSE",
                         "CHANGELOG.md", "scripts/package.py"):
                shutil.copyfile(ROOT / name, source / name)
            args = change(source) or []
            result = subprocess.run([sys.executable, str(source / "scripts/package.py"), *args], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, result.stderr)
            self.assertFalse(list(source.glob("dist/*.zip")))

    def assert_rejects_toc(self, extra, message):
        def append_toc(source):
            with (source / "PartyFinderForever.toc").open("a", encoding="utf-8") as toc:
                toc.write(extra)

        self.assert_rejects_package(append_toc, message)

    def test_rejects_unpackaged_toc_entry(self):
        self.assert_rejects_toc("\nExtra.xml\n", "TOC file inventory")

    def test_rejects_conflicting_toc_metadata(self):
        for extra in ("## Version: invalid", "## Version: 9.9.9", "## Interface: 99999"):
            with self.subTest(extra=extra):
                self.assert_rejects_toc(f"\n{extra}\n", "TOC must declare")

    def test_rejects_zero_padded_version_even_when_changelog_agrees(self):
        def set_version(source):
            toc = source / "PartyFinderForever.toc"
            contents = toc.read_text(encoding="utf-8")
            version = re.search(r"^## Version: (\S+)$", contents, re.MULTILINE)[1]
            toc.write_text(contents.replace(f"## Version: {version}", f"## Version: 0{version}"), encoding="utf-8")
            changelog = source / "CHANGELOG.md"
            contents = changelog.read_text(encoding="utf-8")
            changelog.write_text(contents.replace(f"## {version} - ", f"## 0{version} - ", 1), encoding="utf-8")

        self.assert_rejects_package(set_version, "TOC must declare")

    def test_rejects_truncated_release_history(self):
        def truncate_history(source):
            changelog = source / "CHANGELOG.md"
            sections = re.split(r"(?m)(?=^## )", changelog.read_text(encoding="utf-8"))
            previous = source / "previous.md"
            previous.write_text(sections[0] + "".join(sections[2:]), encoding="utf-8")
            changelog.write_text("".join(sections[:-1]), encoding="utf-8")
            return ["--previous-changelog", str(previous)]

        self.assert_rejects_package(truncate_history, "must retain the previous release history")

    def test_rejects_duplicate_release_heading_even_with_full_history(self):
        def duplicate_release(source):
            changelog = source / "CHANGELOG.md"
            contents = changelog.read_text(encoding="utf-8")
            previous = source / "previous.md"
            previous.write_text(contents, encoding="utf-8")
            first_release = contents.index("## ")
            duplicate = contents[:contents.index("\n", first_release)] + "\n\n"
            changelog.write_text(duplicate + contents[first_release:], encoding="utf-8")
            return ["--previous-changelog", str(previous)]

        self.assert_rejects_package(duplicate_release, "duplicate release version")

    def test_archive_uses_the_metadata_bytes_that_were_validated(self):
        script = ROOT / "scripts/package.py"
        original_open = Path.open
        metadata = {ROOT / name: (ROOT / name).read_bytes() for name in ("PartyFinderForever.toc", "CHANGELOG.md")}
        opened = set()

        def changing_metadata(path, mode="r", *args, **kwargs):
            if path not in metadata:
                return original_open(path, mode, *args, **kwargs)
            data = b"Changed after validation\n" if path in opened else metadata[path]
            opened.add(path)
            return BytesIO(data) if mode == "rb" else StringIO(data.decode("utf-8"))

        with tempfile.TemporaryDirectory() as directory:
            with patch.object(sys, "argv", [str(script), "--out", directory]), patch.object(Path, "open", changing_metadata):
                runpy.run_path(str(script), run_name="__main__")
            archive, = Path(directory).glob("*.zip")
            with ZipFile(archive) as zipped:
                for path, expected in metadata.items():
                    self.assertEqual(zipped.read(f"PartyFinderForever/{path.name}"), expected)

    def test_preserves_existing_versioned_archive(self):
        toc = (ROOT / "PartyFinderForever.toc").read_text(encoding="utf-8")
        version = re.search(r"^## Version: (\S+)$", toc, re.MULTILINE)[1]
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / f"LFGPartyFinder-{version}.zip"
            command = [sys.executable, str(ROOT / "scripts/package.py"), "--out", directory]
            subprocess.run(command, check=True, capture_output=True)
            first_build = archive.read_bytes()

            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(archive.read_bytes(), first_build)

            existing_archive = first_build + b"retained build marker"
            archive.write_bytes(existing_archive)
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(archive.read_bytes(), existing_archive)

    def test_publishes_archive_only_after_write_finishes(self):
        script = ROOT / "scripts/package.py"
        original_open = Path.open

        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            observed = []

            class ObservedDestination:
                def __init__(self, stream):
                    self.stream = stream

                def __enter__(self):
                    self.stream.__enter__()
                    return self

                def __exit__(self, *args):
                    return self.stream.__exit__(*args)

                def write(self, data):
                    self.stream.write(data[:64])
                    self.stream.flush()
                    observed.append(list(out.glob("*.zip")))
                    self.stream.write(data[64:])

            def observe_write(path, mode="r", *args, **kwargs):
                stream = original_open(path, mode, *args, **kwargs)
                return ObservedDestination(stream) if mode == "xb" else stream

            with patch.object(sys, "argv", [str(script), "--out", directory]), patch.object(Path, "open", observe_write):
                runpy.run_path(str(script), run_name="__main__")

            self.assertEqual(observed, [[]], "the final path must stay absent during partial writes")
            archive, = out.iterdir()
            with ZipFile(archive) as packaged:
                self.assertIsNone(packaged.testzip())

    def test_failed_write_does_not_block_retry(self):
        script = ROOT / "scripts/package.py"
        original_open = Path.open

        class FailingDestination:
            def __init__(self, stream):
                self.stream = stream

            def __enter__(self):
                self.stream.__enter__()
                return self

            def __exit__(self, *args):
                return self.stream.__exit__(*args)

            def write(self, data):
                self.stream.write(data[:64])
                raise OSError("simulated write failure")

        def fail_archive_write(path, mode="r", *args, **kwargs):
            stream = original_open(path, mode, *args, **kwargs)
            return FailingDestination(stream) if mode == "xb" else stream

        with tempfile.TemporaryDirectory() as directory:
            with patch.object(sys, "argv", [str(script), "--out", directory]), patch.object(Path, "open", fail_archive_write):
                with self.assertRaisesRegex(OSError, "simulated write failure"):
                    runpy.run_path(str(script), run_name="__main__")
            self.assertFalse(list(Path(directory).glob("*.zip")))
            subprocess.run([sys.executable, str(script), "--out", directory], check=True, capture_output=True)
            self.assertEqual(len(list(Path(directory).glob("*.zip"))), 1)


if __name__ == "__main__":
    unittest.main()
