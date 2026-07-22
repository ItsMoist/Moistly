from flask import Blueprint, current_app, jsonify, render_template, request

from ..services.webhook_store import webhook_store
from ..services.webhooks import WebhookService


webhooks = Blueprint("webhooks", __name__)
service = WebhookService()


def receive_webhook():
    body = request.get_data(cache=True)
    payload = request.get_json(silent=True)
    if payload is None:
        return jsonify(ok=False, error="invalid_json"), 400

    result = service.process(request.path, request.headers, body, payload)
    webhook_store().append(result.event(request.path))

    current_app.logger.info(
        "webhook provider=%s verified=%s event=%s body=%s headers=%s",
        result.provider,
        result.verified,
        result.normalized.get("event_type"),
        result.safe_body,
        result.safe_headers,
    )

    strict = current_app.config.get("WEBHOOK_STRICT_VERIFY", True)
    if service.should_reject(result, strict):
        return jsonify(ok=False, verified=False, reason=result.verify_reason), 401

    return jsonify(result.response())


@webhooks.get("/webhooks")
def webhook_viewer():
    provider = request.args.get("provider", "").lower()
    if provider not in ("", "alchemy", "privy"):
        return jsonify(ok=False, error="unknown_webhook_provider"), 400

    try:
        limit = min(max(int(request.args.get("limit", "100")), 1), 500)
    except ValueError:
        return jsonify(ok=False, error="invalid_limit"), 400

    events = webhook_store().recent(limit=limit, provider=provider)
    return render_template(
        "webhooks.html",
        events=events,
        provider=provider,
        limit=limit,
    )


webhooks.add_url_rule(
    "/webhooks/alchemy",
    endpoint="alchemy",
    view_func=receive_webhook,
    methods=["POST"],
)
webhooks.add_url_rule(
    "/webhooks/privy",
    endpoint="privy",
    view_func=receive_webhook,
    methods=["POST"],
)
