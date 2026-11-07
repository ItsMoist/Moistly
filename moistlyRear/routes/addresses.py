import json
import re
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import urlopen

from flask import Blueprint, jsonify, render_template

from src.etherscan_workflow_monitor import ETHERSCAN_API, etherscan_key


addresses = Blueprint("addresses", __name__, url_prefix="/addresses")
CHAINS = {1: "Ethereum", 8453: "Base", 42161: "Arbitrum One"}
ADDRESS_PATTERN = re.compile(r"0x[0-9a-fA-F]{40}")


@addresses.get("/")
def index():
    return render_template("addresses.html", chains=CHAINS)


@addresses.get("/history/<int:chain_id>/<address>")
def history(chain_id, address):
    if chain_id not in CHAINS or not ADDRESS_PATTERN.fullmatch(address):
        return jsonify(error="Choose a supported chain and a valid EVM address."), 400

    key = etherscan_key()
    if not key:
        return jsonify(error="Set ETHERSCAN_API_KEY on the Moistly server to load history."), 503

    query = urlencode({
        "chainid": chain_id,
        "module": "account",
        "action": "txlist",
        "address": address,
        "page": 1,
        "offset": 25,
        "sort": "desc",
        "apikey": key,
    })
    try:
        with urlopen(f"{ETHERSCAN_API}?{query}", timeout=10) as response:
            payload = json.load(response)
    except (URLError, OSError, ValueError):
        return jsonify(error="The transaction provider is unavailable. Try again shortly."), 502

    if isinstance(payload, dict):
        rows = payload.get("result")
        if payload.get("status") == "0" and payload.get("message") == "No transactions found" and rows == []:
            return jsonify(transactions=[])
        if payload.get("status") == "1" and isinstance(rows, list) and all(isinstance(row, dict) for row in rows):
            fields = ("hash", "from", "to", "timeStamp", "blockNumber", "isError", "value")
            return jsonify(transactions=[{field: row.get(field, "") for field in fields} for row in rows])

    return jsonify(error="Etherscan rejected the history request. Check API access for this chain."), 502
