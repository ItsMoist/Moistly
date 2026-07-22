import json
import threading
from datetime import UTC, datetime
from pathlib import Path

from flask import current_app
from sqlalchemy import select

from ..storage.database import session
from ..storage.models import WebhookEvent


class WebhookStore:
    _write_lock = threading.Lock()

    def __init__(self, path: str | Path | None) -> None:
        self.path = Path(path) if path else None

    def append(self, event: dict) -> None:
        if self.path is None:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        serialized = json.dumps(event, separators=(",", ":"), default=str)
        with self._write_lock, self.path.open("a", encoding="utf-8") as stream:
            stream.write(serialized + "\n")

    def recent(self, *, limit: int = 100, provider: str = "") -> list[dict]:
        if self.path is None or not self.path.exists():
            return []

        events: list[dict] = []
        with self.path.open("r", encoding="utf-8") as stream:
            for line in stream:
                try:
                    event = json.loads(line)
                except (json.JSONDecodeError, TypeError):
                    continue
                if not isinstance(event, dict):
                    continue
                if provider and event.get("provider") != provider:
                    continue
                events.append(event)

        return list(reversed(events[-limit:]))


class MssqlWebhookStore:
    def append(self, event: dict) -> None:
        normalized = event.get("normalized") or {}
        tx_hashes = normalized.get("tx_hashes") or []
        received_at = _parse_timestamp(event.get("ts"))
        row = WebhookEvent(
            received_at=received_at,
            provider=str(event.get("provider") or "unknown"),
            event_type=str(normalized.get("event_type") or "unknown"),
            verified=bool(event.get("verified")),
            verify_reason=str(event.get("verify_reason") or ""),
            path=str(event.get("path") or ""),
            transaction_hash=str(tx_hashes[0]) if tx_hashes else None,
            payload=json.dumps(event.get("body"), separators=(",", ":"), default=str),
            normalized=json.dumps(normalized, separators=(",", ":"), default=str),
            actions=json.dumps(event.get("actions") or [], separators=(",", ":"), default=str),
            reaction=json.dumps(event.get("reaction") or {}, separators=(",", ":"), default=str),
        )
        with session() as database:
            database.add(row)
            database.commit()

    def recent(self, *, limit: int = 100, provider: str = "") -> list[dict]:
        statement = select(WebhookEvent).order_by(WebhookEvent.received_at.desc()).limit(limit)
        if provider:
            statement = statement.where(WebhookEvent.provider == provider)
        with session() as database:
            rows = database.scalars(statement).all()
            return [_event_dict(row) for row in rows]


def webhook_store():
    if current_app.config.get("STORAGE_BACKEND") == "mssql":
        return MssqlWebhookStore()
    return WebhookStore(current_app.config.get("WEBHOOK_LOG_PATH"))


def _parse_timestamp(value: object) -> datetime:
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).replace(tzinfo=None)
        except ValueError:
            pass
    return datetime.now(UTC).replace(tzinfo=None)


def _event_dict(row: WebhookEvent) -> dict:
    return {
        "id": row.id,
        "ts": row.received_at.isoformat() + "Z",
        "provider": row.provider,
        "path": row.path,
        "verified": row.verified,
        "verify_reason": row.verify_reason,
        "body": json.loads(row.payload),
        "normalized": json.loads(row.normalized),
        "actions": json.loads(row.actions),
        "reaction": json.loads(row.reaction),
    }
