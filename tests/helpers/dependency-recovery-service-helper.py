#!/usr/bin/env python3
"""Fail once with a dependency error, then replay normally after manual retry."""

from __future__ import annotations

import json
from pathlib import Path
import sys


marker = Path(__file__).with_name(".dependency-retried")
if not marker.exists():
    marker.touch()
    print(json.dumps({"backend": "sdl3", "protocol": 1, "type": "hello", "version": "unavailable"}), flush=True)
    print(json.dumps({"type": "error", "code": "dependency_missing", "message": "SDL3 Python bindings are unavailable."}), flush=True)
else:
    fixture = Path(__file__).parents[1] / "tests" / "fixtures" / "two-switch-pro.ndjson"
    for line in fixture.read_text(encoding="utf-8").splitlines():
        print(line, flush=True)

for line in sys.stdin:
    try:
        command = json.loads(line)
    except json.JSONDecodeError:
        continue
    if command.get("command") == "shutdown":
        break
