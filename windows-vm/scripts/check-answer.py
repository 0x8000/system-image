#!/usr/bin/env python3
"""Assert a rendered answer file matches the edition it was rendered for.

This is the check CI runs on every change: a placeholder left behind, a
dropped driver path, or an edition name that does not appear in the file all
turn into a setup failure 30 minutes into a Windows install otherwise.
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Every virtio driver tree the answer file must point setup at.
REQUIRED_DRIVERS = ("viostor", "vioscsi", "NetKvm")


def values(root: ET.Element, suffix: str) -> list[str]:
    return [element.text or "" for element in root.iter() if element.tag.endswith(suffix)]


def check(path: Path, image_name: str) -> list[str]:
    problems: list[str] = []
    text = path.read_text()
    for placeholder in ("__IMAGE_NAME__", "__DRIVER_PATHS__"):
        if placeholder in text:
            problems.append(f"{placeholder} was left unrendered")

    root = ET.fromstring(text)
    if image_name not in values(root, "Value"):
        problems.append(f"the edition {image_name!r} is not selected anywhere in the file")

    paths = [p for p in values(root, "Path") if p]
    for driver in REQUIRED_DRIVERS:
        if not any(driver in path for path in paths):
            problems.append(f"no driver path for {driver}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--answer", type=Path, required=True)
    parser.add_argument("--image-name", required=True)
    args = parser.parse_args()

    problems = check(args.answer, args.image_name)
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    if problems:
        return 1
    print(f"{args.answer}: ok for {args.image_name!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
