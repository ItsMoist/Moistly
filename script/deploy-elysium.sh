#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NETWORK="${1:-elysium-testnet}"
case "$NETWORK" in
  elysium|elysium-mainnet)
    RPC_URL="${ELYSIUM_RPC:-https://rpc.elysium.kinetiq.xyz}"
    CHAIN_ID=99901
    ;;
  elysium-testnet)
    RPC_URL="${ELYSIUM_TESTNET_RPC:-https://testnet-rpc.elysium.kinetiq.xyz}"
    CHAIN_ID=99801
    ;;
  *)
    echo "Usage: $0 [elysium-testnet|elysium]" >&2
    exit 1
    ;;
esac

if [[ -z "${DEPLOYER_PRIVATE_KEY:-}" ]]; then
  echo "DEPLOYER_PRIVATE_KEY is required" >&2
  exit 1
fi

OWNER="${STORAGE_BEACON_OWNER:-$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")}"
export STORAGE_BEACON_OWNER="$OWNER"
export DEPLOYER_PRIVATE_KEY

echo "Deploying storage clone stack to $NETWORK (chain $CHAIN_ID)"
echo "RPC: $RPC_URL"
echo "Owner: $OWNER"
echo "Deployer balance: $(cast balance "$OWNER" --rpc-url "$RPC_URL") wei"

forge script script/DeployStorageClones.s.sol:DeployStorageClones \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  -vvv

echo "Broadcast artifacts under broadcast/"
