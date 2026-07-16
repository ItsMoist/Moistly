#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import logging
import os
import time
import urllib.error
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from dotenv import load_dotenv
from eth_account import Account
from eth_utils import to_checksum_address
from web3 import Web3


ROOT = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT / "logs" / "bridge-quotes.jsonl"
NATIVE = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
LIFI_BASE = "https://li.quest/v1"
RELAY_BASE = "https://api.relay.link"
RHINO_BASE = "https://api.rhino.fi/bridge"
DEFAULT_DOMAIN_NAME = "moistbandz.com"
MAINMOIST_ADDRESS = "0x1b4C289c4f6e0565f1E432654254485c490679e9"
DCC3_ADDRESS = "0x75e732608Bc17B23D01f01728562Ee844196DCC3"
ADDRESS_1= "0x0000000000000000000000000000000000000001"
8DBB_ADDRESS = ""
ADDRESS_1562 = "0x33de8904812785a8828Af49770907DC27c431562"
DOMAIN_ACCOUNTS = {
    "mainmoist": MAINMOIST_ADDRESS,
    "dcc3": DCC3_ADDRESS,
    "8DDB":
}

log = logging.getLogger("script.bridge_to_l1")
CHAINS = {
    "eth": {"id": 1, "rpc": "ALCHEMY_ETH_RPC"},
    "ethereum": {"id": 1, "rpc": "ALCHEMY_ETH_RPC"},
    "base": {"id": 8453, "rpc": "ALCHEMY_BASE_RPC"},
    "arb": {"id": 42161, "rpc": "ALCHEMY_ARB_RPC"},
    "arbitrum": {"id": 42161, "rpc": "ALCHEMY_ARB_RPC"},
    "op": {"id": 10, "rpc": "ALCHEMY_OP_RPC"},
    "optimism": {"id": 10, "rpc": "ALCHEMY_OP_RPC"},
    "pol": {"id": 137, "rpc": "ALCHEMY_POLYGON_RPC"},
    "polygon": {"id": 137, "rpc": "ALCHEMY_POLYGON_RPC"},
    "avax": {"id": 43114, "rpc": "ALCHEMY_AVAX_RPC"},
    "avalanche": {"id": 43114, "rpc": "ALCHEMY_AVAX_RPC"},
    "bnb": {"id": 56, "rpc": "ALCHEMY_BNB_RPC"},
    "bsc": {"id": 56, "rpc": "ALCHEMY_BNB_RPC"},
}
TOKEN_ALIASES = {
    1: {
        "dai": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
        "usdc": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        "usdt": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
        "wbtc": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
        "weth": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    },
    10: {
        "dai": "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
        "op": "0x4200000000000000000000000000000000000042",
        "usdc": "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85",
        "usdt": "0x94b008aD8eB991f9C797d7dAF4aD4e7E4dDbbEdb",
        "wbtc": "0x68f180fcCe6836688e9084f035309E29Bf0A2095",
        "weth": "0x4200000000000000000000000000000000000006",
    },
    56: {
        "btcb": "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c",
        "busd": "0x4Fabb145d64652a948d72533023f6E7A623C7C53",
        "dai": "0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3",
        "usdc": "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d",
        "usdt": "0x55d398326f99059fF775485246999027B3197955",
        "weth": "0x2170Ed0880ac9A755fd29B2688956BD959F933F8",
    },
    137: {
        "dai": "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063",
        "pol": "0x0000000000000000000000000000000000001010",
        "usdc": "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359",
        "usdc.e": "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
        "usdt": "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
        "wbtc": "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6",
        "weth": "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619",
    },
    8453: {
        "aero": "0x940181a94A35A4569E4529A3CDfB74e38FD98631",
        "cbbtc": "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf",
        "dai": "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb",
        "usdc": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        "usdbc": "0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA",
        "weth": "0x4200000000000000000000000000000000000006",
    },
    42161: {
        "arb": "0x912CE59144191C1204E64559FE8253a0e49E6548",
        "dai": "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
        "usdc": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
        "usdc.e": "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
        "usdt": "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
        "wbtc": "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f",
        "weth": "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    },
    43114: {
        "dai.e": "0xd586E7F844cEa2F87f50152665BCbc2C279D8d70",
        "usdc": "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E",
        "usdc.e": "0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664",
        "usdt": "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7",
        "usdt.e": "0xc7198437980c041c805A1EDcbA50c1Ce5db95118",
        "wbtc.e": "0x50b7545627a5162F82A992c33b87aDc75187B218",
        "weth.e": "0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB",
    },
}
RHINO_CHAIN_ALIASES = {
    1: "ETHEREUM",
    10: "OPTIMISM",
    56: "BNB",
    137: "POLYGON",
    8453: "BASE",
    42161: "ARBITRUM",
    43114: "AVALANCHE",
}


def chain_id(value: str) -> int:
    key = value.lower()
    if key in CHAINS:
        return int(CHAINS[key]["id"])
    return int(value, 0)


def resolve_token(value: str, chain: int) -> str:
    token = value.strip()
    key = token.lower()
    if key in {"eth", "ether", "native", "gas", "bnb", "avax", "matic"}:
        return NATIVE
    if key in {"zero", "0", ZERO_ADDRESS}:
        return ZERO_ADDRESS
    if key.startswith("0x"):
        if len(key) != 42:
            raise RuntimeError(f"Token address must be 20 bytes: {value}")
        return to_checksum_address(token)
    aliases = TOKEN_ALIASES.get(chain, {})
    if key not in aliases:
        supported = ", ".join(["eth", *sorted(aliases)])
        raise RuntimeError(f"Unsupported token alias {value!r} on chain {chain}. Supported: {supported}")
    return to_checksum_address(aliases[key])


def resolve_address(value: str) -> str:
    key = value.strip().lower()
    if key in DOMAIN_ACCOUNTS:
        return to_checksum_address(DOMAIN_ACCOUNTS[key])
    return to_checksum_address(value)


def domain_metadata(domain: str, layerzero_executor: str | None = None) -> dict:
    metadata = {
        "name": domain,
        "accounts": {name: to_checksum_address(address) for name, address in DOMAIN_ACCOUNTS.items()},
    }
    if layerzero_executor:
        metadata["layerzeroExecutor"] = resolve_address(layerzero_executor)
    return metadata


def rpc_env_for(chain: int) -> str:
    for cfg in CHAINS.values():
        if int(cfg["id"]) == chain:
            return str(cfg["rpc"])
    raise RuntimeError(f"No configured RPC env for chain {chain}.")


def parse_int(value: int | str | None, default: int = 0) -> int:
    if value is None:
        return default
    if isinstance(value, int):
        return value
    return int(value, 0)


def decimal_from_units(amount: int | str, decimals: int) -> str:
    value = parse_int(amount)
    if decimals == 0:
        return str(value)
    sign = "-" if value < 0 else ""
    digits = str(abs(value)).rjust(decimals + 1, "0")
    whole = digits[:-decimals]
    fraction = digits[-decimals:].rstrip("0")
    return f"{sign}{whole}.{fraction}" if fraction else f"{sign}{whole}"


def read_private_key(key_env: str) -> str:
    value = os.environ.get(key_env)
    if not value:
        raise RuntimeError(f"Missing {key_env}.")
    value = value.strip()
    return value if value.startswith("0x") else f"0x{value}"


def lifi_get(path: str, params: dict[str, str]) -> dict:
    url = f"{LIFI_BASE}{path}?{urlencode(params)}"
    headers = {"accept": "application/json", "user-agent": "debndni-bridge/1.0"}
    if os.environ.get("LIFI_API_KEY"):
        headers["x-lifi-api-key"] = os.environ["LIFI_API_KEY"]
    req = Request(url, headers=headers)
    try:
        with urlopen(req, timeout=45) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise RuntimeError(f"LI.FI HTTP {exc.code}: {body}") from exc


def relay_post(path: str, payload: dict) -> dict:
    url = f"{RELAY_BASE}{path}"
    headers = {
        "accept": "application/json",
        "content-type": "application/json",
        "user-agent": "debndni-bridge/1.0",
    }
    if os.environ.get("RELAY_API_KEY"):
        headers["authorization"] = f"Bearer {os.environ['RELAY_API_KEY']}"
    req = Request(url, data=json.dumps(payload).encode(), headers=headers, method="POST")
    try:
        with urlopen(req, timeout=45) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise RuntimeError(f"Relay HTTP {exc.code}: {body}") from exc


def rhino_auth_header() -> str:
    token = os.environ.get("RHINO_API_AUTH") or os.environ.get("RHINO_JWT") or os.environ.get("RHINOFI_JWT")
    if not token:
        raise RuntimeError("Missing Rhino.fi auth. Set RHINO_API_AUTH or RHINO_JWT.")
    token = token.strip()
    return token if token.lower().startswith("bearer ") else f"Bearer {token}"


def rhino_get(path: str) -> dict:
    req = Request(f"{RHINO_BASE}{path}", headers={"accept": "application/json", "user-agent": "debndni-bridge/1.0"})
    try:
        with urlopen(req, timeout=45) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise RuntimeError(f"Rhino.fi HTTP {exc.code}: {body}") from exc


def rhino_post(path: str, payload: dict) -> dict:
    req = Request(
        f"{RHINO_BASE}{path}",
        data=json.dumps(payload).encode(),
        headers={
            "accept": "application/json",
            "authorization": rhino_auth_header(),
            "content-type": "application/json",
            "user-agent": "debndni-bridge/1.0",
        },
        method="POST",
    )
    try:
        with urlopen(req, timeout=45) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise RuntimeError(f"Rhino.fi HTTP {exc.code}: {body}") from exc


def append_log(event: dict) -> None:
    LOG_PATH.parent.mkdir(exist_ok=True)
    with LOG_PATH.open("a") as fh:
        fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **event}) + "\n")


