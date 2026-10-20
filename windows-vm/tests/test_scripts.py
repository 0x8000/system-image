"""Tests for the pieces of the image pipeline that can fail silently.

These cover the two transformations where a mistake only shows up 30 minutes
into a Windows install: the answer file's edition/driver wiring, and the
split-and-reassemble round trip for the published disk.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
TEMPLATE = ROOT / "packer" / "answer_files" / "Autounattend.xml.tpl"


def run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [*args], capture_output=True, text=True, check=check, cwd=ROOT
    )


class AnswerFileTest(unittest.TestCase):
    def test_renders_the_selected_edition_and_every_driver(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "Autounattend.xml"
            edition = "Windows 11 Enterprise LTSC 2024 Evaluation"
            run(
                sys.executable,
                str(SCRIPTS / "render-answer.py"),
                "--template",
                str(TEMPLATE),
                "--output",
                str(output),
                "--image-name",
                edition,
            )
            text = output.read_text()
            self.assertNotIn("__IMAGE_NAME__", text)
            self.assertNotIn("__DRIVER_PATHS__", text)
            self.assertIn(f"<Value>{edition}</Value>", text)
            run(
                sys.executable,
                str(SCRIPTS / "check-answer.py"),
                "--answer",
                str(output),
                "--image-name",
                edition,
            )

    def test_rejects_an_edition_that_is_not_in_the_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "Autounattend.xml"
            run(
                sys.executable,
                str(SCRIPTS / "render-answer.py"),
                "--template",
                str(TEMPLATE),
                "--output",
                str(output),
            )
            result = run(
                sys.executable,
                str(SCRIPTS / "check-answer.py"),
                "--answer",
                str(output),
                "--image-name",
                "Windows 99 Imaginary",
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("not selected", result.stderr)

    def test_driver_paths_survive_a_missing_drive_letter(self) -> None:
        # Setup ignores paths whose media is not mounted, so the answer file
        # has to list several candidates rather than one guessed letter.
        rendered = run(
            sys.executable,
            str(SCRIPTS / "render-answer.py"),
            "--template",
            str(TEMPLATE),
            "--output",
            "/dev/stdout",
        ).stdout
        for drive in ("D:", "E:", "F:", "G:", "H:"):
            self.assertIn(f"{drive}\\drivers\\viostor\\w11\\amd64", rendered)


class OciContextTest(unittest.TestCase):
    def test_split_and_reassemble_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            disk = work / "disk.qcow2"
            disk.write_bytes(bytes(range(256)) * 1024 * 40)
            context = work / "ctx"
            run(
                str(SCRIPTS / "make-oci-context.sh"),
                "--disk",
                str(disk),
                "--output-dir",
                str(context),
                "--part-size",
                "512K",
            )

            manifest = json.loads((context / "manifest.json").read_text())
            parts = sorted((context / "parts").glob("disk.qcow2.part-*"))
            self.assertEqual(manifest["parts"], len(parts))
            self.assertGreater(len(parts), 1)

            dockerfile = (context / "Dockerfile").read_text()
            self.assertTrue(dockerfile.startswith("FROM scratch"))
            self.assertEqual(dockerfile.count("ADD parts/"), len(parts))
            # A manifest-only command keeps `docker create` happy.
            self.assertIn("CMD", dockerfile)

            joined = work / "joined.qcow2"
            joined.write_bytes(b"".join(part.read_bytes() for part in parts))
            self.assertEqual(joined.read_bytes(), disk.read_bytes())

    def test_rejects_a_context_without_a_disk(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = run(
                str(SCRIPTS / "make-oci-context.sh"),
                "--disk",
                str(Path(directory) / "missing.qcow2"),
                "--output-dir",
                str(Path(directory) / "ctx"),
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
