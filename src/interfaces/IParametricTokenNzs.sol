// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./IParametricToken.sol";

/**`
 * @title IParametricTokenNzs
 * @dev Extension of IParametricToken interface to support non-zero-sum parametric transfers. Required to support ERC-165
 */

interface IParametricTokenNzs is IParametricToken {
    // ====== EVENTS ======

    /**
     * @notice Emitted when a non-zero-sum parametric token transfer occurs.
     * @dev The standard ERC-20 `Transfer` event MUST also be emitted using the `creditAmount`.
     *      The base `ParametricTransfer` event SHOULD NOT be emitted for NZS token transfers.
     * @param from The sender address
     * @param fromSubId The sender's sub-account
     * @param to The recipient address
     * @param toSubId The recipient's sub-account
     * @param debitAmount The exact amount deducted from the sender's balance
     * @param creditAmount The exact amount added to the recipient's balance
     * @param incomingParams The full incoming parameter array
     * @param resultingParams The full resulting parameter array
     */
    event ParametricTransferNzs(
        address indexed from,
        uint48 indexed fromSubId,
        address indexed to,
        uint48 toSubId,
        uint256 debitAmount,
        uint256 creditAmount,
        uint64[] incomingParams,
        uint64[] resultingParams
    );
}
