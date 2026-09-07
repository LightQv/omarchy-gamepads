#!/usr/bin/env python3
"""Emit ready state and a warning before an unrelated runtime exit."""

from __future__ import annotations

import json
from pathlib import Path


fixture = Path(__file__).parents[1] / "tests" / "fixtures" / "two-switch-pro.ndjson"
for line in fixture.read_text(encoding="utf-8").splitlines():
    print(line, flush=True)
print(json.dumps({"type": "error", "code": "mapping_failed", "message": "Controller mapping needs attention."}), flush=True)
raise SystemExit(7)
