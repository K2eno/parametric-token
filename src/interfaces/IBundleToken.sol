// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./IParametricTokenNzs.sol";

interface IBundleToken is IParametricTokenNzs {
    // ====== FUNCTIONS ======

    function mint(address to, uint256 amount, uint64 anchor) external;
    function burn(address from, uint48 subId, uint256 amount) external;

    // ====== GETTERS ======

    function anchor(
        address account,
        uint48 subId
    ) external view returns (uint64);
}
