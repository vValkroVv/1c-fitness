#!/usr/bin/env python3
"""Small cross-platform SQL Server client used by the delivery pipeline.

The package deliberately does not invoke Docker, sqlcmd, bcp, or operating
system specific restore helpers.  It only opens a normal TDS connection to an
already restored Microsoft SQL Server database.
"""

from __future__ import annotations

import csv
import re
from contextlib import AbstractContextManager
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any, Iterable, Sequence

import pytds


GO_LINE = re.compile(r"^\s*GO(?:\s+(\d+))?\s*(?:--.*)?$", re.IGNORECASE)


@dataclass(frozen=True)
class ConnectionSettings:
    server: str
    port: int
    database: str
    user: str
    password: str
    login_timeout_seconds: int = 30
    query_timeout_seconds: int = 0
    encrypt_login: bool = True
    tls_ca_file: str = ""
    tls_validate_host: bool = True


def split_go_batches(sql_text: str) -> list[str]:
    """Split a SQLCMD-style file on standalone GO lines.

    GO is a client-side separator rather than T-SQL.  The supplied SQL files
    use it only on a line by itself, which keeps this parser deterministic.
    """

    batches: list[str] = []
    current: list[str] = []
    for line in sql_text.splitlines():
        match = GO_LINE.match(line)
        if not match:
            current.append(line)
            continue
        batch = "\n".join(current).strip()
        if batch:
            repeat = int(match.group(1) or "1")
            batches.extend([batch] * repeat)
        current = []
    tail = "\n".join(current).strip()
    if tail:
        batches.append(tail)
    return batches


def render_sql(sql_text: str, variables: dict[str, str]) -> str:
    rendered = sql_text
    for key, value in variables.items():
        rendered = rendered.replace(f"$({key})", value)
    unresolved = sorted(set(re.findall(r"\$\(([^)]+)\)", rendered)))
    if unresolved:
        raise ValueError(f"Unresolved SQL variables: {', '.join(unresolved)}")
    return rendered


def quote_identifier(value: str) -> str:
    """Quote a SQL Server identifier without accepting raw SQL fragments."""

    if not value or "\x00" in value:
        raise ValueError("SQL identifier cannot be empty or contain NUL")
    return "[" + value.replace("]", "]]") + "]"


def text_value(value: Any) -> str:
    """Convert a database value to the stable text form used by CSV/TSV."""

    if value is None:
        return ""
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return format(value, "f")
    if isinstance(value, bytes):
        return value.hex().upper()
    return str(value)


def clean_cell(value: Any) -> str:
    return text_value(value).replace("\t", " ").replace("\r", " ").replace("\n", " ")


