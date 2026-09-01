// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**`
 * @title IParametricToken
 * @dev Extension of ERC-20 supporting mutable and immutable parameters and
 *      allowing a single address to manage multiple sub-accounts (partitions),
 *      each with its own parameters (e.g., mint time). Supports ERC-165
 */
interface IParametricToken is IERC20, IERC165 {
    // ====== STRUCTS ======

    struct ParamConfig {
        bytes32 name; // Human‑readable identifier (e.g., "mintTime", "anchor")
        uint8 decimals; // Number of decimals for display
        bool isMutable; // True if parameter changes during transfers
    }

    // ====== EVENTS ======

    /**
     * @notice Emitted when a Normal account is converted to a Super account.
     * @dev This creates the default sub-account `0`, transferring the existing
     *      balance and parameters to it. The account's type is permanently changed.
     *      Can only be triggered by the account owner.
     * @param account The address of the account that was converted to Super
     */
    event AccountConvertedToSuper(address indexed account);

    /**
     * @notice Emitted when a new sub-account is created within a Super account.
     * @dev The new sub-account is initialized with zero balance and default
     *      parameters. Can only be triggered by the Super account owner.
     * @param superAccount The address of the Super account that owns the new sub-account
     * @param subId The index of the newly created sub-account
     */
    event SubAccountCreated(address indexed superAccount, uint48 indexed subId);

    /**
     * @notice Emitted when a zero-sum parametric token transfer occurs.
     * @dev The standard ERC-20 `Transfer` event MUST also be emitted using the `amount`.
     *      This event SHOULD NOT be emitted for NZS token transfers, instead `ParametricTransferNzs`
     *      SHALL be emitted.
     * @param from The sender address
     * @param fromSubId The sender's sub-account
     * @param to The recipient address
     * @param toSubId The recipient's sub-account
     * @param amount The exact amount added to the recipient's balance
     * @param resultingParams The full parameter array of the receiver AFTER parameters update
     */
    event ParametricTransfer(
        address indexed from,
        uint48 indexed fromSubId,
        address indexed to,
        uint48 toSubId,
        uint256 amount,
        uint64[] resultingParams
    );

    /**
     * @notice Emitted when a sub-account specific allowance is set or updated.
     * @dev This allowance applies specifically to `subId`. If `oneOff` is `true`,
     *      the allowance is consumed entirely after the first non-zero spend from
     *      that sub-account. The general allowance (`total - sub`) is adjusted to
     *      ensure `total >= sub`. Standard ERC-20 `Approval` events remain unaffected.
     * @param owner The address of the token owner
     * @param subId The sub-account for which the allowance is granted
     * @param spender The address authorized to spend the tokens
     * @param amount The specific allowance amount for the sub-account
     * @param oneOff `true` if the allowance is one-time use
     * @param committedUntil Future time if allowance is committed, otherwise 0
     */
    event ApprovalForSub(
        address indexed owner,
        uint48 indexed subId,
        address indexed spender,
        uint256 amount,
        bool oneOff,
        uint64 committedUntil
    );

    // ====== FUNCTIONS ======

    // Account settings

    /**
     * @notice Returns the total number of parameters defined by this token.
     * @dev MUST be a constant value.
     */
    function NUMBER_OF_PARAMETERS() external view returns (uint8);

    /**
     * @notice Returns metadata for all parameters defined by this token
     * @return ParamConfig[] Array of metadata sets (name, decimals, isMutable)
     */
    function paramConfig() external view returns (ParamConfig[] memory);

    // Account management

    /**
     * @notice Converts the caller's account from Normal to Super
     * @dev This creates sub-account 0 with the current balance and parameters,
     *      and clears the Normal account parameters
     * @return true if the conversion succeeded
     */
    function convertToSuper() external returns (bool);

    /**
     * @notice Creates a new sub-account for a Super account
     * @dev Creates new sub-account to the owner's Super account
     *      with zero balance and initial (zero) parameters
     * @return subId The index of the newly created sub-account
     */
    function createSubAccount() external returns (uint48);

    /**
     * @notice Returns true if the account is a Super account
     * @dev This is a compatibility helper for ERC‑20 wallets
     * @param account The address to query
     * @return bool True if the account is a Super account
     */
    function isSuperAccount(address account) external view returns (bool);