def summarize_quote(quote: dict) -> dict:
    tx = quote.get("transactionRequest") or {}
    estimate = quote.get("estimate") or {}
    action = quote.get("action") or {}
    return {
        "id": quote.get("id"),
        "tool": quote.get("tool"),
        "fromChainId": action.get("fromChainId"),
        "toChainId": action.get("toChainId"),
        "fromToken": action.get("fromToken", {}).get("address"),
        "toToken": action.get("toToken", {}).get("address"),
        "fromAmount": action.get("fromAmount"),
        "toAmount": estimate.get("toAmount"),
        "toAmountMin": estimate.get("toAmountMin"),
        "approvalAddress": estimate.get("approvalAddress"),
        "executionDurationSeconds": estimate.get("executionDuration"),
        "transactionRequest": {
            "to": tx.get("to"),
            "value": tx.get("value"),
            "data_len_bytes": (len(tx.get("data", "0x")) - 2) // 2,
            "gasLimit": tx.get("gasLimit") or tx.get("gas"),
            "chainId": tx.get("chainId"),
        },
    }


def summarize_relay_quote(quote: dict) -> dict:
    steps = quote.get("steps") or []
    step_summaries = []
    for step in steps:
        items = step.get("items") or []
        item_summaries = []
        for item in items:
            data = item.get("data") or {}
            tx = data.get("tx") or data.get("transaction") or data
            item_summaries.append(
                {
                    "status": item.get("status"),
                    "kind": item.get("kind"),
                    "requestId": item.get("requestId") or step.get("requestId"),
                    "check": item.get("check"),
                    "tx": {
                        "to": tx.get("to"),
                        "value": tx.get("value"),
                        "data_len_bytes": (len(tx.get("data", "0x")) - 2) // 2 if tx.get("data") else 0,
                        "gas": tx.get("gas") or tx.get("gasLimit"),
                        "chainId": tx.get("chainId"),
                    }
                    if tx.get("to")
                    else None,
                }
            )
        step_summaries.append(
            {
                "id": step.get("id"),
                "kind": step.get("kind"),
                "requestId": step.get("requestId"),
                "items": item_summaries,
            }
        )
    return {
        "requestId": quote.get("requestId"),
        "originChainId": quote.get("originChainId") or quote.get("details", {}).get("currencyIn", {}).get("currency", {}).get("chainId"),
        "destinationChainId": quote.get("destinationChainId") or quote.get("details", {}).get("currencyOut", {}).get("currency", {}).get("chainId"),
        "fees": quote.get("fees"),
        "expandedPriceImpact": quote.get("expandedPriceImpact"),
        "steps": step_summaries,
    }


