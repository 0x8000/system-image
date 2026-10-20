#!/usr/bin/env python3
"""Periodically capture the guest's screen over the QEMU monitor.

A Windows install that never reaches WinRM gives no other signal: Packer only
reports that the connection timed out, with no indication of whether setup is
waiting on a dialog, still copying files, or sitting at an error. QEMU's
HMP monitor can take a screendump from a running domain, so a watcher runs
alongside the build and leaves a timeline of images behind.
"""

from __future__ import annotations

import argparse
import socket
import subprocess
import time
from pathlib import Path


def send(connection: socket.socket, command: str) -> str:
    connection.sendall((command + "\n").encode())
    time.sleep(0.5)
    chunks: list[bytes] = []
    connection.settimeout(2.0)
    try:
        while True:
            data = connection.recv(65536)
            if not data:
                break
            chunks.append(data)
            if b"(qemu)" in data:
                break
    except socket.timeout:
        pass
    return b"".join(chunks).decode(errors="replace")


def capture(port: int, output: Path) -> bool:
    try:
        connection = socket.create_connection(("127.0.0.1", port), timeout=5)
    except OSError:
        return False
    try:
        send(connection, "")
        ppm = output.with_suffix(".ppm")
        send(connection, f"screendump {ppm}")
        if not ppm.is_file() or ppm.stat().st_size == 0:
            return False
        # A ppm is readable by every viewer and by ImageMagick; converting is
        # best effort so a missing tool never loses the evidence.
        subprocess.run(
            ["convert", str(ppm), str(output.with_suffix(".png"))],
            capture_output=True,
            check=False,
        )
        return True
    finally:
        connection.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--interval", type=float, default=30.0)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    index = 0
    while True:
        if capture(args.port, args.output_dir / f"screen-{index:03d}.ppm"):
            index += 1
        time.sleep(args.interval)


if __name__ == "__main__":
    raise SystemExit(main())
