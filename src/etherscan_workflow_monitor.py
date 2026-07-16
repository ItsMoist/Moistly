#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import signal
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT / "logs" / "etherscan-workflow-monitor.jsonl"
OUT_PATH = ROOT / "logs" / "etherscan-workflow-monitor.out"
PID_PATH = ROOT / "logs" / "etherscan-workflow-monitor.pid"
STATE_PATH = ROOT / "logs" / "etherscan-workflow-monitor-state.json"
DEPLOYMENT_PATH = ROOT / "logs" / "storage-create2-recreate.json"
FOUNDRY_DEPLOYMENTS_PATH = ROOT / "logs" / "foundry-deployer-ethereum-contracts.json"
FOUNDRY_KEYSTORE_DIR = Path.home() / ".foundry" / "keystores"
OWS_WALLETS_DIR = Path.home() / ".ows" / "wallets"
OWS_SMART_WALLETS_DIR = Path.home() / ".ows" / "smart-wallets"
ETHERSCAN_API = "https://api.etherscan.io/v2/api"

RUNNING = True


BASE_WATCH: dict[str, str] = {
    "0x1b4C289c4f6e0565f1E432654254485c490679e9": "deployer_owner",
    "0x75e732608Bc17B23D01f01728562Ee844196DCC3": "dcc3",
    "0xdadB0d80178819F2319190D340ce9A924f783711": "discovery_seed_sender_e981",
    "0x9F24a605BA20A884826306fb8A6068Db2C16b1a5": "discovery_seed_receiver_e981",
    "0x37A974B2b3AaC406Aa478778a9070426b4a4f21E": "storage_clone_original",
    "0x7a07b27a9A30b9cFeC41199507A53655154EDc7a": "storage_clone_recreated_old_impl",
    "0xF7811759646BC23B96a226f2731616B5D982Fa73": "storage_clone_v2_zero_salt",
    "0xD3e2Be909A3f17777095E4ACdE680E9D488CD766": "storage_clone_v2_salted",
    "0x7Da4C35F10319E1e1D549cE05573a192C523bb3C": "storage_clone_v2_defi_owner_gated",
    "0x7DAF91DFe55FcAb363416A6E3bceb3Da34ff1d30": "storage_impl_original",
    "0x99174d8F0971244267853b13205F50C661414d22": "storage_impl_v2_zero_salt",
    "0xc8789c4F55BC957C981D3F7B388E1878fC796E0E": "storage_impl_v2_salted",
    "0x92ACD09a9e95405C90508164A188eb02A3cd837b": "storage_impl_v2_defi_owner_gated",
    "0x00000000000000447e69651d841bD8D104Bed493": "delegate_registry",
    "0x390aFa951EF526bbb36Fb7489Fb2FABB846ebCC8": "active_nft_delegate_proxy",
    "0x62bbaf41c131a3282b1ab243893b0d7f15e5daee": "nested_safe_proxy_seen_from_dcc3",
    "0x9641d764fc13c8b624c04430c7356c1c7c8102e2": "multisend_seen_from_dcc3_flow",
    "0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67": "proxy_factory_seen_from_dcc3_flow",
    "0x41675C099F32341bf84BFc5382aF534df5C7461a": "safe_singleton_seen_from_dcc3_flow",
    "0x1b5cC0c7bbb2B7b15b70aBCa9faBD29B616c0666": "proxy_created_from_dcc3_flow",
    "0xBD89A1CE4DDe368FFAB0eC35506eEcE0b1fFdc54": "setup_target_seen_from_dcc3_flow",
    "0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99": "fallback_handler_seen_from_dcc3_flow",
    "0x29fcb43b46531bca003ddc8fcb67ffe91900c762": "setup_module_seen_from_dcc3_flow",
    "0x2f2c68aC45f2ee77c5dd464B0ccaB52a9955CD13": "alert_counterparty_0001_eth",
    "0x4231B2f83CB7C833Db84ceC0cEAAa9959f051374": "large_balance_eoa_observed",
    "0x9fc3da866e7df3a1c57ade1a97c9f00a70f010c8": "funded_eoa_observed",
    "0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7": "ZkLighterContract",
    "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": "USDCContract",
}