    // Sub-account queries

    /**
     * @notice Returns the balance of a Normal account or specific sub-account
     * @dev For Normal accounts, subId must be 0. For Super accounts,
     *      the subId must correspond to an existing sub-account
     * @param account The address of the account (Normal or Super)
     * @param subId The index of the sub-account (0 for Normal accounts)
     * @return uint256 The balance of the specified sub-account
     */
    function parametricBalanceOf(
        address account,
        uint48 subId
    ) external view returns (uint256);

    /**
     * @notice Returns the number of sub-accounts for an account
     * @dev Returns 0 if the account is not Super
     * @param account The account to query
     * @return uint48 The number of sub-accounts
     */
    function subsCountOf(address account) external view returns (uint48);

    /**
     * @notice Returns the value of a parameter for a given account or sub-account
     * @dev paramIndex must be less than NUMBER_OF_PARAMETERS
     *      For Normal accounts, subId must be 0
     * @param account The address of the account
     * @param subId The sub-account index (0 for Normal accounts)
     * @param paramIndex The index of the parameter (0 to NUMBER_OF_PARAMETERS-1)
     * @return uint64 The parameter value
     */
    function parameterOf(
        address account,
        uint48 subId,
        uint8 paramIndex
    ) external view returns (uint64);

    /**
     * @notice Returns the sub-account allowance for a given owner and spender
     * @dev If the stored subId matches the queried subId, returns the sub-specific
     *      allowance and its oneOff flag. Otherwise, returns the general allowance
     *      (total - sub) and `false` for oneOff
     * @param owner The address of the token owner
     * @param subId The sub-account index
     * @param spender The address of the spender
     * @return (uint256, bool, uint64) The allowance amount, one-off flag and commitment deadline
     */
    function allowanceOf(
        address owner,
        uint48 subId,
        address spender
    ) external view returns (uint256, bool, uint64);

    /**
     * @notice Returns sub-allowance settings for a given owner and spender
     * @dev Returns (0, 0, false) for Normal accounts
     * @param owner The address of the token owner
     * @param spender The address of the spender
     * @return (uint48, uint256, bool, uint64) The allowance subId, sub amount,one-off flag and committment deadline
     */
    function subAllowance(
        address owner,
        address spender
    ) external view returns (uint48, uint256, bool, uint64);

    // Sub-account approval

    /**
     * @notice Sets an allowance for a specific sub-account.
     * @dev Only callable by the owner of a Super account. The allowance applies
     *      specifically to the given subId. If oneOff is true, the allowance is
     *      consumed entirely after the first non-zero spend from that subId
     * @param ownerSubId The sub-account for which the allowance is granted
     * @param spender The address authorized to spend
     * @param amount The allowance amount (sub-account-specific)
     * @param oneOff If true, the allowance is one-time use
     * @param committedUntil Future timestamp for allowance commitment deadline, otherwise 0
     * @return true if the approval succeeded
     */
    function approveForSub(
        uint48 ownerSubId,
        address spender,
        uint256 amount,
        bool oneOff,
        uint64 committedUntil
    ) external returns (bool);

    // Parametric transfers

    /**
     * @notice Transfers tokens from the caller's specified account/sub-account to a recipient's account/sub-account
     * @dev The caller must have sufficient balance in account/fromSubId.
     *      The transfer will apply parameter mutation logic (weighted average, conflict checks)
     *      before updating balances
     * @param fromSubId The sub-account to transfer from (0 for Normal accounts)
     * @param to The recipient address
     * @param toSubId The recipient's sub-account (0 for Normal accounts)
     * @param amount The number of tokens to transfer
     * @return true if the transfer succeeded
     */
    function parametricTransfer(
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Transfers tokens from a specified sub-account using an allowance
     * @dev This is the parametric equivalent of ERC-20 transferFrom.
     *      The spender must have sufficient allowance for the specified fromSubId.
     *      The transfer will apply parameter mutation logic before updating balances
     * @param from The token owner address
     * @param fromSubId The sub-account to transfer from (0 for Normal accounts)
     * @param to The recipient address
     * @param toSubId The recipient's sub-account (0 for Normal accounts)
     * @param amount The number of tokens to transfer
     * @return true if the transfer succeeded
     */
    function parametricTransferFrom(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    ) external returns (bool);
}
