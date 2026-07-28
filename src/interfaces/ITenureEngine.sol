// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ITenureEngine {
    // ====== EVENTS ======

    event FeeRateUpdated(uint256 newFeeRate);
    event TokenSet(address indexed token);

    // ====== FUCNTIONS ======

    function mint(address to, uint256 amount) external;
    function redeem(address from, uint48 subId, uint256 amount) external;
    function pointsEarned(address account) external view returns (uint256);
}
