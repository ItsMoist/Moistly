# Moistly

Moistly is a multichain DeFi toolkit: Foundry contracts, Python ops scripts, and the `moistlyRear` Flask service.

## Elysium

[Elysium](https://elysium.kinetiq.xyz/docs/what-is-elysium) is Kinetiq’s Arbitrum Orbit L2 for Hyperliquid. It settles to HyperEVM, uses **HYPE** as gas, and speaks standard EVM JSON-RPC.

| Network | Chain ID | Settles to | Public RPC |
| --- | --- | --- | --- |
| Elysium mainnet | `99901` | HyperEVM `999` | `https://rpc.elysium.kinetiq.xyz` |
| Elysium testnet | `99801` | HyperEVM testnet `998` | `https://testnet-rpc.elysium.kinetiq.xyz` |

Canonical mainnet tokens:

| Token | Address |
| --- | --- |
| USDC | `0xb47c4C8F73F009CC0C0d3f92B388d13E293F0B65` |
| WHYPE | `0xbA876237B0F021A6c6D852d6c26E107997cC5E81` |
| Gateway router | `0x61EbbC3A29f1970aF2Ce862bA9c5364832E14d17` |

### Configure RPC

Optional env vars (public RPC is used when unset):

```bash
export ALCHEMY_ELYSIUM_RPC="https://elysium-mainnet.g.alchemy.com/v2/<key>"
export ALCHEMY_ELYSIUM_TESTNET_RPC="https://elysium-testnet.g.alchemy.com/v2/<key>"
# or
export ELYSIUM_RPC="https://rpc.elysium.kinetiq.xyz"
export ELYSIUM_TESTNET_RPC="https://testnet-rpc.elysium.kinetiq.xyz"
```

### Check connectivity

```bash
python -m src.elysium ping
python -m src.elysium ping --network elysium-testnet
python -m src.elysium contracts
python chain_checks.py
```

`StorageV2` resolves `usdc()` / `weth()` on chain id `99901` to Elysium USDC and WHYPE. Bridge aliases in `src/bridge_to_l1.py` accept `elysium`, `elysium-testnet`, and `hyperevm`.

### Optimized storage clones

Deploy once per chain:

1. `StorageV2` (implementation)
2. `StorageBeacon(implementation, owner)` — your upgrade key
3. `StorageCloneFactory(beacon)` — CREATE2 factory

Then mint clones in one transaction (owner baked into `PROXY_OWNER_SLOT`, no separate init):

```solidity
factory.deployForAccount(owner, accountId);
// or
factory.deploy(owner, salt);
factory.predict(owner, salt); // CREATE2 address
```

Proxy changes vs the old clone path:

- No `forge-std` / console in production proxies
- `receive()` forwards to the implementation
- Beacon `implementation()` resolved with a tight `staticcall`
- Dead `call` removed from `ERC1967Proxy` fallback
- Optional owner-at-construction removes `initializeProxyOwner` for new clones

### Token linkage (Elysium ↔ HyperEVM)

```bash
python -m src.token_linkage verify-usdc
python -m src.token_linkage resolve --token 0xb47c… --from-chain elysium
python -m src.token_linkage resolve --token 0xb883… --from-chain hyperevm
python -m src.token_linkage known
```

| Class | How Moistly resolves it |
| --- | --- |
| Canonical representation | `l1Address()` + router `calculateL2TokenAddress` round-trip |
| Elysium-native | `ElysiumBridgeFactory.expectedL1Mirror` (+ `l2WalletFor` for pair status) |
| Native HYPE | Gas path has no ERC-20; **WHYPE** is a canonical rep of HyperEVM `0x555…555` |

Verified mainnet: HyperEVM USDC `0xb883…630f` ↔ Elysium USDC `0xb47c…0b65`.

## Foundry

```shell
forge install foundry-rs/forge-std --no-commit
forge build
forge test
forge fmt
```

`StorageV2` is compiled with `via_ir` + `optimizer_runs = 1` so it fits under the EIP-170 size limit.

### Deploy storage clones to Elysium

Requires `DEPLOYER_PRIVATE_KEY` (funded with HYPE) and optional `STORAGE_BEACON_OWNER` (defaults to the deployer).

```shell
# Testnet (99801)
./script/deploy-elysium.sh elysium-testnet

# Mainnet (99901)
./script/deploy-elysium.sh elysium
```

Or directly:

```shell
forge script script/DeployStorageClones.s.sol:DeployStorageClones \
  --rpc-url "${ELYSIUM_TESTNET_RPC:-https://testnet-rpc.elysium.kinetiq.xyz}" \
  --broadcast \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  -vvv
```

Contracts that still need OpenZeppelin or have unfinished syntax live under `contracts_wip/`.

## Python

```shell
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```
