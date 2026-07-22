from dataclasses import dataclass
from datetime import UTC, datetime

from source.webhook_receiver import (
    body_for_log,
    normalize_event,
    provider_from_path,
    react_to_event,
    response_actions,
    sanitize_headers,
    should_reject_unverified,
    verify_request,
)


@dataclass(frozen=True)
class WebhookResult:
    provider: str
    verified: bool
    verify_reason: str
    normalized: dict
    actions: list[dict]
    reaction: dict
    safe_body: object
    safe_headers: dict[str, str]

    def response(self) -> dict:
        return {
            "ok": True,
            "provider": self.provider,
            "verified": self.verified,
            "verify_reason": self.verify_reason,
            "normalized": self.normalized,
            "actions": self.actions,
            "reaction": self.reaction,
        }

    def event(self, path: str) -> dict:
        return {
            "ts": datetime.now(UTC).isoformat(),
            "provider": self.provider,
            "path": path,
            "verified": self.verified,
            "verify_reason": self.verify_reason,
            "headers": self.safe_headers,
            "body": self.safe_body,
            "normalized": self.normalized,
            "actions": self.actions,
            "reaction": self.reaction,
        }


class WebhookService:
    def process(self, path: str, headers: object, body: bytes, payload: dict) -> WebhookResult:
        provider = provider_from_path(path)
        verified, reason = verify_request(provider, headers, body, path)
        normalized = normalize_event(provider, path, payload)
        actions = response_actions(provider, verified, reason, normalized)
        reaction = react_to_event(provider, verified, reason, normalized, actions)

        return WebhookResult(
            provider=provider,
            verified=verified,
            verify_reason=reason,
            normalized=normalized,
            actions=actions,
            reaction=reaction,
            safe_body=body_for_log(provider, path, payload, normalized),
            safe_headers=sanitize_headers(dict(headers)),
        )

    @staticmethod
    def should_reject(result: WebhookResult, strict: bool) -> bool:
        return strict and should_reject_unverified(
            result.provider,
            result.verified,
            result.verify_reason,
        )
