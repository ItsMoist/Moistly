#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   RPC_URL
#   DCC3                         account address (the account identity)
#   SALT                         exact bytes32 factory salt retained for account lineage
# Optional env:
#   PRIVATE_KEY                  deployer key for the implementation/factory tx
#   FACTORY                      deterministic factory address
#   IMPLEMENTATION               already-deployed implementation address
#
# This script deliberately separates:
#   DCC3 account identity
#   EIP-7702 delegation mechanism
#   Moist7702AccountV2 implementation

: "${RPC_URL:?set RPC_URL}"
: "${DCC3:?set DCC3}"
: "${SALT:?set the exact retained bytes32 SALT; do not use an abbreviated value}"

FACTORY="${FACTORY:-0xA8Ce4524c53D038d68E75Ff52C995961599E22d5}"

if [[ -z "${IMPLEMENTATION:-}" ]]; then
  : "${PRIVATE_KEY:?set PRIVATE_KEY to deploy implementation}"
  BYTECODE=$(forge inspect contracts/Moist7702AccountV2.sol:Moist7702AccountV2 bytecode)
  INIT_CODE_HASH=$(cast keccak "$BYTECODE")
  echo "implementation initCodeHash: $INIT_CODE_HASH"
  echo "factory: $FACTORY"
  echo "salt:    $SALT"

  TX=$(cast send "$FACTORY" \
    "deploy(bytes32,bytes)(address)" \
    "$SALT" "$BYTECODE" \
    --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --json | jq -r .transactionHash)
  echo "deployment tx: $TX"
  cast receipt "$TX" --rpc-url "$RPC_URL"
  echo "Set IMPLEMENTATION to the deployed address emitted by the factory, then rerun."
  exit 0
fi

echo "DCC3 account:        $DCC3"
echo "7702 implementation: $IMPLEMENTATION"
echo "factory:             $FACTORY"
echo "factory salt:        $SALT"
echo "implementation code: $(cast code "$IMPLEMENTATION" --rpc-url "$RPC_URL")"
echo "DCC3 code before authorization: $(cast code "$DCC3" --rpc-url "$RPC_URL")"
echo
cat <<EOF
EIP-7702 authorization required from the DCC3 signer:
  account:        $DCC3
  implementation: $IMPLEMENTATION

After broadcasting the type-0x04 authorization transaction, verify:
  cast code $DCC3 --rpc-url '$RPC_URL'

Expected code form:
  0xef0100<20-byte implementation>

Then initialize deterministic account metadata by making a SELF-CALL from DCC3:
  initializeAccount(address,bytes32,address)
  initialOwner     = $DCC3
  factorySalt      = $SALT
  verifyingAccount = $DCC3
EOF
