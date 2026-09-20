"""Resolve one effective date for all exports while retaining backup provenance."""

from __future__ import annotations

from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation
from typing import Any


TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S"


def parse_timestamp(value: Any, field: str) -> datetime:
    text = str(value).strip()
    try:
        parsed = datetime.strptime(text, TIMESTAMP_FORMAT)
    except ValueError as exc:
        raise ValueError(f"{field} must be YYYY-MM-DD HH:MM:SS") from exc
    if parsed.strftime(TIMESTAMP_FORMAT) != text:
        raise ValueError(f"{field} must be YYYY-MM-DD HH:MM:SS")
    return parsed


def resolve_cutoff(run: dict[str, Any], backup: dict[str, Any]) -> dict[str, str]:
    """An explicit customer as-of setting overrides only the effective cutoff.

    Legacy configurations still default to the exact BackupFinishDate. Dates
    of sales, payments and contracts are never shifted by this function.
    """
    finish = parse_timestamp(backup.get("backup_finish_at", ""), "backup.backup_finish_at")
    explicit = run.get("effective_at")
    offset = run.get("effective_offset_days")
    if explicit not in (None, "") and offset not in (None, ""):
        raise ValueError("Choose only one of run.effective_at and run.effective_offset_days")
    effective = finish
    source = "backup.backup_finish_at"
    if explicit not in (None, ""):
        effective = parse_timestamp(explicit, "run.effective_at")
        source = "run.effective_at"
    elif offset not in (None, ""):
        try:
            seconds = Decimal(str(offset)) * 86400
            if not seconds.is_finite() or seconds != seconds.to_integral_value():
                raise ValueError("offset must resolve to a whole number of seconds")
            effective = finish + timedelta(seconds=int(seconds))
        except (InvalidOperation, OverflowError, ValueError) as exc:
            raise ValueError("run.effective_offset_days must be a finite day offset at second precision") from exc
        source = "run.effective_offset_days"
    canonical = {
        "backup_finish_at": finish.strftime(TIMESTAMP_FORMAT),
        "cutoff_at": effective.strftime(TIMESTAMP_FORMAT),
        "cutoff_date": effective.strftime("%Y-%m-%d"),
        "date_stamp": effective.strftime("%Y%m%d"),
    }
    for field, expected in canonical.items():
        configured = str(run.get(field, expected)).strip()
        if configured != expected:
            raise ValueError(f"run.{field}={configured!r} does not match resolved value {expected!r}")
        run[field] = expected
    for field in ("membership_cutoff_at", "services_cutoff_at", "photos_cutoff_at"):
        if field in run and str(run[field]).strip() != canonical["cutoff_at"]:
            raise ValueError(f"run.{field} must match the single effective cutoff {canonical['cutoff_at']!r}")
    return {"source": source, **canonical,
            "effective_shift_seconds": str(int((effective - finish).total_seconds()))}
