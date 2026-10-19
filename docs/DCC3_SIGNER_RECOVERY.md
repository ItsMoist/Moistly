# DCC3 signer authorization — multichain read-only audit

This audit inventories known addresses on Ethereum (1), Arbitrum (42161), Optimism (10), Polygon PoS (137), and Base (8453). It **does not** grant or restore signer permissions.

## Known identities
- DCC3: `0x75e732608Bc17B23D01f01728562Ee844196DCC3`
- Base account candidate: `0x8e351774b73248e98adc053bf30a5e7d5c2105c7`
- Factory candidate: `0x2Dfcc7415D89af828cbef005F0d072D8b3F23183`
- Base CREATE helper: `0x647dd07eA1c463F1B7c0FcaaC1A0858668FedC0d`
- EntryPoint v0.7: `0x0000000071727De22E5E9d8BAf0edAc6f37da032`

The account/factory/helper are confirmed on Base from earlier checks; **do not assume the same addresses are deployed on other chains**. The Base account exposes ERC-1271 and reports itself via `owner()`. Neither establishes DCC3 signer/operator authority.

## Run locally in Cursor

Install Foundry, configure these environment variables in your local shell (do not commit secrets), then run:

```bash
export ETH_RPC_URL='https://YOUR_ETH_RPC'
export ARB_RPC_URL='https://YOUR_ARB_RPC'
export OP_RPC_URL='https://YOUR_OP_RPC'
export POLY_RPC_URL='https://YOUR_POLYGON_RPC'
export BASE_RPC_URL='https://YOUR_BASE_RPC'
bash scripts/audit-dcc3-signers.sh
```

Results are written to `reports/dcc3-auth-audit.jsonl`. Each network is chain-ID checked. Missing RPCs are explicitly reported. Presence of code is **not** proof of ownership. Failed ABI reads are omitted, not treated as authorization failures.

## Authorization recovery gate

1. Identify exact deployed account source/ABI and storage layout per chain.
2. Determine active validator, recovery authority, and required signature envelope.
3. Request a fresh chain/account-bound challenge signature from DCC3 in a trusted local wallet UI.
4. Check ERC-1271 with correct digest/signature encoding or simulate ERC-4337 validation; a raw EOA signature is not sufficient proof.
5. If DCC3 is not authorized, prepare a recovery transaction only through an already-authorized recovery path.
6. Review simulation, calldata, target, chain ID, and signers before any broadcast.

Never call `initialize`, `transferOwnership`, install a validator, or revoke a delegate speculatively. Gains `MoistTrader.operators` is a **different** permission system from ERC-4337 smart-account signer authority.

## Current status
Read-only inventory script prepared. No local RPC run, signature validation, or recovery transaction has been performed.
