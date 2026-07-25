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
