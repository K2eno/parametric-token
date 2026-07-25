// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ITenureEngine {
    function mint(address to, uint256 amount) external;
    function redeem(address from, uint48 subId, uint256 amount) external;
    function pointsEarned(address account) external view returns (uint256);
}
