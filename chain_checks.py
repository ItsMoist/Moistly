from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv
from web3 import HTTPProvider, Web3

from src.elysium import (
    ELYSIUM_MAINNET_PUBLIC_RPC,
    ELYSIUM_TESTNET_PUBLIC_RPC,
    MAINNET as ELYSIUM_MAINNET,
    TESTNET as ELYSIUM_TESTNET,
    effective_rpc_url,
)
from utils import generate_jwt_from_private_pem


ROOT = Path(__file__).resolve().parent


@dataclass(frozen=True)
class ChainConfig:
    name: str
    env_var: str
    expected_chain_id: int
    public_rpc: str | None = None
    use_alchemy_jwt: bool = True


CHAINS = [
    ChainConfig("ethereum", "ALCHEMY_ETH_RPC", 1),
    ChainConfig("base", "ALCHEMY_BASE_RPC", 8453),
    ChainConfig("bnb", "ALCHEMY_BNB_RPC", 56),
    ChainConfig("arbitrum", "ALCHEMY_ARB_RPC", 42161),
    ChainConfig(
        "elysium",
        ELYSIUM_MAINNET.alchemy_env,
        ELYSIUM_MAINNET.chain_id,
        public_rpc=ELYSIUM_MAINNET_PUBLIC_RPC,
        use_alchemy_jwt=False,
    ),
    ChainConfig(
        "elysium-testnet",
        ELYSIUM_TESTNET.alchemy_env,
        ELYSIUM_TESTNET.chain_id,
        public_rpc=ELYSIUM_TESTNET_PUBLIC_RPC,
        use_alchemy_jwt=False,
    ),
    ChainConfig(
        "hyperevm",
        "ALCHEMY_HYPEREVM_RPC",
        999,
        public_rpc="https://rpc.hyperliquid.xyz/evm",
        use_alchemy_jwt=False,
    ),
]


def alchemy_jwt_headers() -> dict[str, str]:
    token = generate_jwt_from_private_pem(ROOT / "private.pem", os.environ["JWT_PK_ID"])
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


def rpc_url_for_env(env_var: str) -> str:
    url = os.environ.get(env_var)
    if not url:
        raise RuntimeError(f"{env_var} is not set")

    return url.rsplit("/", 1)[0] if "/v2/" in url else url


def resolve_rpc(chain: ChainConfig) -> tuple[str, dict[str, str]]:
    """Return (rpc_url, request_headers) for a chain."""
    if chain.name in {"elysium", "elysium-testnet"}:
        return effective_rpc_url(chain.name), {}

    url = os.environ.get(chain.env_var)
    if url:
        normalized = url.rsplit("/", 1)[0] if "/v2/" in url else url
        headers = alchemy_jwt_headers() if chain.use_alchemy_jwt else {}
        return normalized, headers

    if chain.public_rpc:
        return chain.public_rpc, {}

    raise RuntimeError(f"{chain.env_var} is not set")


def web3_for_chain(chain: ChainConfig) -> Web3:
    url, headers = resolve_rpc(chain)
    request_kwargs: dict = {"timeout": 15}
    if headers:
        request_kwargs["headers"] = headers
    return Web3(HTTPProvider(url, request_kwargs=request_kwargs))


def main() -> None:
    load_dotenv(ROOT / ".env")
    for chain in CHAINS:
        try:
            w3 = web3_for_chain(chain)
            chain_id = w3.eth.chain_id
            status = "ok" if chain_id == chain.expected_chain_id else "unexpected"
            print(
                f"{chain.name}: status={status} chain_id={chain_id} "
                f"latest_block={w3.eth.block_number}"
            )
        except Exception as exc:
            print(f"{chain.name}: failed {type(exc).__name__}: {exc}")


if __name__ == "__main__":
    main()