HIGH_VOLUME_ADDRESSES = {
    "0x00000000000000447e69651d841bd8d104bed493",
    "0x9641d764fc13c8b624c04430c7356c1c7c8102e2",
    "0x4e1dcf7ad4e460cfd30791ccc4f9c8a4f820ec67",
    "0x41675c099f32341bf84bfc5382af534df5c7461a",
    "0xbd89a1ce4dde368ffab0ec35506eece0b1ffdc54",
    "0xfd0732dc9e303f09fcef3a7388ad10a83459ec99",
    "0x29fcb43b46531bca003ddc8fcb67ffe91900c762",
    "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--sync-local-only", action="store_true")
    parser.add_argument("--poll-seconds", type=float, default=float(os.environ.get("ETHERSCAN_MONITOR_POLL_SECONDS", "45")))
    parser.add_argument("--offset", type=int, default=int(os.environ.get("ETHERSCAN_MONITOR_OFFSET", "25")))
    args = parser.parse_args()

    load_dotenv()
    state = load_state()
    watch = load_watch(state)
    if args.sync_local_only:
        save_state(state)
        print(
            f"synced local inventory addresses={len(state.get('local_inventory', {}))} "
            f"watch_count={len(watch)} state={STATE_PATH}",
            flush=True,
        )
        return

    api_key = etherscan_key()
    if not api_key:
        raise RuntimeError("Set ETHERSCAN_API_KEY in .env or environment.")

    LOG_PATH.parent.mkdir(exist_ok=True)
    PID_PATH.write_text(str(os.getpid()) + "\n")
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    append_log({"type": "monitor_start", "ts": now(), "watch_count": len(watch), "poll_seconds": args.poll_seconds})
    print(f"etherscan workflow monitor watching {len(watch)} addresses log={LOG_PATH}", flush=True)

    while RUNNING:
        try:
            poll(api_key, watch, state, args.offset)
            save_state(state)
        except Exception as exc:
            append_log({"type": "monitor_error", "ts": now(), "error_type": type(exc).__name__, "error": str(exc)})
            print(f"monitor error {type(exc).__name__}: {exc}", flush=True)
        if args.once:
            break
        time.sleep(args.poll_seconds)


def stop(_signum: int, _frame: object) -> None:
    global RUNNING
    RUNNING = False


def load_dotenv() -> None:
    env_path = ROOT / ".env"
    if not env_path.exists():
        return
    for raw in env_path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("'\""))


def etherscan_key() -> str:
    return os.environ.get("ETHERSCAN_API_KEY") or os.environ.get("ETHERSCAN_KEY") or os.environ.get("ETHERSCAN_TOKEN") or ""


def load_watch(state: dict[str, Any] | None = None) -> dict[str, dict[str, Any]]:
    watch: dict[str, dict[str, Any]] = {}
    state_data = state if state is not None else {}
    for address, label in BASE_WATCH.items():
        add_watch(watch, address, label, "static")

    if DEPLOYMENT_PATH.exists():
        try:
            data = json.loads(DEPLOYMENT_PATH.read_text())
        except json.JSONDecodeError:
            data = {}
        add_watch(watch, data.get("original_clone"), "artifact_original_clone", str(DEPLOYMENT_PATH))
        add_watch(watch, data.get("predicted_address"), "artifact_latest_clone", str(DEPLOYMENT_PATH))
        add_watch(watch, data.get("implementation"), "artifact_latest_implementation", str(DEPLOYMENT_PATH))
        add_watch(watch, data.get("owner"), "artifact_owner", str(DEPLOYMENT_PATH))

    extra = os.environ.get("ETHERSCAN_MONITOR_ADDRESSES", "")
    for item in extra.split(","):
        item = item.strip()
        if item:
            add_watch(watch, item, "env_extra", ".env")

    for address, metadata in state_data.get("discovered_watch", {}).items():
        labels = metadata.get("labels") or ["discovered"]
        for label in labels:
            add_watch(watch, address, label, "state.discovered_watch")

    sync_local_inventory(state_data, watch)

    return dict(sorted(watch.items()))


def add_watch(watch: dict[str, dict[str, Any]], address: str | None, label: str, source: str) -> None:
    if not address or not isinstance(address, str) or not address.startswith("0x") or len(address) != 42:
        return
    key = address.lower()
    row = watch.setdefault(key, {"address": address, "labels": [], "sources": []})
    if label not in row["labels"]:
        row["labels"].append(label)
    if source not in row["sources"]:
        row["sources"].append(source)


