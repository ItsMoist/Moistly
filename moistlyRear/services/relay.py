"""Read-only Relay order and credited-balance discovery."""
import json
import re
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


class RelayUnavailable(RuntimeError):
    pass


def summarize(order):
    data = order.get('data') or {}
    status = order.get('status', 'unknown')
    return dict(id=order.get('id'), status=status, recipient=order.get('recipient'),
                refund_to=order.get('refundTo'), claim_status=data.get('claimStatus'),
                failure_reason=data.get('failReason'), refund_failure_reason=data.get('refundFailReason'),
                deposits=transactions(data.get('inTxs') or []), outputs=transactions(data.get('outTxs') or []),
                next_action={'success': 'inspect_destination', 'refund': 'inspect_refund'}.get(status, 'check_relay_recovery'),
                withdrawal_eligibility='unverified')


def transactions(items):
    return [{k: t.get(k) for k in ('txHash', 'chainId', 'status', 'type')} for t in items]


class RelayRecovery:
    def __init__(self, api_key=None):
        self.api_key = api_key

    def get(self, path, params):
        headers = {'Accept': 'application/json', 'User-Agent': 'Moistly-Recovery/1.0'}
        if self.api_key:
            headers['x-api-key'] = self.api_key
        req = Request('https://api.relay.link' + path + '?' + urlencode(params), headers=headers)
        try:
            with urlopen(req, timeout=15) as response:
                payload = json.load(response)
            if not isinstance(payload, dict):
                raise ValueError('Invalid response')
            return payload
        except (URLError, OSError, ValueError) as exc:
            raise RelayUnavailable('Relay lookup unavailable') from exc

    def inspect(self, address, mode='orders', continuation=None, owner_chain_id=None, deposit_tx=None):
        if not re.fullmatch(r'0x[0-9a-fA-F]{40}', address):
            raise ValueError('Expected an EVM wallet address')
        if continuation and len(continuation) > 512:
            raise ValueError('Invalid continuation cursor')
        if mode == 'orders':
            if deposit_tx and not re.fullmatch(r'0x[0-9a-fA-F]{64}', deposit_tx):
                raise ValueError('Expected a deposit transaction hash')
            if not self.api_key:
                raise RelayUnavailable('RELAY_API_KEY required for order discovery')
            params = {'user': address, 'limit': 20}
            if deposit_tx:
                params['depositTxHash'] = deposit_tx
            path, key = '/requests/v3', 'requests'
        elif mode == 'balances':
            try:
                chain = int(owner_chain_id)
            except (TypeError, ValueError):
                raise ValueError('owner_chain_id is required and must be an integer') from None
            if not 1 <= chain <= 9007199254740991:
                raise ValueError('Invalid owner chain ID')
            params = {'recoveryAddress': address, 'ownerChainId': chain, 'limit': 20}
            path, key = '/withdrawals/balances', 'balances'
        else:
            raise ValueError('mode must be orders or balances')
        if continuation:
            params['continuation'] = continuation
        payload = self.get(path, params)
        if not isinstance(payload.get(key), list) or any(not isinstance(x, dict) for x in payload[key]):
            raise RelayUnavailable('Invalid Relay response')
        try:
            items = [summarize(x) for x in payload[key]] if mode == 'orders' else payload[key]
        except (AttributeError, TypeError) as exc:
            raise RelayUnavailable('Invalid Relay order') from exc
        return {mode: items, 'continuation': payload.get('continuation'),
                'withdrawal_eligibility': 'unverified',
                'coverage': 'relay_indexed_orders_only' if mode == 'orders' else 'credited_hub_balances_only'}
