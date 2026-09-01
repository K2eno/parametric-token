# Parametric Token Standard – ERC-8378 Reference Implementation

This repository contains the reference implementation for the Parametric Token Standard (ERC-8378), a fully ERC‑20 compatible token standard that allows fungible tokens to carry account‑specific, mutable parameters.

## What is a Parametric Token?

A parametric token is an ERC‑20 token where every balance carries additional information – parameters. Parameters can be:

- Mutable – updated during mints/transfers according to deterministic rules (e.g., weighted average, max operation)
- Immutable – fixed; tokens with different immutable parameter values can never coexist in the same account.

Parameters are account‑specific, not token‑class‑specific. This means two users holding the same token can have different parameter values, and these values evolve as tokens move between accounts.

The standard also introduces sub‑accounts – partitions within a single address that allow a user to hold multiple parameter variants without needing multiple wallets.

Optional functionalities include inbound transfer permissions and non-zero-sum transfers.

## Why Parametric Tokens?

The standard addresses real‑world needs:

- Liquidity consolidation – parametric tokens bring state to fungibility, tokens.with different parameters trade in the same pool; no segmentation by parameter value
- Velocity control – progressive age‑based fees or rewards let you design tokens for high or low turnover.
- Advanced derivatives – tokenized portfolios (like the Bundle) and other sophisticated constructs work out‑of‑the‑box.
- Simplified UX – sub‑accounts and fine‑grained allowances/permissions provide intuitive and powerful wallet controls.

## Repository Structure

```text
ERCS/
└── erc-8378.md                   # ERC draft

src/
├── interfaces/
│   └── spec/                     # ERC interfaces
│       ├── IParametricToken.sol
│       ├── IParametricTokenNzs.sol
│       └── IParametricPermissions.sol
├── libraries/
│   └── Lib.sol                   # Pure functions (weightedAverage, sqrt, combine)
├── mock/
│   └── AssetToken.sol            # Sample ERC‑20 for testing
├── bundle/                       # Bundle token and engine implementation
├── prediction/                   # Prediction token and engine implementation
└── tenure/                       # Tenure token and engine implementation

script/
├── BundleDeploy.s.sol
├── PredictionDeploy.s.sol
└── TenureDeploy.s.sol

test/
├── Bundle.t.sol
├── Prediction.t.sol
└── Tenure.t.sol

out/                                  # Build artifacts and deployed addresses
└── bundle_deployed_addresses.json
└── tenure_deployed_addresses.json
└── prediction_deployed_addresses.json
```

## ERC Specification

