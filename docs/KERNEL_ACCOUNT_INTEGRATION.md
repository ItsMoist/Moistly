# Kernel Account Integration

## Status and scope

This change adds an owner-authorized on-chain link primitive and documents the cross-chain discovery/indexing integration. It does not deploy the contract, install a module, change ENS/CCIP-Read configuration, or execute account calls.

Target chains: Ethereum mainnet (1), Base (8453), and Arbitrum One (42161).

## Trust model

A provider label (Privy, thirdweb, ZeroDev, or another provider) is descriptive metadata, not proof of ownership or account type. Discovery is not authorization. A shared implementation address is not sufficient to prove that an account is Kernel or that a particular user controls it.

The integration keeps these states separate:

1. **Discovered** — an address was found in provider data, deployment events, or an explicit user-supplied list.
2. **Code-verified** — code exists at the address on the specified chain and the implementation/code hash was recorded at a specific block.
3. **Kernel-classified** — the account implementation, version and supported Kernel/ERC-7579 behavior were verified against a pinned compatibility profile.
4. **Identity-linked** — the identity and account both authorized the same EIP-712 link message, validated through EOA or ERC-1271 signature checks.
5. **Module-ready** — compatibility, module type, executor target, initialization data and simulation have been reviewed. This state never triggers installation automatically.

## On-chain link primitive

contracts/KernelAccountLinkRegistry.sol is a proposed deployment artifact. It stores an identity-to-account link on each chain, with provider metadata, update time and active state.

- Both the Moistly/DCC3 identity and the smart account must authorize the exact same typed message.
- EIP-712 signatures are bound to chain ID and registry address.
- Nonces prevent replay of a previously accepted link or unlink message.
- EOA and ERC-1271 signatures are supported through OpenZeppelin SignatureChecker.
- An account must have deployed code.
- The contract does not assert that the account is Kernel; classification belongs to the verifier/indexer.
- The contract cannot install modules or execute arbitrary account calls.

Deployments should use the repository's reviewed deployment process, pinned compiler/dependency versions, tests, and per-chain deployment records. Do not point ENS, CCIP-Read, or production indexers at this contract until deployment has been independently verified and approved.

## Cross-chain discovery/indexing adapter

Use a chain-qualified record. Do not assume the same address on two chains means the same deployment.

Recommended record shape:

    type KernelAccountRecord = {
      chainId: number;
      account: string;
      identity?: string;
      accountKind: "kernel" | "erc7579-compatible" | "unknown";
      implementation?: string;
      implementationCodeHash?: string;
      provider?: "privy" | "thirdweb" | "zerodev" | "other";
      factory?: string;
      deploymentTx?: string;
      verification: "discovered" | "code-verified" | "kernel-classified" | "identity-linked";
      verifiedAtBlock?: number;
    };

### Per-chain pipeline

For Ethereum mainnet, Base and Arbitrum One:

1. Ingest candidate addresses from explicitly connected provider records, known signer EOAs, and known factory deployment events. Do not treat Alchemy transfer history as a complete account directory.
2. Read eth_getCode at a pinned block and compute the runtime code hash.
3. Inspect the EIP-1967 implementation slot where relevant, but do not assume every Kernel deployment uses that proxy pattern.
4. Verify account version and expected Kernel/ERC-7579 behavior against a pinned, audited compatibility profile. Test ERC-165/interface probes only when the implementation actually documents those interfaces; a failed ERC-165 probe alone does not disprove Kernel.
5. Store chain-qualified evidence and last-verified block. Keep provider provenance separate from proof of ownership.
6. To create the identity link, collect both signatures over the contract's exact EIP-712 payload and submit a transaction on that chain. Never request signatures that authorize execution or module installation for this linking step.
7. Emit a normalized event/indexer record for the canonical Moistly identity API. Reconcile records across chains, but retain chain-specific deployment and link state.

## Executor/module compatibility gate

Do not install a module as part of discovery or linking. Before preparing an installation transaction:

- Pin the Kernel implementation/version and ERC-7579 account behavior.
- Confirm the exact module type (executor, validator, hook, fallback, or another type) supported by that version.
- Review the module's install and uninstall hooks and all initialization calldata.
- Confirm the intended Moistly executor proxy address, chain, code hash, owner and resolver configuration.
- Simulate the complete account call and review target, calldata, value and state changes.
- Obtain the account's explicit authorized signature for the installation transaction.
- Verify installation state after execution and preserve a rollback/uninstall procedure.

## Initial candidates to verify

These Arbitrum One addresses were previously observed to have code and the same implementation-slot value. Treat them as unverified candidates until the pipeline checks their current code, account version, and ownership:

- 0x0A6aa42783756Dd3755a80df8F641Aa4F16C7F2C
- 0xA4412B36BB6D1811cCA33DE395371E2Ddd558a87

Previously observed implementation-slot value: 0xbac849bb641841b44e965fb01a4bf5f074f84b4d.

## Acceptance criteria

- Candidate records are chain-qualified and preserve evidence and verification block.
- Provider metadata never implies ownership.
- An identity link requires valid signatures from both identity and account.
- Link/unlink messages are replay-protected and chain-bound.
- Indexing can enumerate active links without treating unknown candidates as verified.
- The same identity can link different account deployments across chains without forcing a shared factory.
- Module readiness is an explicit review state and never triggers an automatic transaction.
- No registry deployment, ENS pointer change, or module installation occurs without a separate approved transaction.
