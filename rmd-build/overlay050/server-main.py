from __future__ import annotations

import os
import sqlite3
import time
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field


DB_PATH = Path(os.environ.get("RMD_SYNC_DB", "rmd-sync.sqlite3"))
EXPECTED_TOKEN = os.environ.get("RMD_SYNC_TOKEN", "")

app = FastAPI(title="RMD Opaque Sync Relay", version="0.5.0")


class OpaqueObject(BaseModel):
    object_id: str = Field(min_length=1, max_length=200)
    revision: int = Field(ge=0)
    ciphertext: str = Field(min_length=1, max_length=2_000_000)


class StoredObject(OpaqueObject):
    updated_at: int


def _connect() -> sqlite3.Connection:
    connection = sqlite3.connect(DB_PATH)
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS opaque_objects (
            object_id TEXT PRIMARY KEY,
            revision INTEGER NOT NULL,
            ciphertext TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        )
        """
    )
    return connection


def _authenticate(authorization: str | None = Header(default=None)) -> None:
    if not EXPECTED_TOKEN:
        raise HTTPException(status_code=503, detail="RMD_SYNC_TOKEN is not configured")
    if authorization != f"Bearer {EXPECTED_TOKEN}":
        raise HTTPException(status_code=401, detail="invalid sync token")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.put("/objects/{object_id}", dependencies=[Depends(_authenticate)])
def put_object(object_id: str, value: OpaqueObject) -> StoredObject:
    if object_id != value.object_id:
        raise HTTPException(status_code=400, detail="object ID mismatch")
    updated_at = int(time.time())
    with _connect() as connection:
        current = connection.execute(
            "SELECT revision FROM opaque_objects WHERE object_id = ?", (object_id,)
        ).fetchone()
        if current is not None and value.revision <= int(current[0]):
            raise HTTPException(status_code=409, detail="revision must increase")
        connection.execute(
            """
            INSERT INTO opaque_objects(object_id, revision, ciphertext, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(object_id) DO UPDATE SET
                revision = excluded.revision,
                ciphertext = excluded.ciphertext,
                updated_at = excluded.updated_at
            """,
            (object_id, value.revision, value.ciphertext, updated_at),
        )
    return StoredObject(**value.model_dump(), updated_at=updated_at)


@app.get("/objects/{object_id}", response_model=StoredObject, dependencies=[Depends(_authenticate)])
def get_object(object_id: str) -> StoredObject:
    with _connect() as connection:
        row = connection.execute(
            "SELECT object_id, revision, ciphertext, updated_at FROM opaque_objects WHERE object_id = ?",
            (object_id,),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="object not found")
    return StoredObject(object_id=row[0], revision=row[1], ciphertext=row[2], updated_at=row[3])
