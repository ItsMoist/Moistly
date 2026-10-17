# Kernel Account Link Registry Deployment Runbook

## Important status

The contract and deployment script are proposed artifacts. They have not been compiled, tested, audited, deployed, or verified in this environment. The repository connector cannot run Foundry, and outbound GitHub access from the available shell is unavailable. Do not broadcast until the checks below pass locally and the PR is reviewed.

## Chain IDs

- Ethereum mainnet: 1
- Base mainnet: 8453
- Arbitrum One: 42161

Deploy one registry per chain. Each deployment has its own address and EIP-712 domain. Do not assume one chain's registry address applies to another.

## 1. Local setup and build

From a trusted checkout of the PR branch, run:

    forge --version
    forge build
    forge test --match-path test/KernelAccountLinkRegistry.t.sol -vvv
    forge test
    forge fmt --check

If dependencies are missing, install the repository's pinned dependencies using the project's documented method; do not silently upgrade OpenZeppelin or Foundry dependencies for a production deployment. Review lockfiles and remappings.

Required review before broadcast:
- Ensure OpenZeppelin SignatureChecker resolves to the pinned repository dependency.
- Add coverage for malformed signatures, invalid identity signature, invalid account signature, nonce replay, expiry, chain/domain mismatch, inactive link state, and no-code account rejection.
- Run static analysis and review gas and bytecode output.
- Have the contract and tests reviewed; confirm the dual-signature trust model.

## 2. Configure secrets locally

Use a local ignored .env file or a secure secret manager. Never commit private keys or RPC credentials.

Example .env variables:

    ETH_MAINNET_RPC_URL=https://<your-ethereum-rpc>
    BASE_RPC_URL=https://<your-base-rpc>
    ARBITRUM_RPC_URL=https://<your-arbitrum-rpc>
    DEPLOYER_PRIVATE_KEY=<deployment-key>
    EXPECTED_DEPLOYER=0x<expected-deployer-address>
    EXPECTED_CHAIN_ID=8453

Use a dedicated deployment key with only the funds needed for the selected chain. Verify EXPECTED_DEPLOYER independently against the key before use. Do not paste private keys into chat, commit them, or place them in shell history.

## 3. Simulate, then broadcast one chain at a time

For Base, simulate first without broadcast:

    set -a; source .env; set +a
    forge script script/DeployKernelAccountLinkRegistry.s.sol:DeployKernelAccountLinkRegistry --rpc-url base -vvvv

Review the chain ID, deployer, predicted contract address, creation bytecode, and estimated cost. If simulation is correct, and only after review and explicit approval to spend deployment gas:

    forge script script/DeployKernelAccountLinkRegistry.s.sol:DeployKernelAccountLinkRegistry --rpc-url base --broadcast -vvvv

For Ethereum, set EXPECTED_CHAIN_ID=1 and use --rpc-url mainnet. For Arbitrum One, set EXPECTED_CHAIN_ID=42161 and use --rpc-url arbitrum. Re-run a fresh simulation for each chain. Do not run all chains in a single unreviewed command.

The script checks that the connected chain ID matches EXPECTED_CHAIN_ID and that the key-derived address matches EXPECTED_DEPLOYER.

## 4. Verify after each deployment

From the broadcast output, record contract address, transaction hash, block number, deployer, chain ID, compiler version, and creation/runtime bytecode hashes.

Then:
- Query eth_getCode and confirm non-empty runtime bytecode.
- Read domainSeparator() and confirm it is nonzero and chain-specific.
- Verify the deployment transaction and source on the chain's block explorer.
- Run a read-only call to getLink(identity, account) for an unlinked pair and confirm the default record is inactive.
- Store the verified deployment address in the chain deployment manifest; do not point ENS, CCIP-Read, or production indexers at it until verified.

## 5. Identity linking is a separate transaction

Deploying this registry does not register accounts. For each identity/account pair, the application must build the exact EIP-712 KernelAccountLink payload with current nonce, registry address, chain ID, provider hash, active flag, and deadline. Both the identity and smart account must authorize the same digest. Submit setLink only after displaying and reviewing the payload and collecting both signatures.

Do not reuse signatures across chains or registry addresses. Do not use link signatures as authorization to install modules.

## 6. Module installation is a separate change

No module installation is included in this deployment. Before a Kernel module installation, verify the account implementation/version, supported module type, module address and code hash, initialization data, executor permissions, simulation results, and explicit account authorization. Record installation state only after the transaction is confirmed.