def summarize_rhino_quote(quote: dict, config: dict, chain_in: str, token_in: str) -> dict:
    chain_cfg = config.get(chain_in) or {}
    token_cfg = (chain_cfg.get("tokens") or {}).get(token_in) or {}
    return {
        "quoteId": quote.get("quoteId"),
        "tag": quote.get("_tag"),
        "chainIn": quote.get("chainIn"),
        "chainOut": quote.get("chainOut"),
        "token": quote.get("token") or quote.get("tokenIn"),
        "tokenOut": quote.get("tokenOut"),
        "payAmount": quote.get("payAmount"),
        "receiveAmount": quote.get("receiveAmount"),
        "receiveAmountUsd": quote.get("receiveAmountUsd"),
        "fees": quote.get("fees"),
        "expiresAt": quote.get("expiresAt"),
        "bridgeContract": chain_cfg.get("contractAddress"),
        "tokenAddress": token_cfg.get("address"),
        "tokenDecimals": token_cfg.get("decimals"),
        "nextStep": "commit quote, then call depositNativeWithId or depositWithId on bridgeContract",
    }


def build_lifi_quote(args: argparse.Namespace, sender: str, recipient: str) -> dict:
    from_chain = chain_id(args.from_chain)
    to_chain = chain_id(args.to_chain)
    params = {
        "fromChain": str(from_chain),
        "toChain": str(to_chain),
        "fromToken": resolve_token(args.from_token, from_chain),
        "toToken": resolve_token(args.to_token, to_chain),
        "fromAmount": str(args.amount_wei),
        "fromAddress": sender,
        "toAddress": recipient,
        "slippage": str(args.slippage),
        "order": args.order,
        "integrator": args.integrator,
    }
    if args.allow_bridges:
        params["allowBridges"] = args.allow_bridges
    if args.deny_bridges:
        params["denyBridges"] = args.deny_bridges
    return lifi_get("/quote", params)


