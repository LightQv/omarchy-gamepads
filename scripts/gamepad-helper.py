#!/usr/bin/env python3
"""Command-line entry point for the Omarchy Gamepads backend."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

from gamepad_backend import ProtocolError, replay, run_live


def main() -> int:
    parser = argparse.ArgumentParser(description="Omarchy Gamepads SDL3 helper")
    parser.add_argument("--replay", type=Path, help="emit a deterministic protocol fixture")
    arguments = parser.parse_args()

    if arguments.replay:
        try:
            return replay(arguments.replay, sys.stdout)
        except (OSError, ProtocolError) as error:
            print(f"Replay failed: {error}", file=sys.stderr)
            return 4
    return run_live()


if __name__ == "__main__":
    raise SystemExit(main())
