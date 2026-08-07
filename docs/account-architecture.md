# Moistly account architecture

## Goal

Keep account identity deterministic across Ethereum L1 and supported L2s without conflating three different concepts:

1. the implementation/singleton address,
2. the proxy/account address,
3. mutable account state.

Those can be made equal or synchronized independently.

## ERC-7702 path

An ERC-7702 account keeps the EOA address. There is no account proxy address to deploy for the EOA itself.

Deploy `Moist7702Account` at one canonical implementation address on every target chain, then authorize the EOA to delegate to that implementation. The implementation should be deployed with identical creation bytecode, through the same deterministic deployer address, with the same deployment salt.

The delegated EOA then keeps its original address on every chain. Guard configuration and other mutable state remain chain-local unless explicitly synchronized.

## Safe path

A Safe is a proxy account. To obtain the same Safe proxy address across chains:

- use the same Safe singleton address,
- use the same Safe proxy factory address,
- use the same initializer bytes,
- use the same salt nonce,
- use Safe's cross-chain-replayable `createProxyWithNonce` path, not the chain-specific deployment path.

The same Safe address does not imply the same state after deployment. Owner/module/guard changes on one chain do not automatically propagate to another chain.

## Moist account-proxy path

`MoistAccountProxyFactory` is the reserved account-proxy factory for non-Safe deterministic account proxies.

### Factory reservation

The factory itself must be deployed at the same address on every target chain before relying on cross-chain proxy-address parity. Reserve one deterministic deployment salt for the factory and never reuse it for any other contract family.

Recommended factory deployment salt namespace:

```text
keccak256("moistly.account.proxy.factory.v1")
```

Deploy the factory through the same canonical CREATE2 deployer on every chain with identical factory creation bytecode.

### Account salt derivation

The factory derives account salts as:

```solidity
keccak256(abi.encode(
    keccak256("moistly.account.proxy.factory.v1"),
    owner,
    nonce
))
```

`block.chainid` is intentionally excluded. Including it would force different CREATE2 addresses across chains.

### Nonce rules

- `deployNext(...)` uses the next unused sequential nonce.
- `deployAtNonce(nonce, ...)` consumes exactly that nonce and leaves lower unused nonce slots available.
- Sequential deployment skips explicitly consumed nonce slots.
- `nonceUsed(owner, nonce)` is the on-chain source of truth for whether an owner/nonce salt has been consumed on that chain.
- `predictAddress(owner, nonce, implementation, initData)` must be called with byte-identical `implementation` and `initData` on every chain when the same proxy address is required.

The nonce belongs to the owner namespace, not to the chain. For a cross-chain account reservation, record the tuple:

```text
owner
nonce
implementation
keccak256(initData)
salt
initCodeHash
predictedProxy
factoryAddress
```

and reuse that exact tuple on every target chain.

## Address parity invariant

For `MoistAccountProxyFactory`, the CREATE2 proxy address is identical across chains if and only if all of these inputs are identical:

```text
factory address
owner
nonce
implementation address
initData bytes
MoistAccountProxy creation bytecode
```

The factory computes:

```text
salt = keccak256(DOMAIN_SALT, owner, nonce)
initCodeHash = keccak256(MoistAccountProxy.creationCode ++ abi.encode(implementation, initData))
proxy = keccak256(0xff ++ factory ++ salt ++ initCodeHash)[12:]
```

## State synchronization

Deterministic address parity does not synchronize state.

Use the ENS/EAS/CCIP-Read layer for cross-chain identity and state assertions rather than attempting to make arbitrary storage writes magically identical. The intended higher-level flow is:

```text
ENS on L1
  -> CCIP-Read resolver
  -> gateway/proof service
  -> L2 identity registry
  -> EAS attestations
  -> ERC-7702 EOA / Safe / deterministic account proxy / ERC-6551 account
```

## Security invariants

- Never include `chainid` in a salt intended to reproduce an address cross-chain.
- Never assume matching account addresses imply matching state.
- Never reuse a nonce/salt after `nonceUsed(owner, nonce)` becomes true.
- Never change proxy constructor bytecode while expecting old predictions to remain valid.
- Never deploy account proxies through a factory address that differs across target chains when address parity matters.
- ERC-7702 delegation gives the delegate implementation authority in the EOA execution context; only audited delegate code should be authorized.
