#!/usr/bin/env python3
"""Render the unattended answer file for one verified ISO.

The edition name is part of the answer file, and a wrong one turns into setup's
unhelpful "no images are available". The caller passes the name it read out of
the ISO's install image, so the rendered file cannot disagree with the media.
"""

from __future__ import annotations

import argparse
import base64
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
BOOTSTRAP = SCRIPT_DIR.parent / "packer" / "scripts" / "00-enable-winrm.ps1"

# virtio-win keys Windows 11 as `w11`. The second CD-ROM's drive letter is not
# stable across machines, so every plausible one is listed; setup ignores the
# paths whose media is not mounted.
DRIVES = ("D", "E", "F", "G", "H")
DRIVER_TREES = (
    ("viostor", "w11"),
    ("vioscsi", "w11"),
    ("NetKvm", "w11"),
    ("Balloon", "w11"),
    ("vioserial", "w11"),
    ("Balloon", "w10"),
    ("vioserial", "w10"),
)


def driver_paths() -> str:
    entries: list[str] = []
    for order, (drive, directory, tree) in enumerate(
        (
            (drive, directory, tree)
            for drive in DRIVES
            for directory, tree in DRIVER_TREES
        ),
        start=1,
    ):
        entries.append(
            "        <PathAndCredentials wcm:action=\"add\" "
            f'wcm:keyValue="{order}">\n'
            f"          <Path>{drive}:\\drivers\\{directory}\\{tree}\\amd64</Path>\n"
            "        </PathAndCredentials>"
        )
    return "\n".join(entries)


def encoded_bootstrap() -> str:
    """The WinRM bootstrap as a PowerShell -EncodedCommand payload.

    Embedding the script removes the only drive letter the answer file would
    otherwise depend on: setup reads Autounattend.xml from whichever removable
    medium it finds, so drive A is not guaranteed to be the floppy that
    carries the script.
    """
    text = BOOTSTRAP.read_text()
    return base64.b64encode(text.encode("utf-16-le")).decode()


BEGIN = "<!-- DRIVER_COMPONENT_BEGIN -->"
END = "<!-- DRIVER_COMPONENT_END -->"


def strip_driver_components(text: str) -> str:
    """Remove every block between the driver component markers.

    Dropping the component entirely is not the same as rendering it with an
    empty DriverPaths: setup still acts on a component that is present.
    """
    while BEGIN in text:
        start = text.index(BEGIN)
        stop = text.index(END, start) + len(END)
        # Also drop the line break that followed the block.
        if text[stop:stop + 1] == "\n":
            stop += 1
        text = text[:start] + text[stop:]
    return text


def render(template: str, image_name: str, *, drivers: bool) -> str:
    """Fill the template.

    A SATA disk needs no driver at all, and Windows setup fails on a driver
    path that does not exist on this machine. So the driver paths are only
    emitted when the build actually attaches a virtio disk.
    """
    for placeholder in ("__IMAGE_NAME__", "__DRIVER_PATHS__", "__WINRM_BOOTSTRAP__"):
        if placeholder not in template:
            raise ValueError(f"the answer template has no {placeholder}")
    if not drivers:
        template = strip_driver_components(template)
    return (
        template.replace("__IMAGE_NAME__", image_name)
        .replace("__DRIVER_PATHS__", driver_paths() if drivers else "")
        .replace("__WINRM_BOOTSTRAP__", encoded_bootstrap())
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--image-name",
        default="Windows 11 Enterprise LTSC 2024 Evaluation",
    )
    parser.add_argument(
        "--drivers",
        choices=("virtio", "none"),
        default="none",
        help="emit virtio driver paths; a SATA disk needs none",
    )
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        render(args.template.read_text(), args.image_name, drivers=args.drivers == "virtio")
    )
    print(f"rendered {args.output} for {args.image_name!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
