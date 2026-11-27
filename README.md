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

## Foundry

```shell
forge build
forge test
forge fmt
```

Deploy against Elysium:

```shell
forge create contracts/Counter.sol:Counter \
  --rpc-url "${ELYSIUM_RPC:-https://rpc.elysium.kinetiq.xyz}" \
  --private-key <key> \
  --broadcast
```

## Python

```shell
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```
