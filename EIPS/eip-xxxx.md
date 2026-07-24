# **EIP-XXXX: Parametric Token Standard**

## **Abstract**

This proposal introduces a standard for parametric ERC‑20 tokens—tokens that carry additional, account‑specific parameters beyond simple balances. Parameters may be **mutable** (updated during transfers according to token‑specific rules, e.g., weighted averages) or **immutable** (must remain identical across all tokens that can coexist in the same account). The standard defines an account model that supports **sub‑accounts** (partitions) within a single address, enabling a user to hold multiple parameter variants without requiring multiple wallets. It also extends the ERC‑20 allowance system to support sub‑account‑specific approvals with a one‑off consumption option.

The standard is fully backward‑compatible with ERC‑20, ensuring seamless integration with existing wallets, exchanges, and DeFi protocols.

## **Motivation**

Traditional ERC‑20 tokens treat every token as fungible and identical. However, many advanced use cases require tokens to carry extra information that evolves with their usage history or is tied to specific characteristics. For example:

- **Prediction tokens** that represent a forecast price for an asset (e.g., “expected BTC price as of Aug 1, 2026 will be $76200”). Different tokens with different price predictions cannot be pooled in the same account without losing the distinct prediction data. Without a parametric standard, such markets are often split into separate binary option pools, fragmenting liquidity.
- **Velocity‑first** tokens where the token’s “age” (time since mint) determines its redemption fee (e.g., longer‑held tokens incur higher fees). The age must be tracked per user balance and updated on every transfer using a weighted average.
- **Tokenized positions** that carry immutable attributes like asset class (BTC, ETH, gold) and resolution time; tokens with different attributes must never be mixed in the same account.
- **Gaming or loyalty tokens** that accrue “experience” or “level” as they are held, with the parameter affecting redemption rewards.

The Parametric Token standard solves these challenges by:

- **Consolidating liquidity**: Tokens with different parameters can trade in the same pool because the token contract itself manages the parameter logic, eliminating the need to create separate pools per parameter value.
- **Enabling velocity‑first economics**: By tracking mint time, tokens can incentivise higher turnover through progressive fees.
- **Simplifying user experience**: Sub‑accounts allow a single address to hold tokens with different parameters, avoiding the need for multiple wallets.
- **Providing fine‑grained permission control**: Sub‑account‑specific allowances with one‑off option give users precise control over delegated spending, especially useful in protected (encapsulated) token systems where an engine contract manages minting, burning, and liquidity operations.

## **Specification**

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119\.

### **Definitions**

- **Parameter**: An attribute associated with a token balance (account or sub‑account). Parameters are stored as `uint64` values (may represent timestamps, prices, or any numeric value). The token contract defines a fixed number of parameters via `NUMBER_OF_PARAMETERS`.
- **Parameter Mutability**:
  - **Mutable**: The parameter value changes during token transfers according to token‑specific rules (e.g., weighted average, max operation). The token contract MUST implement the mutation logic inside its transfer functions.
  - **Immutable**: The parameter value never changes. Tokens with different immutable parameter values MUST NOT be allowed to coexist in the same account or sub‑account; the token contract SHALL revert any transfer that would cause such a conflict.
- **Account**: An Ethereum address that holds tokens. Accounts can be of two types:
  - Normal: Holds a single balance and a single set of parameters.
  - Super: Holds multiple sub‑accounts, each with its own balance and parameters.
- **Sub‑account**: A partition within a Super account, identified by a `uint48` index (starting from `0`). Sub‑account `0` is created automatically when an account is converted to Super.

### **Interface**

Every compliant Parametric Token MUST implement the following interface, in addition to the standard ERC‑20 interface (`IERC20`).

