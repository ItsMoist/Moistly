#!/usr/bin/env bash
set -euo pipefail

# Deploy Moist7702Verifier173 using secrets from the caller's local environment.
# Expected variables:
#   ETH_RPC_URL
#   PRIVATE_KEY
# Optional:
#   ETHERSCAN_API_KEY

: "${ETH_RPC_URL:?ETH_RPC_URL must be set}"
: "${PRIVATE_KEY:?PRIVATE_KEY must be set}"

CONTRACT="contracts/Moist7702Verifier173.sol:Moist7702Verifier173"
DCC3="0x75e732608Bc17B23D01f01728562Ee844196DCC3"
ERC173_ID="0x7f5828d0"

forge build

DEPLOY_ARGS=(
  forge create "$CONTRACT"
  --rpc-url "$ETH_RPC_URL"
  --private-key "$PRIVATE_KEY"
  --broadcast
)

if [[ -n "${ETHERSCAN_API_KEY:-}" ]]; then
  DEPLOY_ARGS+=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
fi

OUTPUT="$(${DEPLOY_ARGS[@]})"
printf '%s\n' "$OUTPUT"

IMPLEMENTATION="$(printf '%s\n' "$OUTPUT" | awk '/Deployed to:/ {print $3}' | tail -n1)"
if [[ -z "$IMPLEMENTATION" ]]; then
  echo "Could not parse deployed implementation address." >&2
  exit 1
fi

echo "Implementation: $IMPLEMENTATION"
echo "Canonical 7702 EOA: $DCC3"

OWNER="$(cast call "$IMPLEMENTATION" 'owner()(address)' --rpc-url "$ETH_RPC_URL")"
SUPPORTS_173="$(cast call "$IMPLEMENTATION" 'supportsInterface(bytes4)(bool)' "$ERC173_ID" --rpc-url "$ETH_RPC_URL")"
CANONICAL_ON_IMPL="$(cast call "$IMPLEMENTATION" 'isCanonicalDCC3Context()(bool)' --rpc-url "$ETH_RPC_URL")"
OWNER_SLOT="$(cast call "$IMPLEMENTATION" 'ownerStorageSlot()(bytes32)' --rpc-url "$ETH_RPC_URL")"

echo "implementation.owner(): $OWNER"
echo "implementation.supportsInterface(ERC-173): $SUPPORTS_173"
echo "implementation.isCanonicalDCC3Context(): $CANONICAL_ON_IMPL (expected false)"
echo "owner storage slot: $OWNER_SLOT"

echo
echo "Next step: authorize DCC3 under EIP-7702 to delegate to:"
echo "  $IMPLEMENTATION"
echo
echo "After the 7702 authorization is mined, verify through DCC3 itself:"
echo "  cast call $DCC3 'owner()(address)' --rpc-url \"$ETH_RPC_URL\""
echo "  cast call $DCC3 'supportsInterface(bytes4)(bool)' $ERC173_ID --rpc-url \"$ETH_RPC_URL\""
echo "  cast call $DCC3 'isCanonicalDCC3Context()(bool)' --rpc-url \"$ETH_RPC_URL\""
echo "  cast call $DCC3 'domainSeparatorV4()(bytes32)' --rpc-url \"$ETH_RPC_URL\""
