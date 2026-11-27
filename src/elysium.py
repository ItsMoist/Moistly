#!/usr/bin/env python3
"""Elysium (Kinetiq) chain constants and RPC helpers for Moistly.

Elysium is an Arbitrum Orbit L2 that settles to HyperEVM, uses HYPE as gas,
and exposes standard EVM tooling. Docs: https://elysium.kinetiq.xyz/docs
"""

from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from typing import Any


ELYSIUM_MAINNET_CHAIN_ID = 99901
ELYSIUM_TESTNET_CHAIN_ID = 99801
HYPEREVM_MAINNET_CHAIN_ID = 999
HYPEREVM_TESTNET_CHAIN_ID = 998

ELYSIUM_MAINNET_PUBLIC_RPC = "https://rpc.elysium.kinetiq.xyz"
ELYSIUM_TESTNET_PUBLIC_RPC = "https://testnet-rpc.elysium.kinetiq.xyz"
ELYSIUM_MAINNET_EXPLORER = "https://elysium.kinetiq.xyz/explorer"
ELYSIUM_TESTNET_EXPLORER = "https://elysium.kinetiq.xyz/testnet-explorer"

# Canonical mainnet addresses from https://elysium.kinetiq.xyz/docs/contract-addresses
ELYSIUM_MULTICALL3 = "0xcA11bde05977b3631167028862bE2a173976CA11"
ELYSIUM_WHYPE = "0xbA876237B0F021A6c6D852d6c26E107997cC5E81"
ELYSIUM_USDC = "0xb47c4C8F73F009CC0C0d3f92B388d13E293F0B65"
ELYSIUM_GATEWAY_ROUTER = "0x61EbbC3A29f1970aF2Ce862bA9c5364832E14d17"
ELYSIUM_ERC20_GATEWAY = "0x5DC84e4Cb0F9082246E92a5585C5395592B1aF1f"
ELYSIUM_WHYPE_GATEWAY = "0xb916e67307ad52955d37B6C123CF1A79c10855B6"
ELYSIUM_BRIDGE_FACTORY = "0x209B0476ec33841c661f41C0C260A3b8aF94164A"

# HyperEVM side of the Elysium bridge (mainnet)
HYPEREVM_USDC = "0xb88339CB7199b77E23DB6E890353E22632Ba630f"
HYPEREVM_GATEWAY_ROUTER = "0x5D24f760DD7664b4214bDD4B04a3f62B9edd68c0"
HYPEREVM_ERC20_GATEWAY = "0xd97B30dE0bA0C2eAeE942afce77530e06c5F122c"
HYPEREVM_WHYPE_GATEWAY = "0x4ADeEcE99eDfa453e40E79FfD2F179008F5a91EB"
HYPEREVM_INBOX = "0xce59f8B65ad41C9DAE4c07A0571a39824bD92cff"
HYPEREVM_OUTBOX = "0xeC6B106DfA14428FE5Eec2a4065a7be599f02728"
HYPEREVM_BRIDGE = "0x503D572157113fAaaD4DbeD2647Bb10b949216B6"
HYPEREVM_ROLLUP = "0x508C173dFe5F737B3493195Bf785d71fA76fD217"

NATIVE = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

TOKEN_ALIASES_MAINNET = {
    "usdc": ELYSIUM_USDC,
    "whype": ELYSIUM_WHYPE,
    "weth": ELYSIUM_WHYPE,  # wrapped native on Elysium is WHYPE
    "hype": NATIVE,
    "native": NATIVE,
    "gas": NATIVE,
}


@dataclass(frozen=True)
class ElysiumNetwork:
    name: str
    chain_id: int
    settles_to_chain_id: int
    public_rpc: str
    alchemy_env: str
    public_env: str
    explorer: str
    currency: str = "HYPE"


MAINNET = ElysiumNetwork(
    name="elysium",
    chain_id=ELYSIUM_MAINNET_CHAIN_ID,
    settles_to_chain_id=HYPEREVM_MAINNET_CHAIN_ID,
    public_rpc=ELYSIUM_MAINNET_PUBLIC_RPC,
    alchemy_env="ALCHEMY_ELYSIUM_RPC",
    public_env="ELYSIUM_RPC",
    explorer=ELYSIUM_MAINNET_EXPLORER,
)

TESTNET = ElysiumNetwork(
    name="elysium-testnet",
    chain_id=ELYSIUM_TESTNET_CHAIN_ID,
    settles_to_chain_id=HYPEREVM_TESTNET_CHAIN_ID,
    public_rpc=ELYSIUM_TESTNET_PUBLIC_RPC,
    alchemy_env="ALCHEMY_ELYSIUM_TESTNET_RPC",
    public_env="ELYSIUM_TESTNET_RPC",
    explorer=ELYSIUM_TESTNET_EXPLORER,
)

NETWORKS = {
    "elysium": MAINNET,
    "elysium-mainnet": MAINNET,
    "elysium-testnet": TESTNET,
    "elysium_testnet": TESTNET,
}


def resolve_network(name: str = "elysium") -> ElysiumNetwork:
    key = name.strip().lower()
    if key not in NETWORKS:
        supported = ", ".join(sorted(set(NETWORKS)))
        raise KeyError(f"Unknown Elysium network {name!r}. Supported: {supported}")
    return NETWORKS[key]


