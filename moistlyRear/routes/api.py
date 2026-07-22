from flask import Blueprint, current_app, jsonify, request
from web3.exceptions import Web3Exception

from ..services.providers import provider_status
from ..services.rpc import RPCService


api = Blueprint("api", __name__)


@api.get("/")
def index():
    return jsonify(service="moistlyRear", status="ok")


@api.get("/health")
def health():
    try:
        status = RPCService.from_app().network_status()
    except (OSError, RuntimeError, ValueError, Web3Exception) as exc:
        current_app.logger.warning("RPC health check failed: %s", exc)
        return jsonify(
            ok=False,
            service="moistlyRear",
            rpc_connected=False,
            error="rpc_unavailable",
        ), 503

    if not status["connected"]:
        return jsonify(
            ok=False,
            service="moistlyRear",
            rpc_connected=False,
            error="rpc_unavailable",
        ), 503

    return jsonify(
        ok=True,
        service="moistlyRear",
        rpc_connected=True,
        rpc_provider=status["provider"],
        chain_id=status["chain_id"],
        block_number=status["block_number"],
    )


@api.get("/api/v1/network")
def network_status():
    try:
        status = RPCService.from_app(request.args.get("provider")).network_status()
    except ValueError as exc:
        return jsonify(ok=False, error="unknown_rpc_provider", message=str(exc)), 400
    except (OSError, RuntimeError, ValueError, Web3Exception) as exc:
        current_app.logger.warning("RPC network check failed: %s", exc)
        return jsonify(ok=False, error="rpc_unavailable"), 503

    return jsonify(ok=True, **status)


@api.get("/api/v1/providers")
def providers():
    return jsonify(ok=True, **provider_status())


@api.get("/api/v1/accounts/<address>")
def account_state(address: str):
    try:
        state = RPCService.from_app(request.args.get("provider")).account_state(address)
    except ValueError as exc:
        if "RPC provider" in str(exc):
            return jsonify(ok=False, error="unknown_rpc_provider", message=str(exc)), 400
        return jsonify(ok=False, error="invalid_address"), 400
    except (OSError, RuntimeError, Web3Exception) as exc:
        current_app.logger.warning("RPC account lookup failed: %s", exc)
        return jsonify(ok=False, error="rpc_unavailable"), 503

    return jsonify(ok=True, **state)
