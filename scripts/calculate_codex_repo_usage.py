#!/usr/bin/env python3
"""Estimate this repository's API-equivalent cost from local Codex JSONL logs."""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path


# Standard API prices in USD per million tokens, checked on 2026-09-24.
PRICES = {
    "gpt-5.5": ("5", "0.5", "30"),
    "gpt-5.6-sol": ("4", "0.4", "20"),
    "gpt-6-astra": ("10", "1", "50"),
    "gpt-6-sol": ("2", "0.2", "10"),
    "gpt-6-luna": ("0.1", "0.01", "0.5"),
}
FIELDS = (
    "input_tokens",
    "cached_input_tokens",
    "cache_write_input_tokens",
    "output_tokens",
    "reasoning_output_tokens",
    "total_tokens",
)
MILLION = Decimal(1_000_000)


@dataclass
class Event:
    timestamp: str
    model: str | None
    total: dict[str, int]
    last: dict[str, int]


def counters(data: dict) -> dict[str, int]:
    return {field: int(data.get(field, 0) or 0) for field in FIELDS}


def read_sessions(codex_home: Path, repo_cwd: str):
    sessions = defaultdict(list)
    models = defaultdict(list)
    files = 0
    malformed_lines = 0
    paths = list((codex_home / "sessions").rglob("*.jsonl"))
    paths += list((codex_home / "archived_sessions").glob("*.jsonl"))
    for path in paths:
        with path.open(encoding="utf-8") as handle:
            try:
                first = json.loads(handle.readline())
            except (json.JSONDecodeError, OSError):
                continue
            meta = first.get("payload") or {}
            if first.get("type") != "session_meta" or meta.get("cwd") != repo_cwd:
                continue
            files += 1
            session_id = meta.get("id")
            model = None
            for line in handle:
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    malformed_lines += 1
                    continue
                payload = item.get("payload") or {}
                if item.get("type") == "turn_context":
                    model = payload.get("model") or model
                    if model:
                        models[session_id].append(model)
                elif item.get("type") == "event_msg" and payload.get("type") == "token_count":
                    info = payload.get("info") or {}
                    total = info.get("total_token_usage") or {}
                    if total.get("total_tokens") is None:
                        continue
                    last = info.get("last_token_usage") or {}
                    sessions[session_id].append(
                        Event(item["timestamp"], model, counters(total), counters(last))
                    )
    return sessions, models, files, malformed_lines


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-cwd", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--codex-home", type=Path, default=Path.home() / ".codex")
    args = parser.parse_args()
    sessions, models, file_count, malformed_lines = read_sessions(
        args.codex_home, args.repo_cwd
    )

    per_model = defaultdict(Counter)
    costs = defaultdict(lambda: Decimal(0))
    base_costs = defaultdict(lambda: Decimal(0))
    anomalies = Counter()
    first_timestamp = last_timestamp = None
    event_count = 0
    long_context_events = Counter()

    for session_id, events in sessions.items():
        events.sort(key=lambda event: (event.timestamp, event.total["total_tokens"]))
        fallback_model = models[session_id][0] if models[session_id] else "unknown"
        previous = None
        for event in events:
            event_count += 1
            first_timestamp = min(first_timestamp or event.timestamp, event.timestamp)
            last_timestamp = max(last_timestamp or event.timestamp, event.timestamp)
            model = event.model or fallback_model
            if previous is None:
                # A child session can inherit the parent's cumulative counters.
                usage = event.last if event.last["total_tokens"] else event.total
                if usage["total_tokens"] != event.total["total_tokens"]:
                    anomalies["inherited_first_counters"] += 1
            elif any(event.total[field] < previous[field] for field in FIELDS):
                # A resumed session can restart its cumulative counters.
                usage = event.last if event.last["total_tokens"] else event.total
                anomalies["counter_resets"] += 1
            else:
                usage = {
                    field: event.total[field] - previous[field] for field in FIELDS
                }
                if usage["total_tokens"] > event.last["total_tokens"]:
                    anomalies["unlogged_intermediate_usage"] += 1
            previous = event.total
            if not usage["total_tokens"]:
                anomalies["repeated_counters"] += 1
                continue
            per_model[model].update(usage)
            if model not in PRICES:
                continue
            input_rate, cached_rate, output_rate = map(Decimal, PRICES[model])
            uncached = usage["input_tokens"] - usage["cached_input_tokens"]
            cache_writes = usage["cache_write_input_tokens"]
            uncached -= cache_writes
            if uncached < 0:
                raise ValueError(f"Invalid input counters for {session_id}")
            input_cost = (
                uncached * input_rate
                + usage["cached_input_tokens"] * cached_rate
                + cache_writes * input_rate * Decimal("1.25")
            ) / MILLION
            output_cost = usage["output_tokens"] * output_rate / MILLION
            base_costs[model] += input_cost + output_cost
            if event.last["input_tokens"] > 272_000:
                input_cost *= 2
                output_cost *= Decimal("1.5")
                long_context_events[model] += 1
            costs[model] += input_cost + output_cost

    if any(model not in PRICES for model in per_model):
        raise ValueError(f"Unknown models: {set(per_model) - set(PRICES)}")
    totals = Counter()
    for usage in per_model.values():
        totals.update(usage)
    unclassified_tokens = totals["total_tokens"] - totals["input_tokens"] - totals["output_tokens"]
    report = {
        "repo_cwd": args.repo_cwd,
        "files": file_count,
        "sessions": len(sessions),
        "token_events": event_count,
        "first_event_utc": first_timestamp,
        "last_event_utc": last_timestamp,
        "totals": dict(totals),
        "unclassified_tokens": unclassified_tokens,
        "estimated_without_long_context_usd": str(sum(base_costs.values(), Decimal(0)).quantize(Decimal("0.01"))),
        "estimated_standard_api_usd": str(sum(costs.values(), Decimal(0)).quantize(Decimal("0.01"))),
        "models": {
            model: {
                **dict(usage),
                "unclassified_tokens": usage["total_tokens"] - usage["input_tokens"] - usage["output_tokens"],
                "cost_usd": str(costs[model].quantize(Decimal("0.01"))),
                "long_context_events": long_context_events[model],
            }
            for model, usage in sorted(per_model.items())
        },
        "anomalies": dict(anomalies),
        "malformed_lines": malformed_lines,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
