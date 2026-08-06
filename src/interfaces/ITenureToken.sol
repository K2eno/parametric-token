// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./IParametricToken.sol";

interface ITenureToken is IParametricToken {
    // ====== FUNCTIONS ======

    function mint(address to, uint256 amount) external;
    function burn(address from, uint48 subId, uint256 amount) external;

    // ====== GETTERS ======

    function mintTime(
        address account,
        uint48 subId
    ) external view returns (uint64);
}