The full ERC specification is available in [`ERCS/erc-8378.md`](https://github.com/K2eno/parametric-token/blob/main/ERCS/erc-8378.md). It covers:

- Interfaces and data models
- Parameter semantics (mutable/immutable)
- Sub‑accounts, allowances and permissions
- ERC‑20 compatibility requirements
- Security considerations
- Rationale and comparison with existing standards.

## The Three Implementations

All token implementations use router-proxy pattern (to efficiently manage contract size) accompanied by an engine. Every implementation is supported by respective deployment script.

### 1\. Tenure – Age‑Based Economics Token

Concept: A token where the parameter is `mintTime` (timestamp of mint). The engine awards progressive rewards on redemption that are proportional to the token's age.

- Parameter: `mintTime` (mutable, weighted average on transfer)
- Mutation: `weightedAverage` – when two holdings merge, the new mint time is a weighted average of the two
- Mint: Engine‑controlled (engine calls `mint`). `mintTime` is set to `block.timestamp` or `weightedAverage` as applicable
- Burn: Engine‑controlled (engine calls `burn` with a reward computed from age)
- Rewards are proportional to `(block.timestamp - mintTime)` – the older the token, the higher the reward points granted.

#### Use cases:

A. Yield-bearing (or credentials-bearing) tokens: link rewards to the age of the token.
B. Utility‑bearing tokens: stimulate token turnover to avoid holding costs whenever holders don't use the token for its designated purpose (say, portfolio risk management).

---

### 2\. Prediction – Scalar Prediction Market

Concept: A token where traders mint predictions about the price of an asset at a given future resolution time. The token has two parameters: `prediction` (mutable, weighted average) and `round` (immutable, must match when merging). Token implements `permissions` (`IParametricPermissions`) to filter inbount transfers/mints.

- Parameters:
  - `prediction` (mutable, weighted average on transfer)
  - `round` (immutable, 0–4; tokens with different rounds cannot merge). Every `round` has its resolution time
- Mutation: `weightedAverage` for `prediction`; conflict check for `round`
- Mint: Self‑mint – traders call `mint` directly with their preferred predicted price and round
- Burn: Engine‑controlled – engine calls `burn` when traders report their predictions
- The engine manages rounds (`active → reporting → claiming`). After the round closes, traders report by burning their tokens. Points are distributed inversely to prediction deviation
- Token contract does not allow to `mint`/`transfer` to an account/sub-account with a different `round` parameter.

#### Use case:

Scalar prediction markets where liquidity is consolidated into a single pool, unlike binary markets that fragment liquidity by outcome layers.

---

### 3\. Bundle – Portfolio Tokenization

Concept: A token representing a tokenized portfolio (bundle) of an underlying like WBTC and its inverse INV. The bundle token is called BUN. The parameter is the `anchor` – the WBTC price at which the portfolio's USD value is minimised (inverse pricing of INV produces strictly positive gamma of [WBTC + INV] bundle). When two BUNs with different anchors merge, both the anchor and the total balance are recomputed using the convexity formula. BUN is normalized to have 1 USD value at `anchor` underlying price. BUN implements NZS transfers (`IParametricTokenNzs` with `debitAmount != creditAmount`).

- Parameter: `anchor` (mutable, complex non‑linear mutation)
- Mutation: `combine` – a pure function that recomputes the anchor and total balance when two holdings merge. Resulting `creditAmount` in general case is not equal transfer `amount`.
- Mint: Engine‑controlled – engine computes the anchor from WBTC/INV deposit amounts and mints BUN
- Burn: Engine‑controlled – engine computes the underlying WBTC/INV amounts based on the anchor and burns BUN
- In general case the balance update is not a simple sum; it follows the convexity formula. This demonstrates the standard's flexibility for advanced financial engineering.

#### Use case:

Advanced derivatives engineering.

## ⚠️ Scope & Disclaimer

This repository is a **reference implementation** of the ERC-8378 standard. Its sole purpose is to demonstrate the core parametric primitives—mutable/immutable parameters, sub‑account management, and deterministic mutation logic—in an executable, minimally complex form.

To keep the focus on these novel mechanics, the `Prediction` and `Tenure` examples deliberately abstract away economic safeguards and security layers:

- Minting is permissionless and does not require collateral (e.g., payment in a mock asset or stablecoin).
- There are no supply caps, minting fees, or rate limits.
- Rewards are issued as illustrative virtual `POINTS` to visualise the _outcome_ of holding a stateful token (e.g., deviation from a price or holding duration), not as a production‑ready incentive mechanism.

In contrast, the `Bundle` example _does_ introduce mock `WBTC` and `INV` tokens because its core parametric feature — convex portfolio recombination — requires a meaningful underlying assets relationship to demonstrate the `combine` mutation logic.

**When evaluating this standard, focus strictly on the on‑chain parameter semantics, sub‑account allowances, and transfer mutations.** The economic, game‑theoretic, and security safeguards (access controls, collateralisation, or pricing oracles) required for production deployments are out of scope for this demo and must be implemented by integrators based on their specific use cases.

## Gas Efficiency

The parametric token standard adds stateful logic to fungible transfers while maintaining competitive gas costs. The table below shows gas consumption for core functions across the three reference implementations.

| Function                 | Prediction               | Tenure    | Bundle          |
| ------------------------ | ------------------------ | --------- | --------------- |
|                          | _2 params + permissions_ | _1 param_ | _1 param + NZS_ |
| `approveForSub`          | 45,870                   | 45,831    | 45,831          |
| `allowanceOf`            | 14,694                   | 14,677    | 14,677          |
| `parameterOf`            | 9,537                    | 9,498     | 9,498           |
| `parametricBalanceOf`    | 11,338                   | 11,299    | 11,299          |
| `transfer`               | 90,711                   | 76,755    | 113,852         |
| `transferFrom`           | 102,241                  | 88,175    | 125,383         |
| `parametricTransfer`     | 91,427                   | 80,189    | 117,397         |
| `parametricTransferFrom` | 109,351                  | 95,329    | 132,537         |
| `mint`                   | 92,086                   | 70,378    | 105,114         |
| `burn`                   | 64,100                   | 61,242    | 63,018          |
| `permitForSub`           | 41,683                   | n/a       | n/a             |
| `permissionOf`           | 13,056                   | n/a       | n/a             |

#### Methodology:

- Values represent the median gas cost for multiple similar executions with warm storage access.
- `Router` overhead is included: values reflect the total gas paid by the user, including the `Router`'s `delegatecall` overhead.
- Refunds are not included.
- All executions use Super accounts and involve non-trivial mutations and permission checks where applicable.

Results are implementation- and configuration-specific and are intended as comparative benchmarks rather than universal gas estimates.

#### Key observations:

- **Statefulness adds moderate overhead.** The most expensive measured operation, `parametricTransferFrom` in `Bundle`, consumes 132.5k gas. Gas spending remains well below block limits and is economically viable for frequent use.
- **Mutation logic directly affects transfer expense.** `Bundle` NZS `combine` mutation adds ~22‑38k gas compared to simple weighted averages.
- **Parameter and optional permissions handling remain practical.** Enabling `permissions` adds ~5‑10k gas, making it perfectly suitable for agentic and DeFi use cases.

## Pure Functions in Libraries

All mutation logic is implemented as pure functions in `src/libraries/Lib.sol`:

```solidity
function weightedAverage(
  uint64 p1,
  uint256 b1,
  uint64 p2,
  uint256 b2
) external pure returns (uint64 newParameter);

function combine(
  uint64 a1,
  uint256 b1,
  uint64 a2,
  uint256 b2
) external pure returns (uint64 newAnchor, uint256 newBalance);
```

This emphasises their stateless, deterministic nature – they depend only on their inputs, never on contract state. This is a core requirement of the ERC for mutable parameter mutation functions.

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Installation

```bash
git clone https://github.com/k2eno/parametric-token
cd parametric-token

forge install
```

### Build

```bash
forge build
```

## Tests

```bash
forge test
```

Specific test files for each token are `test/Prediction.t.sol`, `test/Tenure.t.sol`, and `test/Bundle.t.sol`.

## Scripts

Deployment scripts are provided for each implementation. Use the following command to deploy prediction contracts:

```bash
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

forge script script/PredictionDeploy.s.sol --broadcast --rpc-url http://localhost:8545 --slow --via-ir
```

After deployment, the contract addresses are saved to `out/prediction_deployed_addresses.json`.

Use the same pattern for `Bundle` and `Tenure` contracts.

## License

- Specification: Public domain via [CC0 1.0 Universal](LICENSE-CC0).
- Code Implementations: [MIT License](LICENSE-MIT).

## Citation

If you use this software or reference the Parametric Token Standard in an academic publication, please cite it as follows:

```bibtex
@misc{zvezdin2026parametric,
  author       = {Alexander Zvezdin},
  title        = {ERC-8378: Parametric Token Standard},
  year         = {2026},
  publisher    = {GitHub},
  journal      = {GitHub Repository},
  howpublished = {\url{https://github.com/k2eno/parametric-token}}
}
```
