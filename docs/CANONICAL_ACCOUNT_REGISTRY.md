# Canonical Account Registry Architecture

## Decision

Moistly should present one canonical account-identity model to applications and indexers, while keeping factory/deployment provenance as a separate concern. Do not merge deployed contracts or migrate storage until their source, ABI, owner, and per-chain addresses have been verified.

This change is an architecture specification. It does not claim that a canonical on-chain registry already exists, and it does not authorize a deployment or migration.

## Responsibilities

### Canonical account identity

The canonical model answers: "Which account belongs to which verified Moistly/DCC3 identity, on which chain, and what account kind is it?"

Each deployment record should include, at minimum:

- `chainId`
- `account`
- `accountKind` (e.g. Kernel/ERC-7579, Safe/ERC-4337, ERC-7702, ERC-6551, EOA, or unknown)
- `identity` / DCC3 reference
- verification status and evidence source
- optional provider hint (Privy, thirdweb, ZeroDev, or other)
- discovery timestamp and last-verified block

A provider hint is metadata, not proof of ownership. Do not infer control of an account merely because it was created by a known factory or appears in a provider's records.

### Factory/deployment registry

The existing `Moist2FactoryRegistry` address previously documented for Base and Arbitrum is:

`0x9Cf0CC6bF329eBfD60B6E31D0cf42f81A3dFA20a`

Keep this component responsible for factory/version/deployment provenance, including deterministic deployment parameters. Treat this address as a deployment reference to verify on-chain, not as proof that it is the canonical account-identity registry.

Factory records should be linked to canonical account records by `chainId + account` and, where available, factory/version/salt/deployment transaction. Do not make the identity registry depend on a single factory: Privy and thirdweb may use different factories, and existing accounts may predate registry adoption.

### Discovery and verification

Use Alchemy and provider-specific sources to discover candidates, then verify them on-chain. Index these signals separately:

1. Factory deployment events / deployment transactions.
2. Account code and implementation information.
3. Kernel or ERC-7579 interfaces and module lifecycle.
4. Provider metadata, when available.
5. An explicit identity proof or owner-authorized registration.

An implementation-slot match alone is not sufficient to label an account as Kernel or prove ownership. Alchemy history is not a complete global account directory.

### ENS / CCIP-Read

ENS and CCIP-Read should resolve identity from the canonical account model or a signed, verifiable index of it. Keep gateway operation and proof/signature validation separate from registry storage. The gateway must not be treated as authoritative merely because it returns an account record.

### Executor module installation

Registry discovery must never automatically install a module. Before installation, independently verify:

- account implementation and supported Kernel/ERC-7579 version;
- module type and install/uninstall hooks;
- trusted MoistExecutor proxy address and configuration;
- account-specific authorization and simulation result.

Installation requires an explicit authorized account signature/transaction.

## Migration plan

1. Inventory the deployed account registry candidates on each target chain. Record address, bytecode hash, verified source/ABI, owner/admin, and relevant read/write methods.
2. Inventory `Moist2FactoryRegistry` deployments and determine whether any existing account identity mappings already live there or in another contract.
3. Define a shared read interface only after the deployed ABIs are known. Prefer a facade/indexer API first if a new on-chain contract would duplicate existing storage.
4. Backfill candidate account records from factory events, provider data, and Alchemy. Mark candidates unverified until ownership/identity is established.
5. Add dual-read comparison and tests; do not change ENS resolver/gateway pointers during backfill.
6. If an on-chain canonical registry is needed, deploy it as a new version, migrate records with explicit authorization, and preserve compatibility with existing resolver clients.
7. Switch consumers to the canonical read interface only after cross-chain parity and rollback procedures are tested.

## Acceptance criteria

- One query can enumerate indexed account deployments for a verified identity across supported chains.
- Records distinguish discovered, deployed, and identity-verified states.
- Factory provenance is preserved without requiring all accounts to share one factory.
- Provider hints do not confer ownership.
- Existing registry addresses, storage, ENS resolver pointers, and deployed contracts remain unchanged until a reviewed migration is approved.
- Executor installation targets are emitted as a reviewable list and are never executed by discovery code.