def build_relay_quote(args: argparse.Namespace, sender: str, recipient: str) -> dict:
    from_chain = chain_id(args.from_chain)
    to_chain = chain_id(args.to_chain)
    payload = {
        "user": sender,
        "recipient": recipient,
        "originChainId": from_chain,
        "destinationChainId": to_chain,
        "originCurrency": resolve_token(args.from_token, from_chain),
        "destinationCurrency": resolve_token(args.to_token, to_chain),
        "amount": str(args.amount_wei),
        "tradeType": "EXACT_INPUT",
    }
    if args.relay_referrer:
        payload["referrer"] = args.relay_referrer
    return relay_post("/quote/v2", payload)


def rhino_chain(value: str) -> str:
    if value.upper() in RHINO_CHAIN_ALIASES.values():
        return value.upper()
    chain = chain_id(value)
    if chain not in RHINO_CHAIN_ALIASES:
        raise RuntimeError(f"Rhino.fi chain alias not configured for chain {chain}.")
    return RHINO_CHAIN_ALIASES[chain]


def rhino_token(value: str, chain_cfg: dict) -> str:
    key = value.strip().lower()
    native = str(chain_cfg.get("nativeTokenName") or "").upper()
    if key in {"eth", "ether", "native", "gas", "bnb", "avax", "matic"}:
        return native
    if key.startswith("0x"):
        for symbol, cfg in (chain_cfg.get("tokens") or {}).items():
            if str(cfg.get("address", "")).lower() == key:
                return symbol
        raise RuntimeError(f"Token address {value} was not found in Rhino.fi config for {chain_cfg.get('name')}.")
    return key.upper()


def build_rhino_quote(args: argparse.Namespace, sender: str, recipient: str) -> tuple[dict, dict, str, str]:
    config = rhino_get("/configs")
    chain_in = rhino_chain(args.from_chain)
    chain_out = rhino_chain(args.to_chain)
    if chain_in not in config:
        raise RuntimeError(f"Rhino.fi config does not include source chain {chain_in}.")
    if chain_out not in config:
        raise RuntimeError(f"Rhino.fi config does not include destination chain {chain_out}.")
    token_in = rhino_token(args.from_token, config[chain_in])
    token_out = rhino_token(args.to_token, config[chain_out])
    token_cfg = (config[chain_in].get("tokens") or {}).get(token_in)
    if not token_cfg:
        supported = ", ".join(sorted((config[chain_in].get("tokens") or {}).keys()))
        raise RuntimeError(f"Rhino.fi token {token_in} is not supported on {chain_in}. Supported: {supported}")
    amount = args.amount or decimal_from_units(args.amount_wei, int(token_cfg["decimals"]))
    payload = {
        "amount": amount,
        "amountNative": str(args.amount_native),
        "chainIn": chain_in,
        "chainOut": chain_out,
        "depositor": sender,
        "mode": args.rhino_mode,
        "recipient": recipient,
        "tokenIn": token_in,
        "tokenOut": token_out,
    }
    if args.refund_address:
        payload["refundAddress"] = to_checksum_address(args.refund_address)
    if args.webhook_url:
        payload["webhookUrl"] = args.webhook_url
    return rhino_post("/quote/bridge-swap/user", payload), config, chain_in, token_in