def rpc_url(network: ElysiumNetwork | str = "elysium", *, allow_public: bool = True) -> str:
    net = resolve_network(network) if isinstance(network, str) else network
    for env_var in (net.alchemy_env, net.public_env):
        value = os.environ.get(env_var)
        if value:
            return value
    if allow_public:
        return net.public_rpc
    raise RuntimeError(
        f"No RPC configured for {net.name}. Set {net.alchemy_env} or {net.public_env}."
    )


def alchemy_http_url(network: ElysiumNetwork | str = "elysium") -> str | None:
    """Return an Alchemy HTTPS URL shape if ALCHEMY_API_KEY is set."""
    net = resolve_network(network) if isinstance(network, str) else network
    key = os.environ.get("ALCHEMY_API_KEY")
    if not key:
        return None
    slug = "elysium-mainnet" if net.chain_id == ELYSIUM_MAINNET_CHAIN_ID else "elysium-testnet"
    return f"https://{slug}.g.alchemy.com/v2/{key}"


def effective_rpc_url(network: ElysiumNetwork | str = "elysium") -> str:
    """Prefer explicit env, then Alchemy API key template, then public RPC."""
    net = resolve_network(network) if isinstance(network, str) else network
    for env_var in (net.alchemy_env, net.public_env):
        value = os.environ.get(env_var)
        if value:
            return value
    templated = alchemy_http_url(net)
    if templated:
        return templated
    return net.public_rpc


def contracts(network: ElysiumNetwork | str = "elysium") -> dict[str, str]:
    net = resolve_network(network) if isinstance(network, str) else network
    if net.chain_id != ELYSIUM_MAINNET_CHAIN_ID:
        return {
            "note": "Canonical mainnet addresses only; substitute testnet docs values.",
            "chain_id": str(net.chain_id),
            "explorer": net.explorer,
            "rpc": effective_rpc_url(net),
        }
    return {
        "chain_id": str(net.chain_id),
        "explorer": net.explorer,
        "rpc": effective_rpc_url(net),
        "multicall3": ELYSIUM_MULTICALL3,
        "whype": ELYSIUM_WHYPE,
        "usdc": ELYSIUM_USDC,
        "gateway_router": ELYSIUM_GATEWAY_ROUTER,
        "erc20_gateway": ELYSIUM_ERC20_GATEWAY,
        "whype_gateway": ELYSIUM_WHYPE_GATEWAY,
        "bridge_factory": ELYSIUM_BRIDGE_FACTORY,
        "hyperevm_usdc": HYPEREVM_USDC,
        "hyperevm_gateway_router": HYPEREVM_GATEWAY_ROUTER,
        "hyperevm_erc20_gateway": HYPEREVM_ERC20_GATEWAY,
        "hyperevm_whype_gateway": HYPEREVM_WHYPE_GATEWAY,
        "hyperevm_inbox": HYPEREVM_INBOX,
        "hyperevm_outbox": HYPEREVM_OUTBOX,
        "hyperevm_bridge": HYPEREVM_BRIDGE,
        "hyperevm_rollup": HYPEREVM_ROLLUP,
    }


def _json_rpc(url: str, method: str, params: list[Any] | None = None) -> Any:
    payload = json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": method, "params": params or []}
    ).encode()
    request = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            # Some public RPCs reject the default Python-urllib User-Agent.
            "User-Agent": "moistly-elysium/1.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        body = json.loads(response.read().decode())
    if "error" in body:
        raise RuntimeError(body["error"])
    return body["result"]


def ping(network: ElysiumNetwork | str = "elysium") -> dict[str, Any]:
    net = resolve_network(network) if isinstance(network, str) else network
    url = effective_rpc_url(net)
    chain_id_hex = _json_rpc(url, "eth_chainId")
    block_hex = _json_rpc(url, "eth_blockNumber")
    chain_id = int(chain_id_hex, 16)
    return {
        "network": net.name,
        "rpc": url,
        "expected_chain_id": net.chain_id,
        "chain_id": chain_id,
        "settles_to_chain_id": net.settles_to_chain_id,
        "latest_block": int(block_hex, 16),
        "ok": chain_id == net.chain_id,
        "explorer": net.explorer,
        "currency": net.currency,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Elysium helpers for Moistly")
    parser.add_argument(
        "command",
        choices=("ping", "contracts", "networks"),
        help="ping RPC, print contracts, or list networks",
    )
    parser.add_argument(
        "--network",
        default="elysium",
        help="elysium | elysium-testnet (default: elysium)",
    )
    args = parser.parse_args()

    if args.command == "networks":
        print(json.dumps({name: asdict(net) for name, net in NETWORKS.items()}, indent=2))
        return
    if args.command == "contracts":
        print(json.dumps(contracts(args.network), indent=2))
        return

    try:
        result = ping(args.network)
    except (OSError, urllib.error.URLError, TimeoutError, RuntimeError, ValueError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, indent=2))
        raise SystemExit(1) from exc
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["ok"] else 2)


if __name__ == "__main__":
    main()