```solidity
// SPDX-License-Identifier: MIT`
pragma solidity ^0.8.30;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**`
 * @title IParametricToken
 * @dev Extension of ERC20 supporting mutable and immutable parameters and
 *      allowing a single address to manage multiple sub-accounts (partitions),
 *      each with its own parameters (e.g., mint time)
 */
interface IParametricToken is IERC20 {
  // Account types
  enum AccountType {
    Normal,
    Super
  }

  // Events
  event AccountConvertedToSuper(address indexed account);
  event SubAccountCreated(address indexed superAccount, uint48 indexed subId);
  event ParametricTransfer(
    address indexed from,
    uint48 indexed fromSubId,
    address indexed to,
    uint48 toSubId,
    uint256 amount
  );
  event ApprovalForSub(
    address indexed owner,
    uint48 indexed subId,
    address indexed spender,
    uint256 amount,
    bool oneOff
  );

  // Account management
  function convertToSuper(address account) external returns (bool);

  function createSubAccount(address account) external returns (uint48);

  function accountType(address account) external view returns (AccountType);

  // Sub-account queries
  function parametricBalanceOf(
    address superAccount,
    uint48 subId
  ) external view returns (uint256);

  function subsCountOf(address superAccount) external view returns (uint48);

  function parameterOf(
    uint8 paramIndex,
    address account,
    uint48 subId
  ) external view returns (uint64);

  function allowanceForSub(
    address owner,
    uint48 subId,
    address spender
  ) external view returns (uint256, bool);

  // Sub-account approval
  function approveForSub(
    uint48 ownerSubId,
    address spender,
    uint256 amount,
    bool oneOff
  ) external returns (bool);

  // Parametric transfers
  function parametricTransfer(
    uint48 fromSubId,
    address to,
    uint48 toSubId,
    uint256 amount
  ) external returns (bool);

  function parametricTransferFrom(
    address from,
    uint48 fromSubId,
    address to,
    uint48 toSubId,
    uint256 amount
  ) external returns (bool);
}
```

### **Parameter Configuration**

The token contract MUST define:

- `NUMBER_OF_PARAMETERS` – a constant `uint8` indicating the total number of parameters.
- A parameter configuration struct (RECOMMENDED to be exposed via a public array or getter):

```solidity
struct ParamConfig {
  bytes32 name; // human‑readable identifier (e.g., "mintTime", "price")
  uint8 decimals; // number of decimals for display
  bool isMutable; // true if mutable, false if immutable
}
```

The contract MUST implement `parameterOf(uint8 paramIndex, address account, uint48 subId) external view returns (uint64)` to return the current parameter value for a given account/sub‑account. For Normal accounts, `subId` MUST be `0`; for Super accounts, the caller MUST provide a valid `subId`.

### **Account Types and Sub‑accounts**

- **Normal accounts** hold a single balance and one set of parameters.
- **Super accounts** hold multiple sub‑accounts, each with its own balance and parameters. The aggregate balance of a Super account is the sum of all its sub‑account balances (accessible via `balanceOf`).
- An account is initially Normal. The owner MAY convert it to Super by calling `convertToSuper(address account)`. This creates sub‑account `0` with the current balance and parameters, and clears the Normal parameters.
- Additional sub‑accounts can be created by the owner via `createSubAccount(address account)`, which returns the new sub‑account index.

### **Parameter Semantics**

#### Immutable Parameters

- Tokens with different immutable parameter values MUST NOT be merged into the same account/sub‑account.
- If the recipient’s balance is zero, the incoming tokens’ immutable parameters are accepted (the account inherits them).
- If the recipient already holds tokens, any transfer that would result in a mix of different immutable parameter values MUST revert.
- This check applies to both standard ERC‑20 transfers and parametric transfers.

#### Mutable Parameters

- When tokens are transferred, the recipient’s mutable parameters MUST be updated according to token‑specific rules.
- The token contract MUST implement the mutation logic inside its internal transfer functions. Examples of mutation rules:
  - Weighted average (e.g., mintTime \= (oldMintTime \* oldBalance \+ incomingMintTime \* incomingAmount) / (oldBalance \+ incomingAmount)).
  - Maximum (e.g., transferStep \= max(oldTransferStep, incomingTransferStep \+ 1)).
  - Any custom logic as long as it is deterministic and gas‑efficient.
- The mutation logic for each mutable parameter MUST be implemented as a **pure** function whose return value is computed deterministically from:
  - parameters of the source account,
  - parameters of the destination account,
  - the transfer value,
  - pre-transfer balance value of the destination account,
  - other state variables or deterministic blockchain parameters (e.g., `block.timestamp`, external price oracles).
- When the balance of an account or sub‑account becomes zero, its parameters SHOULD be reset to a default initial value (e.g., `0` or `block.timestamp` at creation).

#### Resulting Balance

- The post‑transfer balance of the destination account MAY be calculated using logic other than a simple sum of the pre‑transfer balance and the transfer amount. If such custom logic is used, it MUST be implemented as a **pure** function whose return value is computed deterministically from:
  - parameters of the source account,
  - parameters of the destination account,
  - the transfer value,
  - pre-transfer balance value of the destination account,
  - other state variables or deterministic blockchain parameters (e.g., `block.timestamp`, external price oracles).

#### Parameter Initialization

Parameter initialization (setting initial values when tokens are minted) is **outside the scope of this standard**, as minting is typically controlled by an external engine contract rather than the token itself. However, compliant implementations MUST ensure that every mint operation results in all parameters being set to well‑defined initial values.

