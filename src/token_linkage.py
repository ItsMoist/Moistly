#!/usr/bin/env python3
"""Resolve Elysium ↔ HyperEVM token linkage for Moistly.

Three environments matter:

- **Elysium** (99901): high-throughput L2
- **HyperEVM** (999): settlement / hop to HyperCore
- **HyperCore**: spot/perp books (Core linkage via deposit wallets)

Token classes on Elysium:

1. **Canonical representation** — HyperEVM-native ERC-20 locked on HyperEVM,
   minted 1:1 on Elysium. Resolve with router ``calculateL2TokenAddress(l1)``
   and validate ``l1Address()`` round-trip.
2. **Elysium-native** — plain ERC-20 on Elysium. Mirror to HyperEVM via
   ``ElysiumBridgeFactory.expectedL1Mirror(token)`` after one-time setup
   (``l2WalletFor`` nonzero).
3. **Native HYPE** — no ERC-20 in the gas path; WHYPE is the wrapped form and
   is itself a canonical representation of HyperEVM ``0x555…555``.

Docs: https://elysium.kinetiq.xyz/docs/token-bridging-on-elysium
"""

from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from typing import Any, Literal

from Crypto.Hash import keccak as keccak_mod

from src.elysium import (
    ELYSIUM_BRIDGE_FACTORY,
    ELYSIUM_GATEWAY_ROUTER,
    ELYSIUM_MAINNET_PUBLIC_RPC,
    ELYSIUM_USDC,
    ELYSIUM_WHYPE,
    HYPEREVM_ERC20_GATEWAY,
    HYPEREVM_GATEWAY_ROUTER,
    HYPEREVM_USDC,
    HYPEREVM_WHYPE_GATEWAY,
)


TokenClass = Literal[
    "canonical_representation",
    "elysium_native",
    "unknown",
]

HYPEREVM_PUBLIC_RPC = os.environ.get("HYPEREVM_RPC", "https://rpc.hyperliquid.xyz/evm")
HYPEREVM_WRAPPED_HYPE = "0x5555555555555555555555555555555555555555"

# Well-known mainnet pairs Moistly already hardcodes.
KNOWN_PAIRS = {
    "usdc": {
        "elysium": ELYSIUM_USDC,
        "hyperevm": HYPEREVM_USDC,
        "class": "canonical_representation",
        "gateway_hyperevm": HYPEREVM_ERC20_GATEWAY,
    },
    "whype": {
        "elysium": ELYSIUM_WHYPE,
        "hyperevm": HYPEREVM_WRAPPED_HYPE,
        "class": "canonical_representation",
        "gateway_hyperevm": HYPEREVM_WHYPE_GATEWAY,
    },
}


@dataclass(frozen=True)
class TokenLink:
    elysium_token: str
    hyperevm_token: str
    token_class: TokenClass
    gateway: str | None
    l2_wallet: str | None
    paired: bool
    notes: str


def _keccak(data: bytes) -> bytes:
    digest = keccak_mod.new(digest_bits=256)
    digest.update(data)
    return digest.digest()


def _selector(signature: str) -> str:
    return "0x" + _keccak(signature.encode()).hex()[:8]


def _pad_address(address: str) -> str:
    return address.lower().removeprefix("0x").zfill(64)


def _as_address(raw: str) -> str:
    return "0x" + raw[-40:]


def _rpc(url: str, method: str, params: list[Any]) -> Any:
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    request = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "moistly-token-linkage/1.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        body = json.loads(response.read().decode())
    if "error" in body:
        raise RuntimeError(body["error"])
    return body["result"]


def _eth_call(url: str, to: str, data: str) -> str:
    return _rpc(url, "eth_call", [{"to": to, "data": data}, "latest"])


