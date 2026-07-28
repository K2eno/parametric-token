// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IBundleEngine {
    // ====== EVENTS ======

    event Deposited(
        address indexed account,
        uint256 wbtcAmount,
        uint256 invAmount,
        uint256 bunMinted,
        uint64 anchor
    );
    event Redeemed(
        address indexed account,
        uint48 indexed subId,
        uint256 bunBurned,
        uint256 wbtcReturned,
        uint256 invReturned
    );
    event PriceUpdated(uint256 newPrice);

    // ====== FUNCTIONS ======

    function updateIndexPrice(uint64 range) external;
    function deposit(uint256 wbtcAmount, uint256 invAmount) external;
    function redeem(uint256 bunAmount, uint48 subId) external;

    // ====== GETTERS ======

    function indexPrice() external view returns (uint64);
}