class DatabaseClient(AbstractContextManager["DatabaseClient"]):
    def __init__(self, settings: ConnectionSettings) -> None:
        self.settings = settings
        kwargs: dict[str, Any] = {
            "server": settings.server,
            "port": settings.port,
            "database": settings.database,
            "user": settings.user,
            "password": settings.password,
            "autocommit": True,
            "login_timeout": settings.login_timeout_seconds,
            "enc_login_only": settings.encrypt_login,
            "appname": "fitbase-end-to-end-xlsx",
        }
        if settings.query_timeout_seconds > 0:
            kwargs["timeout"] = settings.query_timeout_seconds
        if settings.tls_ca_file:
            kwargs["cafile"] = settings.tls_ca_file
            kwargs["validate_host"] = settings.tls_validate_host
        self.connection = pytds.connect(**kwargs)

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self.connection.close()

    def execute_script(
        self,
        sql_path: Path,
        *,
        variables: dict[str, str] | None = None,
        log_path: Path,
    ) -> None:
        sql_text = render_sql(sql_path.read_text(encoding="utf-8-sig"), variables or {})
        batches = split_go_batches(sql_text)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        with log_path.open("w", encoding="utf-8") as log:
            log.write(f"sql_file={sql_path}\n")
            log.write(f"database={self.settings.database}\n")
            log.write(f"batches={len(batches)}\n")
            for batch_number, batch in enumerate(batches, start=1):
                log.write(f"\n[batch {batch_number}/{len(batches)}]\n")
                with self.connection.cursor() as cursor:
                    cursor.execute(batch)
                    self._write_result_sets(cursor, log)
                log.flush()

    @staticmethod
    def _write_result_sets(cursor, log) -> None:
        result_number = 0
        while True:
            if cursor.description:
                result_number += 1
                headers = [column[0] for column in cursor.description]
                log.write(f"result_set={result_number}\n")
                log.write("\t".join(headers) + "\n")
                for row in cursor.fetchall():
                    log.write("\t".join(clean_cell(value) for value in row) + "\n")
            if not cursor.nextset():
                break

    def query_rows(
        self, sql: str, parameters: Sequence[Any] = ()
    ) -> list[tuple[Any, ...]]:
        with self.connection.cursor() as cursor:
            cursor.execute(sql, tuple(parameters))
            return list(cursor.fetchall())

    def query_scalar(self, sql: str, parameters: Sequence[Any] = ()) -> Any:
        rows = self.query_rows(sql, parameters)
        if not rows:
            return None
        return rows[0][0]

    def get_columns(self, schema: str, table: str) -> list[str]:
        rows = self.query_rows(
            """
            SELECT c.name
            FROM sys.columns AS c
            WHERE c.object_id = OBJECT_ID(%s)
            ORDER BY c.column_id
            """,
            (f"{schema}.{table}",),
        )
        columns = [str(row[0]) for row in rows]
        if not columns:
            raise RuntimeError(f"Table not found or has no columns: {schema}.{table}")
        return columns

    def export_table_csv(
        self,
        *,
        schema: str,
        table: str,
        order_by: str,
        output_path: Path,
        chunk_size: int = 2000,
    ) -> int:
        """Export a staging table using the same all-text rules as sqlcmd."""

        columns = self.get_columns(schema, table)
        expressions = []
        for column in columns:
            quoted = quote_identifier(column)
            expressions.append(
                "REPLACE(REPLACE(REPLACE("
                f"COALESCE(CONVERT(nvarchar(max), {quoted}), N''), "
                "CHAR(9), N' '), CHAR(13), N' '), CHAR(10), N' ') "
                f"AS {quoted}"
            )
        query = (
            "SET NOCOUNT ON; SELECT\n    "
            + ",\n    ".join(expressions)
            + f"\nFROM {quote_identifier(schema)}.{quote_identifier(table)}\n"
            + f"ORDER BY {order_by};"
        )

        output_path.parent.mkdir(parents=True, exist_ok=True)
        row_count = 0
        with output_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(columns)
            with self.connection.cursor() as cursor:
                cursor.execute(query)
                while True:
                    rows = cursor.fetchmany(chunk_size)
                    if not rows:
                        break
                    for row in rows:
                        writer.writerow([clean_cell(value) for value in row])
                    row_count += len(rows)
        return row_count

    def export_query_tsv(
        self,
        *,
        query_path: Path,
        output_path: Path,
        expected_columns: Sequence[str] | None = None,
        chunk_size: int = 2000,
    ) -> tuple[int, list[str]]:
        """Export a query as headerless UTF-16 TSV, compatible with old bcp -w."""

        query = query_path.read_text(encoding="utf-8-sig")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        row_count = 0
        with output_path.open("w", encoding="utf-16", newline="") as handle:
            with self.connection.cursor() as cursor:
                cursor.execute(query)
                columns = [column[0] for column in cursor.description or ()]
                if expected_columns is not None and list(expected_columns) != columns:
                    raise RuntimeError(
                        f"Export columns do not match expected fields for {query_path.name}: "
                        f"expected {len(expected_columns)}, got {len(columns)}"
                    )
                while True:
                    rows = cursor.fetchmany(chunk_size)
                    if not rows:
                        break
                    for row in rows:
                        handle.write(
                            "\t".join(clean_cell(value) for value in row) + "\n"
                        )
                    row_count += len(rows)
        return row_count, columns


def find_dbo_source_tables(sql_paths: Iterable[Path]) -> list[str]:
    """Return source dbo table names referenced by the bundled SQL."""

    found: set[str] = set()
    pattern = re.compile(r"\bdbo\.(_[A-Za-z0-9_]+)\b", re.IGNORECASE)
    for path in sql_paths:
        found.update(
            match.group(1)
            for match in pattern.finditer(path.read_text(encoding="utf-8-sig"))
        )
    return sorted(found)
