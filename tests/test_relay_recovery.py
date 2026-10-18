import unittest
from unittest.mock import patch
from urllib.error import URLError
from moistlyRear import create_app
from moistlyRear.services.relay import RelayRecovery, RelayUnavailable

WALLET = '0x' + '1' * 40


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app('testing')
        self.app.config['RELAY_API_KEY'] = 'test-only'
        self.client = self.app.test_client()
        self.url = '/api/v1/recovery/relay/' + WALLET

    def test_order_evidence_and_cursor(self):
        order = {'id': 'order1', 'status': 'failed', 'data': {'inTxs': [{'txHash': 'deposit', 'chainId': 42161}], 'outTxs': []}}
        with patch.object(RelayRecovery, 'get', return_value={'requests': [order], 'continuation': 'next'}) as get:
            data = self.client.get(self.url + '?continuation=prev').get_json()
        self.assertEqual(data['orders'][0]['withdrawal_eligibility'], 'unverified')
        self.assertEqual(data['orders'][0]['deposits'][0]['txHash'], 'deposit')
        self.assertEqual(data['continuation'], 'next')
        self.assertEqual(get.call_args.args[1]['continuation'], 'prev')

    def test_balances_are_not_guaranteed_claims(self):
        with patch.object(RelayRecovery, 'get', return_value={'balances': [{'amount': '46000000'}], 'continuation': None}) as get:
            data = self.client.get(self.url + '?mode=balances&owner_chain_id=42161').get_json()
        self.assertEqual(get.call_args.args[1]['ownerChainId'], 42161)
        self.assertEqual(data['withdrawal_eligibility'], 'unverified')

    def test_invalid_inputs_never_reach_upstream(self):
        with patch.object(RelayRecovery, 'get') as get:
            for suffix in ['?mode=unknown', '?mode=balances', '?deposit_tx=bad', '?continuation=' + 'x' * 513]:
                self.assertEqual(self.client.get(self.url + suffix).status_code, 400)
            self.assertEqual(self.client.get('/api/v1/recovery/relay/bad').status_code, 400)
            get.assert_not_called()

    def test_upstream_failure(self):
        with patch.object(RelayRecovery, 'get', side_effect=RelayUnavailable('secret')):
            response = self.client.get(self.url)
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('secret', response.get_data(as_text=True))

    def test_malformed_data(self):
        with patch.object(RelayRecovery, 'get', return_value={'requests': [{'data': 'bad'}]}):
            self.assertEqual(self.client.get(self.url).status_code, 503)

    def test_no_write_endpoint(self):
        self.assertEqual(self.client.post(self.url).status_code, 405)

    def test_transport_error(self):
        with patch('moistlyRear.services.relay.urlopen', side_effect=URLError('offline')):
            with self.assertRaises(RelayUnavailable):
                RelayRecovery().get('/withdrawals/balances', {})

    def test_success_and_refund_actions(self):
        from moistlyRear.services.relay import summarize
        self.assertEqual(summarize({'status': 'success'})['next_action'], 'inspect_destination')
        self.assertEqual(summarize({'status': 'refund'})['next_action'], 'inspect_refund')


if __name__ == '__main__':
    unittest.main()
