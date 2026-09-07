#!/usr/bin/python3
"""Export reviewed diagnostic reports to private local state."""

from __future__ import annotations

import ctypes
import errno
import json
import os
import secrets
import stat
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

MAX_INPUT_BYTES = 2 * 1024 * 1024
MAX_REPORT_BYTES = 1024 * 1024
RENAME_NOREPLACE = 1


def _serialized_report(value: Any) -> bytes:
    if not isinstance(value, dict):
        raise ValueError("report must be an object")
    encoded = (json.dumps(value, indent=2, ensure_ascii=True) + "\n").encode("utf-8")
    if len(encoded) > MAX_REPORT_BYTES:
        raise ValueError("report is too large")
    return encoded


def _report_text(value: Any) -> bytes:
    if not isinstance(value, str):
        raise ValueError("text report must be a string")
    encoded = (value.rstrip("\n") + "\n").encode("utf-8")
    if len(encoded) > MAX_REPORT_BYTES:
        raise ValueError("text report is too large")
    return encoded


def _open_directory(path: Path) -> int:
    if not path.is_absolute():
        raise ValueError("report directory must be absolute")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
    directory_fd = os.open("/", flags)
    try:
        for component in path.parts[1:]:
            if component in {"", ".", ".."}:
                raise ValueError("report directory is unsafe")
            try:
                os.mkdir(component, mode=0o700, dir_fd=directory_fd)
            except FileExistsError:
                pass
            next_fd = os.open(component, flags, dir_fd=directory_fd)
            details = os.fstat(next_fd)
            if not stat.S_ISDIR(details.st_mode) or details.st_uid not in {0, os.getuid()}:
                os.close(next_fd)
                raise ValueError("report directory is unsafe")
            os.close(directory_fd)
            directory_fd = next_fd
        os.fchmod(directory_fd, 0o700)
        return directory_fd
    except Exception:
        os.close(directory_fd)
        raise


def _write_new(directory_fd: int, name: str, content: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW
    file_fd = os.open(name, flags, 0o600, dir_fd=directory_fd)
    try:
        offset = 0
        while offset < len(content):
            offset += os.write(file_fd, content[offset:])
        os.fsync(file_fd)
    finally:
        os.close(file_fd)


def _publish_directory(directory_fd: int, source: str, destination: str) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    renameat2 = getattr(libc, "renameat2", None)
    if renameat2 is None:
        raise OSError(errno.ENOSYS, "renameat2 is unavailable")
    renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    renameat2.restype = ctypes.c_int
    if renameat2(
        directory_fd,
        os.fsencode(source),
        directory_fd,
        os.fsencode(destination),
        RENAME_NOREPLACE,
    ) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), destination)


def export_reports(payload: Any, report_directory: Path) -> str:
    if not isinstance(payload, dict) or set(payload) != {"report", "text"}:
        raise ValueError("invalid export payload")
    json_report = _serialized_report(payload["report"])
    text_report = _report_text(payload["text"])

    timestamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    token = secrets.token_hex(8)
    basename = f"diagnostic-{timestamp}-{token}"
    temporary_name = f".{basename}.tmp"
    report_fd = _open_directory(report_directory)
    temporary_fd = -1
    published = False
    try:
        os.mkdir(temporary_name, mode=0o700, dir_fd=report_fd)
        temporary_fd = os.open(
            temporary_name,
            os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW,
            dir_fd=report_fd,
        )
        _write_new(temporary_fd, "report.json", json_report)
        _write_new(temporary_fd, "report.md", text_report)
        os.fsync(temporary_fd)
        _publish_directory(report_fd, temporary_name, basename)
        published = True
        os.fsync(report_fd)
        return basename
    finally:
        if temporary_fd >= 0:
            os.close(temporary_fd)
        if not published:
            for name in ("report.json", "report.md"):
                try:
                    os.unlink(f"{temporary_name}/{name}", dir_fd=report_fd)
                except FileNotFoundError:
                    pass
            try:
                os.rmdir(temporary_name, dir_fd=report_fd)
            except FileNotFoundError:
                pass
        os.close(report_fd)


def main() -> int:
    raw = sys.stdin.buffer.readline(MAX_INPUT_BYTES + 1)
    if len(raw) > MAX_INPUT_BYTES:
        return 2
    try:
        payload = json.loads(raw)
        report_directory = Path.home() / ".local" / "state" / "omarchy-gamepads" / "reports"
        basename = export_reports(payload, report_directory)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
        return 1
    sys.stdout.write(json.dumps({"ok": True, "basename": basename}) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