def sync_local_inventory(state: dict[str, Any], watch: dict[str, dict[str, Any]]) -> None:
    inventory: dict[str, dict[str, Any]] = {}
    errors: list[dict[str, str]] = []

    collect_foundry_keystores(inventory, errors)
    collect_ows_wallets(inventory, errors)
    collect_ows_smart_wallets(inventory, errors)
    collect_foundry_deployment_artifacts(inventory, errors)

    state["local_inventory"] = dict(sorted(inventory.items()))
    if errors:
        state["local_inventory_errors"] = errors
    else:
        state.pop("local_inventory_errors", None)

    for address, metadata in inventory.items():
        for label in metadata.get("labels", []):
            add_watch(watch, address, label, "state.local_inventory")


def collect_foundry_keystores(inventory: dict[str, dict[str, Any]], errors: list[dict[str, str]]) -> None:
    for path in safe_glob(FOUNDRY_KEYSTORE_DIR, "*", errors):
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text())
        except Exception as exc:
            errors.append({"source": str(path), "error": f"{type(exc).__name__}: {exc}"})
            continue
        address = normalize_address(data.get("address"))
        if address:
            add_inventory_address(inventory, address, "foundry_keystore", str(path))


def collect_ows_wallets(inventory: dict[str, dict[str, Any]], errors: list[dict[str, str]]) -> None:
    for path in safe_glob(OWS_WALLETS_DIR, "*.json", errors):
        try:
            data = json.loads(path.read_text())
        except Exception as exc:
            errors.append({"source": str(path), "error": f"{type(exc).__name__}: {exc}"})
            continue
        wallet_name = data.get("name") or data.get("id") or path.stem
        for account in data.get("accounts", []):
            address = normalize_address(account.get("address"))
            chain_id = str(account.get("chain_id", ""))
            if address and chain_id.startswith("eip155:"):
                add_inventory_address(
                    inventory,
                    address,
                    "ows_evm_wallet",
                    str(path),
                    {"wallet_name": wallet_name, "chain_id": chain_id},
                )


def collect_ows_smart_wallets(inventory: dict[str, dict[str, Any]], errors: list[dict[str, str]]) -> None:
    for path in safe_glob(OWS_SMART_WALLETS_DIR, "*.ows.json", errors):
        try:
            data = json.loads(path.read_text())
        except Exception as exc:
            errors.append({"source": str(path), "error": f"{type(exc).__name__}: {exc}"})
            continue
        wallet_name = data.get("name") or data.get("id") or path.stem
        for account in data.get("accounts", []):
            address = normalize_address(account.get("address"))
            chain_id = str(account.get("chain_id", ""))
            role = account.get("role") or "ows_smart_wallet_account"
            if address and chain_id.startswith("eip155:"):
                add_inventory_address(
                    inventory,
                    address,
                    f"ows_{role}",
                    str(path),
                    {"wallet_name": wallet_name, "chain_id": chain_id, "role": role},
                )
        smart_wallet = data.get("smart_wallet", {})
        for field in ("factory_address",):
            address = normalize_address(smart_wallet.get(field))
            if address:
                add_inventory_address(inventory, address, f"ows_smart_wallet_{field}", str(path))
        for address_value in smart_wallet.get("initial_privilege_addresses", []):
            address = normalize_address(address_value)
            if address:
                add_inventory_address(inventory, address, "ows_initial_privilege_address", str(path))


def collect_foundry_deployment_artifacts(
    inventory: dict[str, dict[str, Any]], errors: list[dict[str, str]]
) -> None:
    if not FOUNDRY_DEPLOYMENTS_PATH.exists():
        return
    try:
        data = json.loads(FOUNDRY_DEPLOYMENTS_PATH.read_text())
    except Exception as exc:
        errors.append({"source": str(FOUNDRY_DEPLOYMENTS_PATH), "error": f"{type(exc).__name__}: {exc}"})
        return
    add_inventory_address(inventory, normalize_address(data.get("deployer")), "foundry_deployer", str(FOUNDRY_DEPLOYMENTS_PATH))
    for contract in data.get("contracts", []):
        add_inventory_address(
            inventory,
            normalize_address(contract.get("address")),
            "foundry_deployed_contract",
            str(FOUNDRY_DEPLOYMENTS_PATH),
            {"tx_hash": contract.get("tx_hash"), "deployment_type": contract.get("deployment_type")},
        )
        add_inventory_address(inventory, normalize_address(contract.get("from")), "foundry_contract_from", str(FOUNDRY_DEPLOYMENTS_PATH))
        add_inventory_address(inventory, normalize_address(contract.get("to")), "foundry_contract_to", str(FOUNDRY_DEPLOYMENTS_PATH))