The initialization mechanism MAY be implemented in one of the following ways (or a combination thereof):

- The minting engine provides the initial parameter values as arguments to the mint function.
- The minting user (the recipient) selects the initial parameter values at the time of minting (e.g., choosing a prediction price for a resolution time they believe will prevail).
- The token contract derives initial values from deterministic blockchain parameters (e.g., `block.timestamp` for a mintTime parameter).

Regardless of the mechanism, the token contract MUST NOT allow a mint operation to complete with uninitialized or default‑zero parameters unless zero is explicitly intended as a valid initial value.

### **Allowances and Approvals**

The standard extends the ERC‑20 allowance system to support sub‑account‑specific allowances.

#### Data Structure

Each allowance record is represented by:

```solidity
struct Allowance {
  uint256 total; // total allowance for all sub‑accounts (sum of sub + general)
  uint256 sub; // allowance specifically for the sub‑account identified by subId
  uint48 subId; // which sub‑account the sub allowance applies to
  bool oneOff; // if true, this sub‑allowance is consumed entirely after one use
}
```

The invariant `total >= sub` MUST be maintained, where `(total - sub)` represents the general allowance that can be spent from any sub‑account except the one identified by `subId`.

#### Standard ERC‑20 Approvals

- `approve(address spender, uint256 amount)` sets `total` to `amount`. If `sub` exceeds `amount`, it is capped to `amount`. If `amount` is `0`, the `oneOff` flag MUST be cleared.
- This function does not affect `subId` or `oneOff` for non‑zero amounts.

#### Sub‑account‑specific Approvals

- `approveForSub(uint48 ownerSubId, address spender, uint256 amount, bool oneOff)`:
  - Can only be called by the owner of a Super account.
  - Sets `subId` to `ownerSubId`, `sub` to `amount`, and `oneOff` to the provided value.
  - If `oneOff` is `true`, `amount` MUST be \> 0\.
  - If `amount > total`, `total` is raised to `amount` (maintaining `total >= sub`).
  - Emits `ApprovalForSub`.

#### Spending Allowances

- `transferFrom(address from, address to, uint256 amount)` – standard ERC‑20 transfer:
  - MUST spend from sub‑account `0` of `from` (default sub‑account for ERC‑20 compatibility).
  - For Normal accounts, deducts from `total`.
  - For Super accounts, calls the internal `_spendParametricAllowance(from, spender, 0, amount)`.
- `parametricTransferFrom(...)` – parametric transfer with specified `fromSubId`:
  - Checks sufficient allowance via `_sufficientAllowanceForSub`.
  - Deducts allowance via `_spendParametricAllowance`.

#### One‑off Allowance Behavior

- If `oneOff` is `true` and the allowance is spent using the exact `subId` stored in the allowance record:
  - After the normal deduction (reducing `sub` and `total` by `amount`), the remaining `sub` allowance is zeroed and `total` is reduced by the remaining `sub`, so that the general allowance (`total - sub`) remains unchanged.
  - The `oneOff` flag is set to `false`.
  - The `subId` MAY remain unchanged.
- If the allowance is spent from a different `subId`, the `oneOff` flag is ignored (the allowance behaves as normal).
- Standard `approve()` cannot set `oneOff`; calling it with `amount = 0` clears the flag.

### **Required Internal Functions (Implementation Guidance)**

The specification does not mandate a particular internal implementation, but to achieve the described semantics, implementations SHOULD include:

- A function that updates mutable parameters during transfers (e.g., `_updateParametersBeforeExecution`).
- A conflict check for immutable parameters (`_noParamsConflict`).
- An internal function to spend sub‑account allowances (`_spendParametricAllowance`).
- An internal function to verify sufficient allowance (`_sufficientAllowanceForSub`).

### **Sub‑account Validation**

The standard defines a helper modifier (RECOMMENDED):

```solidity
modifier onlyValidSub(address account, uint48 subId) {
 if (subId > 0) require(_accounts[account].accountType == AccountType.Super, "Not a super account");
 if (subId > 0) require(subId < _supers[account].subsCount, "Sub-account doesn't exist");
 _;
}
```

This ensures that `subId` is valid for the given account.

### **ERC‑20 Compatibility**

All standard ERC‑20 functions (`transfer`, `transferFrom`, `balanceOf`, `allowance`, `approve`, `totalSupply`, `name`, `symbol`, `decimals`) MUST behave as defined in ERC‑20. In particular:

