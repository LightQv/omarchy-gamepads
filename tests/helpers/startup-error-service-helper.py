#!/usr/bin/env python3
"""Emit a structured startup failure before exiting."""

from __future__ import annotations

import json


print(json.dumps({"backend": "sdl3", "protocol": 1, "type": "hello", "version": "3.4.14"}), flush=True)
print(json.dumps({"type": "error", "code": "initialization_failed", "message": "SDL3 gamepad initialization failed."}), flush=True)
raise SystemExit(3)
