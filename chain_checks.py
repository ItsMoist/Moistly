from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv
from web3 import HTTPProvider, Web3

from utils import generate_jwt_from_private_pem


ROOT = Path(__file__).resolve().parent


@dataclass(frozen=True)
class ChainConfig:
    name: str
    env_var: str
    expected_chain_id: int


CHAINS = [
    ChainConfig("ethereum", "ALCHEMY_ETH_RPC", 1),
    ChainConfig("base", "ALCHEMY_BASE_RPC", 8453),
    ChainConfig("bnb", "ALCHEMY_BNB_RPC", 56),
    ChainConfig("arbitrum", "ALCHEMY_ARB_RPC", 42161),
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


def web3_for_chain(chain: ChainConfig) -> Web3:
    return Web3(
        HTTPProvider(
            rpc_url_for_env(chain.env_var),
            request_kwargs={"headers": alchemy_jwt_headers()},
        )
    )


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