- `transfer(address to, uint256 amount)` MUST be equivalent to `parametricTransfer(0, to, 0, amount)` – i.e., transfer from sub‑account 0 to sub‑account 0\.
- `transferFrom(address from, address to, uint256 amount)` MUST spend allowance from the owner's sub‑account 0 and transfer to sub‑account 0 of the recipient.
- `balanceOf(address account)` MUST return the total balance across all sub‑accounts for Super accounts, or the balance for Normal accounts.
- `allowance(address owner, address spender)` MUST return `total` (the sum of all sub‑allowances).

## **Rationale**

### **Why Sub‑accounts?**

Sub‑accounts allow a single address to hold tokens with different immutable parameters (or simply different parameter histories) without requiring multiple wallets. This simplifies user experience and reduces the need for key management. Sub‑account `0` serves as the default for ERC‑20 compatibility, ensuring that existing wallets and tools work without modification.

### **Why Separate `total` and `sub` Allowance?**

The split between `total` and `sub` provides flexibility: an owner can grant a specific allowance for a particular sub‑account (e.g., to a trading bot that should only access that sub‑account) while still allowing a larger general allowance for other sub‑accounts. This is crucial in scenarios where different sub‑accounts represent different strategies or risk profiles.

### **Why One‑off Allowance?**

One‑off allowances are useful for atomic operations where the spender should only be able to use the allowance once (e.g., for a single redemption or swap). The standard ensures that after any positive spend from the designated sub‑account, the entire sub‑allowance is consumed, preventing accidental or malicious reuse. The invariant is preserved by adjusting `total` to reflect the remaining general allowance.

### **Why `uint64` for Parameters?**

`uint64` is sufficient for most use cases (timestamps, prices scaled by `10^decimals`, etc.) and is gas‑efficient. The `decimals` field in `ParamConfig` allows for human‑readable formatting.

### **Why `uint48` for Sub‑account Index?**

`uint48` is enough to support an enormous number of sub‑accounts (over 2.8e14) while being storage‑efficient when packed with other fields.

## **Backwards Compatibility**

- The standard is fully ERC‑20 compatible; all standard functions behave as expected.
- Existing wallets and exchanges that only implement ERC‑20 will work with Parametric Tokens, seeing only the aggregate balance and total allowance.
- Advanced features (sub‑accounts, parameters) are accessed via additional functions; they do not interfere with standard operations.
- The standard does not introduce any new security risks beyond those inherent in ERC‑20 (e.g., reentrancy, allowance attacks), and the recommended implementation patterns mitigate them.

## **Security Considerations**

### **Parameter Conflict Checks**

Implementations MUST verify immutable parameter compatibility before executing any transfer. Failure to do so could allow tokens with different immutable parameters to mix, breaking the intended semantics.

### **Allowance Manipulation**

As with standard ERC‑20, users should be cautious when approving large allowances. The `oneOff` feature mitigates some risks by automatically consuming the allowance after a single use, but it only applies to sub‑account allowances. Standard approvals (`approve`) remain subject to the same risks as in ERC‑20.

### **Reentrancy**

All external functions that modify state (transfers, approvals, sub‑account creation) SHOULD be protected with reentrancy guards, especially when they call external contracts (e.g., during transfers that may trigger hooks).

### **Sub‑account Ownership**

Only the account owner can convert to Super or create sub‑accounts. However, once an account is Super, the owner must manage sub‑account indices carefully; there is no mechanism to delete sub‑accounts, so the number of sub‑accounts should be bounded.

### **Parameter Mutation**

The mutation logic for mutable parameters must be carefully designed to avoid overflow or underflow. Since parameters are `uint64`, all arithmetic should be checked (or use Solidity’s built‑in overflow checks). The weighted average calculation, for example, should use `uint256` intermediate values to prevent overflow.

### **Protection Against Unauthorised Engine Access**

In encapsulated token systems (like the Inverse Token example), the engine contract may have special privileges. The standard does not mandate such a mechanism, but if implemented (e.g., via `onlyEngine` modifiers), the contract must ensure that the engine cannot bypass user approvals without explicit consent.

### **One‑off Allowance Reset**

The reset logic (zeroing remaining sub and adjusting total) must be performed atomically within the same transaction to avoid race conditions. The implementation must not allow the allowance to be spent in two separate transactions after the first use.

## **Copyright**

CC0 1.0 Universal

## **Citation**

Please cite this document as:

```bibtex
@article{
EIP-ParametricToken,
title={EIP-XXXX: Parametric Token Standard},
author={Alexander Zvezdin},
url={https://github.com/k2eno/eip-parametric-token},
year={2026}
}
```

Author: Alexander Zvezdin ([@k2eno](https://github.com/k2eno))  
Status: Draft  
Created: July 24, 2026