def sign_and_send_transaction(tx_req: dict, key_env: str, from_chain: int, expected_sender: str) -> str:
    private_key = read_private_key(key_env)
    account = Account.from_key(private_key)
    if to_checksum_address(account.address) != to_checksum_address(expected_sender):
        raise RuntimeError(f"{key_env} resolves to {account.address}, not quote sender {expected_sender}.")
    rpc_url = os.environ.get(rpc_env_for(from_chain))
    if not rpc_url:
        raise RuntimeError(f"Missing {rpc_env_for(from_chain)}.")
    web3 = Web3(Web3.HTTPProvider(rpc_url))
    tx = {
        "chainId": from_chain,
        "from": account.address,
        "to": to_checksum_address(tx_req["to"]),
        "data": tx_req.get("data", "0x"),
        "value": parse_int(tx_req.get("value")),
        "nonce": web3.eth.get_transaction_count(account.address, "pending"),
        "gas": parse_int(tx_req.get("gasLimit") or tx_req.get("gas")),
    }
    if "maxFeePerGas" in tx_req:
        tx["maxFeePerGas"] = parse_int(tx_req["maxFeePerGas"])
        tx["maxPriorityFeePerGas"] = parse_int(tx_req.get("maxPriorityFeePerGas"))
    else:
        tx["gasPrice"] = parse_int(tx_req.get("gasPrice"), web3.eth.gas_price)
    if tx["gas"] <= 0:
        tx["gas"] = web3.eth.estimate_gas(tx)
    signed = account.sign_transaction(tx)
    return web3.eth.send_raw_transaction(signed.raw_transaction).hex()


def broadcast_lifi_quote(quote: dict, key_env: str, from_chain: int, sender: str) -> list[str]:
    return [sign_and_send_transaction(dict(quote["transactionRequest"]), key_env, from_chain, sender)]


def relay_transaction_items(quote: dict) -> list[dict]:
    transactions = []
    for step in quote.get("steps") or []:
        for item in step.get("items") or []:
            if item.get("status") == "complete":
                continue
            data = item.get("data") or {}
            tx = data.get("tx") or data.get("transaction") or data
            if tx.get("to"):
                transactions.append(tx)
            elif item.get("kind") == "signature" or data.get("sign"):
                raise RuntimeError("Relay quote requires a signature step; transaction-only broadcasting is not enough.")
    if not transactions:
        raise RuntimeError("Relay quote did not include a transaction step.")
    return transactions


def broadcast_relay_quote(quote: dict, key_env: str, from_chain: int, sender: str) -> list[str]:
    hashes = []
    for tx in relay_transaction_items(quote):
        hashes.append(sign_and_send_transaction(tx, key_env, from_chain, sender))
    return hashes


def default_sender(args: argparse.Namespace) -> str:
    if args.from_address:
        return resolve_address(args.from_address)
    for env_name in ("BRIDGE_FROM_ADDRESS", "MAINMOIST_ADDRESS", "DEPLOYER_ADDRESS"):
        if os.environ.get(env_name):
            return to_checksum_address(os.environ[env_name])
    if args.broadcast:
        return Account.from_key(read_private_key(args.key_env)).address
    raise RuntimeError("Set --from-address for dry-run quotes, or BRIDGE_FROM_ADDRESS/MAINMOIST_ADDRESS in .env.")


def default_recipient(args: argparse.Namespace) -> str:
    if args.to_address:
        return resolve_address(args.to_address)
    for env_name in ("BRIDGE_TO_L1_RECIPIENT", "MAINMOIST_ADDRESS", "SAFE_ADDRESS"):
        if os.environ.get(env_name):
            return to_checksum_address(os.environ[env_name])
    return to_checksum_address(MAINMOIST_ADDRESS)


