import os
from collections.abc import Iterable
from typing import Any

import pg8000


DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASS = os.environ["DB_PASS"]
DB_HOST = os.environ["DB_HOST"]
DB_PORT = int(os.environ.get("DB_PORT", "5432"))


def get_connection():
    return pg8000.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
    )


def execute_script(script: str) -> None:
    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute(script)
            conn.commit()
        finally:
            cursor.close()


def fetch_all(query: str, params: Iterable[Any] = ()) -> list[tuple[Any, ...]]:
    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute(query, tuple(params))
            return list(cursor.fetchall())
        finally:
            cursor.close()


def fetch_one(query: str, params: Iterable[Any] = ()) -> tuple[Any, ...] | None:
    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute(query, tuple(params))
            return cursor.fetchone()
        finally:
            cursor.close()