def _checksum(address: str) -> str:
    bare = address.lower().removeprefix("0x")
    if len(bare) != 40:
        raise ValueError(f"Invalid address: {address}")
    digest = _keccak(bare.encode())
    chars: list[str] = []
    for index, char in enumerate(bare):
        if char in "0123456789":
            chars.append(char)
            continue
        # EIP-55: uppercase when the corresponding nibble is >= 8.
        nibble = digest[index // 2] >> (4 if index % 2 == 0 else 0) & 0xF
        chars.append(char.upper() if nibble >= 8 else char)
    return "0x" + "".join(chars)


SEL_L1_ADDRESS = _selector("l1Address()")
SEL_CALCULATE_L2 = _selector("calculateL2TokenAddress(address)")
SEL_GET_GATEWAY = _selector("getGateway(address)")
SEL_EXPECTED_MIRROR = _selector("expectedL1Mirror(address)")
SEL_L2_WALLET = _selector("l2WalletFor(address)")


def known_pair(symbol: str) -> dict[str, str] | None:
    return KNOWN_PAIRS.get(symbol.strip().lower())


def resolve_from_elysium(
    token: str,
    *,
    elysium_rpc: str | None = None,
    hyperevm_rpc: str | None = None,
) -> TokenLink:
    """Classify an Elysium token and return its HyperEVM-side link key."""
    elysium_rpc = elysium_rpc or os.environ.get("ELYSIUM_RPC", ELYSIUM_MAINNET_PUBLIC_RPC)
    hyperevm_rpc = hyperevm_rpc or HYPEREVM_PUBLIC_RPC
    token = _checksum(token)

    l1_key: str | None = None
    try:
        raw_l1 = _eth_call(elysium_rpc, token, SEL_L1_ADDRESS)
        candidate = _as_address(raw_l1)
        round_trip = _as_address(
            _eth_call(
                elysium_rpc,
                ELYSIUM_GATEWAY_ROUTER,
                SEL_CALCULATE_L2 + _pad_address(candidate),
            )
        )
        if round_trip.lower() == token.lower():
            l1_key = _checksum(candidate)
            gateway = _as_address(
                _eth_call(
                    hyperevm_rpc,
                    HYPEREVM_GATEWAY_ROUTER,
                    SEL_GET_GATEWAY + _pad_address(l1_key),
                )
            )
            return TokenLink(
                elysium_token=token,
                hyperevm_token=l1_key,
                token_class="canonical_representation",
                gateway=_checksum(gateway),
                l2_wallet=None,
                paired=True,
                notes="Validated via l1Address() + calculateL2TokenAddress round-trip.",
            )
    except (OSError, urllib.error.URLError, TimeoutError, RuntimeError, ValueError):
        pass

    # Elysium-native path: factory derives the one HyperEVM mirror from metadata.
    try:
        mirror = _as_address(
            _eth_call(
                elysium_rpc,
                ELYSIUM_BRIDGE_FACTORY,
                SEL_EXPECTED_MIRROR + _pad_address(token),
            )
        )
        wallet = _as_address(
            _eth_call(
                elysium_rpc,
                ELYSIUM_BRIDGE_FACTORY,
                SEL_L2_WALLET + _pad_address(token),
            )
        )
        paired = int(wallet, 16) != 0
        return TokenLink(
            elysium_token=token,
            hyperevm_token=_checksum(mirror),
            token_class="elysium_native",
            gateway=None,
            l2_wallet=_checksum(wallet) if paired else None,
            paired=paired,
            notes=(
                "Mirror derived by ElysiumBridgeFactory.expectedL1Mirror. "
                + ("Wallet paired — mirror bridge ready." if paired else "No l2 wallet yet — run one-time mirror setup.")
            ),
        )
    except (OSError, urllib.error.URLError, TimeoutError, RuntimeError, ValueError) as exc:
        return TokenLink(
            elysium_token=token,
            hyperevm_token="0x0000000000000000000000000000000000000000",
            token_class="unknown",
            gateway=None,
            l2_wallet=None,
            paired=False,
            notes=f"Unable to classify token: {exc}",
        )


def resolve_from_hyperevm(
    token: str,
    *,
    elysium_rpc: str | None = None,
    hyperevm_rpc: str | None = None,
) -> TokenLink:
    """Map a HyperEVM-native token to its deterministic Elysium representation."""
    elysium_rpc = elysium_rpc or os.environ.get("ELYSIUM_RPC", ELYSIUM_MAINNET_PUBLIC_RPC)
    hyperevm_rpc = hyperevm_rpc or HYPEREVM_PUBLIC_RPC
    token = _checksum(token)

    representation = _as_address(
        _eth_call(
            hyperevm_rpc,
            HYPEREVM_GATEWAY_ROUTER,
            SEL_CALCULATE_L2 + _pad_address(token),
        )
    )
    # Prefer Elysium router agreement when available.
    representation_elysium = _as_address(
        _eth_call(
            elysium_rpc,
            ELYSIUM_GATEWAY_ROUTER,
            SEL_CALCULATE_L2 + _pad_address(token),
        )
    )
    if representation.lower() != representation_elysium.lower():
        raise RuntimeError(
            f"Router disagreement: HyperEVM={representation} Elysium={representation_elysium}"
        )

    gateway = _as_address(
        _eth_call(
            hyperevm_rpc,
            HYPEREVM_GATEWAY_ROUTER,
            SEL_GET_GATEWAY + _pad_address(token),
        )
    )
    return TokenLink(
        elysium_token=_checksum(representation),
        hyperevm_token=token,
        token_class="canonical_representation",
        gateway=_checksum(gateway),
        l2_wallet=None,
        paired=True,
        notes="Deterministic Elysium representation via calculateL2TokenAddress.",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Resolve Elysium/HyperEVM token linkage")
    parser.add_argument("command", choices=("resolve", "known", "verify-usdc"))
    parser.add_argument("--token", help="Token address to classify")
    parser.add_argument(
        "--from-chain",
        choices=("elysium", "hyperevm"),
        default="elysium",
        help="Which chain the --token address lives on",
    )
    args = parser.parse_args()

    if args.command == "known":
        print(json.dumps(KNOWN_PAIRS, indent=2))
        return

    if args.command == "verify-usdc":
        from_elysium = resolve_from_elysium(ELYSIUM_USDC)
        from_hyperevm = resolve_from_hyperevm(HYPEREVM_USDC)
        whype = resolve_from_elysium(ELYSIUM_WHYPE)
        print(
            json.dumps(
                {
                    "usdc_from_elysium": asdict(from_elysium),
                    "usdc_from_hyperevm": asdict(from_hyperevm),
                    "whype": asdict(whype),
                    "usdc_ok": (
                        from_elysium.hyperevm_token.lower() == HYPEREVM_USDC.lower()
                        and from_hyperevm.elysium_token.lower() == ELYSIUM_USDC.lower()
                    ),
                    "whype_ok": whype.hyperevm_token.lower() == HYPEREVM_WRAPPED_HYPE.lower(),
                },
                indent=2,
            )
        )
        return

    if not args.token:
        raise SystemExit("--token is required for resolve")
    link = (
        resolve_from_hyperevm(args.token)
        if args.from_chain == "hyperevm"
        else resolve_from_elysium(args.token)
    )
    print(json.dumps(asdict(link), indent=2))


if __name__ == "__main__":
    main()
