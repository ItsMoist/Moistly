#!/usr/bin/env bash
set -euo pipefail

: "${DCC3:?set DCC3 account address}"

# Optional RPC envs. Only configured chains are inspected.
# ETH_RPC_URL BASE_RPC_URL ARB_RPC_URL OP_RPC_URL

ACCOUNT_SLOT=$(cast keccak 'moistly.storage.Moist7702Account.v2')
EIP1967_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc

inspect_chain() {
  local name="$1" rpc="$2" usdc="$3"
  [[ -z "$rpc" ]] && return 0

  echo "=== $name ==="
  code=$(cast code "$DCC3" --rpc-url "$rpc")
  native=$(cast balance "$DCC3" --rpc-url "$rpc")
  usdc_bal=$(cast call "$usdc" 'balanceOf(address)(uint256)' "$DCC3" --rpc-url "$rpc" 2>/dev/null || echo unavailable)
  account_slot=$(cast storage "$DCC3" "$ACCOUNT_SLOT" --rpc-url "$rpc" 2>/dev/null || echo unavailable)
  eip1967=$(cast storage "$DCC3" "$EIP1967_SLOT" --rpc-url "$rpc" 2>/dev/null || echo unavailable)

  echo "account:                $DCC3"
  echo "native balance:         $native"
  echo "USDC raw balance:       $usdc_bal"
  echo "7702 account slot:      $account_slot"
  echo "EIP-1967 impl slot:     $eip1967"
  echo "code:                   $code"

  if [[ "$code" =~ ^0xef0100([0-9a-fA-F]{40})$ ]]; then
    echo "delegation type:        EIP-7702"
    echo "delegated implementation: 0x${BASH_REMATCH[1]}"
  elif [[ "$eip1967" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
    echo "delegation type:        ERC-1967-style proxy"
  else
    echo "delegation type:        EOA / non-7702 / non-1967"
  fi
  echo
}

inspect_chain ethereum "${ETH_RPC_URL:-}" 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
inspect_chain base     "${BASE_RPC_URL:-}" 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
inspect_chain arbitrum "${ARB_RPC_URL:-}" 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
inspect_chain optimism "${OP_RPC_URL:-}" 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85
