"""Read-only Relay recovery discovery."""
import os
from flask import Blueprint, current_app, jsonify, request
from ..services.relay import RelayRecovery, RelayUnavailable

recovery = Blueprint('recovery', __name__)


@recovery.get('/api/v1/recovery/relay/<address>')
def inspect_relay(address):
    service = RelayRecovery(current_app.config.get('RELAY_API_KEY') or os.getenv('RELAY_API_KEY'))
    try:
        result = service.inspect(address, mode=request.args.get('mode', 'orders'),
                                 continuation=request.args.get('continuation'),
                                 owner_chain_id=request.args.get('owner_chain_id'),
                                 deposit_tx=request.args.get('deposit_tx'))
    except ValueError as exc:
        return jsonify(ok=False, error='invalid_input', message=str(exc)), 400
    except RelayUnavailable:
        return jsonify(ok=False, error='relay_unavailable',
                       message='Check Relay availability and server-side RELAY_API_KEY configuration.'), 503
    return jsonify(ok=True, wallet=address, read_only=True,
                   recovery_url='https://relay.link/withdraw', **result)
