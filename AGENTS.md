# Repository Guidelines

## Project Structure & Module Organization
- `src/` Solidity contracts (e.g., `LemonJetUpgradeable.sol`, `VaultUpgradeable.sol`); interfaces live in `src/interfaces/`.
- `test/` Foundry tests (`*.t.sol`) and `test/mocks/` for mock contracts.
- `script/` Foundry scripts (`*.s.sol`) with helpers in `script/utils/`.
- `broadcast/` deployment artifacts per script/chain, `out/` build outputs, `cache/` local build cache.
- `lib/` and `dependencies/` vendor libraries (forge-std, OpenZeppelin, Chainlink), configured via `foundry.toml` and `remappings.txt`.

## Build, Test, and Development Commands
- `forge build` (CI uses `forge build --sizes`) to compile contracts and report size.
- `forge test` (CI uses `forge test -vvv`) to run the suite.
- `forge fmt` or `forge fmt --check` to format or verify formatting.
- `forge snapshot` to capture gas usage snapshots.
- `anvil` to run a local EVM node for scripts and manual testing.
- Example deploy script: `forge script script/LemonJet.s.sol:LemonJetScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY` (add `--broadcast` for live deploys).

## Coding Style & Naming Conventions
- Solidity version is 0.8.28 (`foundry.toml`); keep `pragma solidity ^0.8.28`.
- Use 4-space indentation and let `forge fmt` normalize spacing/imports.
- Contracts and files use PascalCase (`LemonJetUpgradeable.sol`), functions use camelCase.
- Tests are `*.t.sol` with `*Test` contracts; revert cases often use `test_RevertWhen_...`.

## Testing Guidelines
- Tests use `forge-std/Test.sol` and a `setUp()` for fixtures.
- Prefer targeted runs while iterating: `forge test --match-contract LemonJetTest` or `--match-test testPlayLjt`.
- No explicit coverage threshold is defined; add regression tests alongside new behavior.

## Commit & Pull Request Guidelines
- Commit messages are short and imperative; some use conventional prefixes like `chore: fmt`. Stay consistent and keep the subject concise.
- PRs should include a summary, motivation, tests run (or `not run` with reason), and any contract address changes or upgrade notes.

## Security & Configuration Tips
- Copy `.env.example` to `.env` and set `SEPOLIA_RPC_URL`, `PRIVATE_KEY`, `OWNER_ADDRESS`, `ETHERSCAN_API_KEY`.
- Never commit private keys or `.env` contents.
- FFI is enabled in `foundry.toml`; review scripts carefully before running untrusted code.
