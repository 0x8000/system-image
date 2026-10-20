#!/usr/bin/env python3
"""Render the unattended answer file for one verified ISO.

The edition name is part of the answer file, and a wrong one turns into setup's
unhelpful "no images are available". The caller passes the name it read out of
the ISO's install image, so the rendered file cannot disagree with the media.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# virtio-win keys Windows 11 as `w11`. The second CD-ROM's drive letter is not
# stable across machines, so every plausible one is listed; setup ignores the
# paths whose media is not mounted.
DRIVES = ("D", "E", "F", "G", "H")
DRIVER_DIRS = ("viostor", "vioscsi", "NetKvm", "Balloon", "vioserial", "qxldod")
WINDOWS_DIR = "w11"


def driver_paths() -> str:
    entries: list[str] = []
    for order, (drive, directory) in enumerate(
        ((drive, directory) for drive in DRIVES for directory in DRIVER_DIRS),
        start=1,
    ):
        entries.append(
            "        <PathAndCredentials wcm:action=\"add\" "
            f'wcm:keyValue="{order}">\n'
            f"          <Path>{drive}:\\drivers\\{directory}\\{WINDOWS_DIR}\\amd64</Path>\n"
            "        </PathAndCredentials>"
        )
    return "\n".join(entries)


def render(template: str, image_name: str) -> str:
    for placeholder in ("__IMAGE_NAME__", "__DRIVER_PATHS__"):
        if placeholder not in template:
            raise ValueError(f"the answer template has no {placeholder}")
    return (
        template.replace("__IMAGE_NAME__", image_name)
        .replace("__DRIVER_PATHS__", driver_paths())
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--image-name",
        default="Windows 11 Enterprise LTSC 2024 Evaluation",
    )
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(args.template.read_text(), args.image_name))
    print(f"rendered {args.output} for {args.image_name!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
