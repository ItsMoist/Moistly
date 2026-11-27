# Work-in-progress / blocked contracts

These files depend on OpenZeppelin (not vendored here yet) or contain known syntax
issues. They are parked outside `contracts/` so the Storage clone stack can build
and deploy cleanly on Elysium.

Restore into `contracts/` after adding:

```bash
forge install OpenZeppelin/openzeppelin-contracts --no-commit
```
