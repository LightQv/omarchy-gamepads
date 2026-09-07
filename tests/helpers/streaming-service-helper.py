#!/usr/bin/env python3
"""Verify the service's selected-controller streaming command lifecycle."""

from __future__ import annotations

import json
from pathlib import Path
import sys


fixture = Path(__file__).parents[1] / "tests" / "fixtures" / "two-switch-pro.ndjson"
messages = fixture.read_text(encoding="utf-8").splitlines()
print(messages[0], flush=True)
print(messages[1], flush=True)

expected = [
    (["11"], True, "stream_11_ready"),
    (["12"], True, "stream_12_ready"),
    ([], False, "stream_cleared"),
]
step = 0
subscribed: list[str] | None = None

for line in sys.stdin:
    try:
        command = json.loads(line)
    except json.JSONDecodeError:
        continue
    if command.get("command") == "shutdown":
        break
    if command.get("command") == "subscribe":
        subscribed = command.get("ids")
        continue
    if command.get("command") != "setStreaming" or step >= len(expected):
        continue
    ids, enabled, marker = expected[step]
    if subscribed == ids and command.get("enabled") is enabled:
        print(json.dumps({"type": "error", "code": marker, "message": marker}), flush=True)
        step += 1