def safe_glob(directory: Path, pattern: str, errors: list[dict[str, str]]) -> list[Path]:
    try:
        if not directory.exists():
            return []
        return sorted(directory.glob(pattern))
    except Exception as exc:
        errors.append({"source": str(directory), "error": f"{type(exc).__name__}: {exc}"})
        return []


def normalize_address(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    candidate = value.strip()
    if re.fullmatch(r"[0-9a-fA-F]{40}", candidate):
        candidate = f"0x{candidate}"
    if not re.fullmatch(r"0x[0-9a-fA-F]{40}", candidate):
        return None
    return "0x" + candidate[2:].lower()


def add_inventory_address(
    inventory: dict[str, dict[str, Any]],
    address: str | None,
    label: str,
    source: str,
    extra: dict[str, Any] | None = None,
) -> None:
    if not address or address == "0x0000000000000000000000000000000000000000":
        return
    row = inventory.setdefault(address, {"address": address, "labels": [], "sources": []})
    if label not in row["labels"]:
        row["labels"].append(label)
    if source not in row["sources"]:
        row["sources"].append(source)
    if extra:
        details = row.setdefault("details", [])
        if extra not in details:
            details.append(extra)


def poll(api_key: str, watch: dict[str, dict[str, Any]], state: dict[str, Any], offset: int) -> None:
    seen = state.setdefault("seen_hashes", [])
    seen_set = set(seen)
    known = set(watch)
    for address, metadata in list(watch.items()):
        rows = etherscan_txlist(api_key, address, offset)
        for tx in reversed(rows):
            tx_hash = tx.get("hash")
            if not tx_hash or tx_hash in seen_set:
                continue
            tx_from = (tx.get("from") or "").lower()
            tx_to = (tx.get("to") or "").lower()
            if address not in (tx_from, tx_to):
                continue

            direction = "in" if tx_to == address else "out"
            counterparty = tx_from if direction == "in" else tx_to
            is_known_counterparty = counterparty in known
            if address in HIGH_VOLUME_ADDRESSES and not is_known_counterparty:
                seen.append(tx_hash)
                seen_set.add(tx_hash)
                continue
            if counterparty and not is_known_counterparty:
                add_discovered_watch(
                    state,
                    watch,
                    counterparty,
                    "discovered_counterparty",
                    tx_hash,
                )
                known.add(counterparty)
            event = {
                "type": "workflow_address_touch",
                "ts": now(),
                "watched_address": metadata["address"],
                "watched_labels": metadata["labels"],
                "direction": direction,
                "counterparty": counterparty,
                "counterparty_known": is_known_counterparty,
                "counterparty_labels": watch.get(counterparty, {}).get("labels", []),
                "tx_hash": tx_hash,
                "block_number": int(tx.get("blockNumber", "0")),
                "block_timestamp": int(tx.get("timeStamp", "0")),
                "value_wei": int(tx.get("value", "0")),
                "method_id": tx.get("methodId"),
                "function_name": tx.get("functionName"),
                "is_error": tx.get("isError"),
            }
            append_log(event)
            print(
                f"{direction} {metadata['address']} counterparty={counterparty} "
                f"value_wei={event['value_wei']} known={is_known_counterparty} tx={tx_hash}",
                flush=True,
            )
            seen.append(tx_hash)
            seen_set.add(tx_hash)
        poll_nft_transfers(api_key, watch, state, address, metadata, offset)

    if len(seen) > 2000:
        del seen[:-2000]
    trim_list(state.setdefault("seen_nft_transfers", []), 3000)
    state["last_poll_at"] = now()


def poll_nft_transfers(
    api_key: str,
    watch: dict[str, dict[str, Any]],
    state: dict[str, Any],
    address: str,
    metadata: dict[str, Any],
    offset: int,
) -> None:
    if address in HIGH_VOLUME_ADDRESSES:
        return
    seen = state.setdefault("seen_nft_transfers", [])
    seen_set = set(seen)
    known = set(watch)
    rows = etherscan_tokennfttx(api_key, address, offset)
    for tx in reversed(rows):
        tx_hash = tx.get("hash")
        contract = (tx.get("contractAddress") or "").lower()
        token_id = tx.get("tokenID") or tx.get("tokenId") or ""
        key = f"{tx_hash}:{contract}:{token_id}:{address}"
        if not tx_hash or key in seen_set:
            continue

        tx_from = (tx.get("from") or "").lower()
        tx_to = (tx.get("to") or "").lower()
        if address not in (tx_from, tx_to):
            continue

        direction = "in" if tx_to == address else "out"
        counterparty = tx_from if direction == "in" else tx_to
        if counterparty and counterparty not in known:
            add_discovered_watch(state, watch, counterparty, "discovered_nft_counterparty", tx_hash)
            known.add(counterparty)
        if contract:
            add_discovered_nft_contract(state, contract, tx)

        event = {
            "type": "workflow_nft_touch",
            "ts": now(),
            "watched_address": metadata["address"],
            "watched_labels": metadata["labels"],
            "direction": direction,
            "counterparty": counterparty,
            "counterparty_known": counterparty in known,
            "counterparty_labels": watch.get(counterparty, {}).get("labels", []),
            "nft_contract": tx.get("contractAddress"),
            "token_id": token_id,
            "token_name": tx.get("tokenName"),
            "token_symbol": tx.get("tokenSymbol"),
            "tx_hash": tx_hash,
            "block_number": int(tx.get("blockNumber", "0")),
            "block_timestamp": int(tx.get("timeStamp", "0")),
        }
        append_log(event)
        print(
            f"nft {direction} {metadata['address']} contract={event['nft_contract']} "
            f"token_id={token_id} counterparty={counterparty} tx={tx_hash}",
            flush=True,
        )
        seen.append(key)
        seen_set.add(key)


def etherscan_txlist(api_key: str, address: str, offset: int) -> list[dict[str, Any]]:
    params = {
        "chainid": "1",
        "module": "account",
        "action": "txlist",
        "address": address,
        "startblock": "0",
        "endblock": "99999999",
        "page": "1",
        "offset": str(offset),
        "sort": "desc",
        "apikey": api_key,
    }
    url = ETHERSCAN_API + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=30) as response:
        data = json.loads(response.read())
    result = data.get("result")
    if data.get("status") == "0" and result == "No transactions found":
        return []
    if not isinstance(result, list):
        raise RuntimeError(f"Etherscan txlist failed for {address}: {data.get('message')} {result}")
    return result


