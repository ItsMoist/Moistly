#!/usr/bin python3
from flask import current_app
from web3 import HTTPProvider, Web3


class RPCService:
    def __init__(self, provider: str, rpc_url: str) -> None:
        if not rpc_url:
            raise RuntimeError(f"RPC provider is not configured: {provider}")
        self.provider = provider
        self.url = rpc_url
        self.web3 = Web3(HTTPProvider(rpc_url, request_kwargs={"timeout": 10}))

    @classmethod
    def from_app(cls, provider: str | None = None) -> "RPCService":
        providers = current_app.config.get("RPC_PROVIDERS", {})
        selected = provider or current_app.config.get("DEFAULT_RPC_PROVIDER")
        if selected not in providers:
            raise ValueError(f"Unknown RPC provider: {selected}")
        return cls(selected, providers[selected])

    def network_status(self) -> dict:
        return {
            "provider": self.provider,
            "connected": self.web3.is_connected(),
            "chain_id": self.web3.eth.chain_id,
            "block_number": self.web3.eth.block_number,
        }

    def account_state(self, address: str) -> dict:
        checksum_address = self.web3.to_checksum_address(address)
        code = self.web3.eth.get_code(checksum_address)
        return {
            "provider": self.provider,
            "address": checksum_address,
            "balance_wei": str(self.web3.eth.get_balance(checksum_address)),
            "nonce": self.web3.eth.get_transaction_count(checksum_address),
            "is_contract": len(code) > 0,
            "code": code.hex(),
        }
