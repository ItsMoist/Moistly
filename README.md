## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Relay recovery discovery

The Flask backend includes a read-only Relay adapter. It finds indexed orders,
source deposits, destination/refund transactions, and credited recovery balances.
It never signs messages, attests deposits, or submits withdrawals.

Run with Flask installed:

```sh
export RELAY_API_KEY='<server-side Relay API key>'
flask --app moistlyRear:create_app run
```

- `GET /api/v1/recovery/relay/0xWALLET` lists 20 orders. A Relay API key is required.
- Add `deposit_tx=0xHASH` to match a deposit transaction.
- Add `mode=balances&owner_chain_id=42161` to query credited Hub balances
  for an Arbitrum recovery owner. Use the owner's numeric chain ID, not the
  destination chain inferred from an order. This endpoint supports keyless reads.
- Pass the returned `continuation` cursor to retrieve the next page for the same
  wallet and filters. A page is not a complete history.

`withdrawal_eligibility` is always `unverified`: failed orders and credited balances
are not proof of a recoverable claim. Empty results do not prove no assets exist:
orders exclude unindexed deposits; balances exclude deposits awaiting attestation.
Recovery must be checked through https://relay.link/withdraw with the authorized
wallet. No ENS ownership or recovery authorization is inferred from an address.
Upstream/configuration failures return 503; invalid inputs return 400.

References: [orders](https://docs.relay.link/references/api/get-requests),
[recovery balances](https://docs.relay.link/references/api/get-withdrawal-balances).

Tests (Flask required): `python -m unittest discover -s tests -v`.