def etherscan_tokennfttx(api_key: str, address: str, offset: int) -> list[dict[str, Any]]:
    params = {
        "chainid": "1",
        "module": "account",
        "action": "tokennfttx",
        "address": address,
        "startblock": "0",
        "endblock": "99999999",
        "page": "1",
        "offset": str(offset),
        "sort": "desc",
        "apikey": api_key,
    }
    url = ETHERSCAN_API + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=30) as response:
        data = json.loads(response.read())
    result = data.get("result")
    if data.get("status") == "0" and result == "No transactions found":
        return []
    if not isinstance(result, list):
        raise RuntimeError(f"Etherscan tokennfttx failed for {address}: {data.get('message')} {result}")
    return result


def add_discovered_watch(
    state: dict[str, Any],
    watch: dict[str, dict[str, Any]],
    address: str,
    label: str,
    tx_hash: str,
) -> None:
    if not address or not address.startswith("0x") or len(address) != 42:
        return
    if address.lower() == "0x0000000000000000000000000000000000000000":
        return
    discovered = state.setdefault("discovered_watch", {})
    key = address.lower()
    row = discovered.setdefault(
        key,
        {"address": address, "labels": [], "first_seen_tx": tx_hash, "first_seen_at": now()},
    )
    if label not in row["labels"]:
        row["labels"].append(label)
    add_watch(watch, address, label, "state.discovered_watch")


def add_discovered_nft_contract(state: dict[str, Any], address: str, tx: dict[str, Any]) -> None:
    if not address or not address.startswith("0x") or len(address) != 42:
        return
    contracts = state.setdefault("discovered_nft_contracts", {})
    key = address.lower()
    contracts.setdefault(
        key,
        {
            "address": address,
            "token_name": tx.get("tokenName"),
            "token_symbol": tx.get("tokenSymbol"),
            "first_seen_tx": tx.get("hash"),
            "first_seen_at": now(),
        },
    )


def trim_list(items: list[Any], limit: int) -> None:
    if len(items) > limit:
        del items[:-limit]


def load_state() -> dict[str, Any]:
    if not STATE_PATH.exists():
        return {}
    return json.loads(STATE_PATH.read_text())


def save_state(state: dict[str, Any]) -> None:
    STATE_PATH.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")


def append_log(event: dict[str, Any]) -> None:
    LOG_PATH.parent.mkdir(exist_ok=True)
    with LOG_PATH.open("a") as handle:
        handle.write(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n")


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


if __name__ == "__main__":
    main()