def main() -> None:
    load_dotenv(ROOT / ".env")
    parser = argparse.ArgumentParser(description="Build and optionally broadcast an L2-to-L1 bridge transaction.")
    parser.add_argument("--provider", default="relay", choices=["relay", "lifi", "rhinofi"], help="Bridge quote provider")
    parser.add_argument("--from-chain", required=True, help="Source chain slug/id, e.g. base, arb, bnb")
    parser.add_argument("--to-chain", default="eth", help="Destination chain slug/id, defaults to eth")
    parser.add_argument("--from-token", default="eth", help="Source token symbol/address, defaults to eth/native")
    parser.add_argument("--to-token", default="eth", help="Destination token symbol/address, defaults to eth/native")
    parser.add_argument("--amount-wei", required=True, help="Amount in smallest units")
    parser.add_argument("--amount", help="Decimal token amount; mainly for Rhino.fi, overrides --amount-wei conversion")
    parser.add_argument("--from-address", help="Sender address or domain account alias; defaults to BRIDGE_FROM_ADDRESS/MAINMOIST_ADDRESS")
    parser.add_argument("--to-address", help="L1 recipient address or domain account alias; defaults to BRIDGE_TO_L1_RECIPIENT/MAINMOIST_ADDRESS/SAFE_ADDRESS")
    parser.add_argument("--key-env", default="DEPLOYER_PRIVATE_KEY", help="Private-key env for sender/broadcast")
    parser.add_argument("--slippage", default="0.005")
    parser.add_argument("--order", default="CHEAPEST", choices=["CHEAPEST", "FASTEST"])
    parser.add_argument("--integrator", default="debndni")
    parser.add_argument("--allow-bridges", help="Comma-separated LI.FI bridge keys")
    parser.add_argument("--deny-bridges", help="Comma-separated LI.FI bridge keys")
    parser.add_argument("--relay-referrer", help="Optional Relay referrer identifier")
    parser.add_argument("--amount-native", default="0", help="Rhino.fi destination native gas boost amount")
    parser.add_argument("--refund-address", help="Rhino.fi refund address")
    parser.add_argument("--rhino-mode", default="receive", choices=["pay", "receive"], help="Rhino.fi quote mode")
    parser.add_argument("--webhook-url", help="Rhino.fi bridge status webhook URL")
    parser.add_argument("--domain", default=os.environ.get("BRIDGE_DOMAIN", DEFAULT_DOMAIN_NAME), help="Human domain label for logs")
    parser.add_argument(
        "--layerzero-executor",
        "--layer0-executor",
        dest="layerzero_executor",
        default=os.environ.get("LAYERZERO_EXECUTOR_ADDRESS") or os.environ.get("LAYER0_EXECUTOR_ADDRESS"),
        help="Optional LayerZero executor address to attach to domain metadata",
    )
    parser.add_argument("--broadcast", action="store_true")
    args = parser.parse_args()

    sender = default_sender(args)
    recipient = default_recipient(args)
    from_chain = chain_id(args.from_chain)

    if args.provider == "relay":
        quote = build_relay_quote(args, sender, recipient)
        summary = summarize_relay_quote(quote)
    elif args.provider == "rhinofi":
        quote, rhino_config, rhino_chain_in, rhino_token_in = build_rhino_quote(args, sender, recipient)
        summary = summarize_rhino_quote(quote, rhino_config, rhino_chain_in, rhino_token_in)
    else:
        quote = build_lifi_quote(args, sender, recipient)
        summary = summarize_quote(quote)
    event = {
        "type": "bridge_quote",
        "provider": args.provider,
        "domain": domain_metadata(args.domain, args.layerzero_executor),
        "dry_run": not args.broadcast,
        "from": sender,
        "to": recipient,
        "summary": summary,
    }
    if args.broadcast:
        if args.provider == "rhinofi":
            raise RuntimeError("Rhino.fi broadcast is intentionally not automatic yet. Commit the quote and deposit onchain explicitly.")
        event["tx_hashes"] = (
            broadcast_relay_quote(quote, args.key_env, from_chain, sender)
            if args.provider == "relay"
            else broadcast_lifi_quote(quote, args.key_env, from_chain, sender)
        )
        if args.provider == "lifi":
            event["status_urls"] = [f"https://explorer.li.fi/tx/{tx_hash}" for tx_hash in event["tx_hashes"]]
    append_log(event)
    print(json.dumps(event, indent=2))


if __name__ == "__main__":
    main()
