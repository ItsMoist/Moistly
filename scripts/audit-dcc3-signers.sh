#!/usr/bin/env bash
# Read-only multichain DCC3 smart-account reconnaissance. Requires Foundry cast.
set -euo pipefail
DCC3="0x75e732608Bc17B23D01f01728562Ee844196DCC3"
ACCOUNT="0x8e351774b73248e98adc053bf30a5e7d5c2105c7"
FACTORY="0x2Dfcc7415D89af828cbef005F0d072D8b3F23183"
HELPER="0x647dd07eA1c463F1B7c0FcaaC1A0858668FedC0d"
ENTRYPOINT="0x0000000071727De22E5E9d8BAf0edAc6f37da032"
command -v cast >/dev/null || { echo "Install Foundry: https://getfoundry.sh"; exit 1; }
mkdir -p reports
OUT="reports/dcc3-auth-audit.jsonl"
: > "$OUT"
for spec in "ethereum:1:ETH_RPC_URL" "arbitrum:42161:ARB_RPC_URL" "optimism:10:OP_RPC_URL" "polygon:137:POLY_RPC_URL" "base:8453:BASE_RPC_URL"; do
  IFS=: read -r chain expected var <<< "$spec"
  rpc="${!var:-}"
  if [[ -z "$rpc" ]]; then
    printf '{"chain":"%s","status":"missing_rpc","env":"%s"}\n' "$chain" "$var" >> "$OUT"
    continue
  fi
  actual="$(cast chain-id --rpc-url "$rpc" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    printf '{"chain":"%s","status":"chain_id_mismatch","expected":"%s","actual":"%s"}\n' "$chain" "$expected" "$actual" >> "$OUT"
    continue
  fi
  for item in "dcc3:$DCC3" "account:$ACCOUNT" "factory:$FACTORY" "helper:$HELPER" "entrypoint:$ENTRYPOINT"; do
    IFS=: read -r role addr <<< "$item"
    code="$(cast code "$addr" --rpc-url "$rpc" 2>/dev/null || true)"
    if [[ -z "$code" ]]; then state="rpc_error"
    elif [[ "$code" == "0x" || "$code" == "0x0" ]]; then state="no_code"
    else state="deployed"; fi
    printf '{"chain":"%s","role":"%s","address":"%s","status":"%s"}\n' "$chain" "$role" "$addr" "$state" >> "$OUT"
    if [[ "$role" == "account" && "$state" == "deployed" ]]; then
      for fn in "owner()(address)" "entryPoint()(address)"; do
        value="$(cast call "$addr" "$fn" --rpc-url "$rpc" 2>/dev/null || true)"
        [[ -n "$value" ]] && printf '{"chain":"%s","role":"account","read":"%s","result":"%s"}\n' "$chain" "$fn" "$value" >> "$OUT"
      done
    fi
  done
done
echo "Read-only report: $OUT"
echo "No signature verification, validator recovery, or operator authorization has been inferred."
