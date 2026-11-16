import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class PackageTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
