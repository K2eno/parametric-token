// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**`
 * @title IParametricToken
 * @dev Extension of ERC20 supporting mutable and immutable parameters and
 *      allowing a single address to manage multiple sub-accounts (partitions),
 *      each with its own parameters (e.g., mint time)
 */
interface IParametricToken is IERC20 {
    // ====== CONSTANTS ======

    enum AccountType {
        Normal,
        Super
    }

    // ====== EVENTS ======

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

    // ====== FUNCTIONS ======

    // Account management

    /**
     * @notice Converts the caller's account from Normal to Super
     * @dev This creates sub-account 0 with the current balance and parameters,
     *      and clears the Normal account parameters. Only callable by the account owner
     * @param account The address of the account to convert
     * @return true if the conversion succeeded
     */
    function convertToSuper(address account) external returns (bool);

    /**
     * @notice Creates a new sub-account for a Super account
     * @dev Only callable by the owner of the Super account. The new sub-account
     *      has zero balance and default parameters
     * @param account The Super account to create a sub-account for
     * @return subId The index of the newly created sub-account
     */
    function createSubAccount(address account) external returns (uint48);

    /**
     * @notice Returns the account type (Normal or Super) for a given address
     * @param account The address to query
     * @return AccountType The account type
     */
    function accountType(address account) external view returns (AccountType);

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
     * @param paramIndex The index of the parameter (0 to NUMBER_OF_PARAMETERS-1)
     * @param account The address of the account
     * @param subId The sub-account index (0 for Normal accounts)
     * @return uint64 The parameter value
     */
    function parameterOf(
        uint8 paramIndex,
        address account,
        uint48 subId
    ) external view returns (uint64);

    /**
     * @notice Returns the sub-account allowance for a given owner and spender
     * @dev If the stored subId matches the queried subId, returns the sub-specific
     *      allowance and its oneOff flag. Otherwise, returns the general allowance
     *      (total - sub) and `false` for oneOff
     * @param owner The address of the token owner
     * @param subId The sub-account index
     * @param spender The address of the spender
     * @return (uint256, bool) The allowance amount and whether it is one-off
     */
    function allowanceForSub(
        address owner,
        uint48 subId,
        address spender
    ) external view returns (uint256, bool);

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
     * @return true if the approval succeeded
     */
    function approveForSub(
        uint48 ownerSubId,
        address spender,
        uint256 amount,
        bool oneOff
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
