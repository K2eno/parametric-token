// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/ITenureToken.sol";
import "../interfaces/ITenureEngine.sol";

contract TenureEngine is ITenureEngine {
    ITenureToken private _tokenContract;
    uint256 private _feeRateBps;

    // Events
    event FeeRateUpdated(uint256 newFeeRate);
    event TokenSet(address indexed token);

    uint256 public constant FEE_BASE = 30 days;
    mapping(address => uint256) private _pointsEarned;

    // Constructor
    constructor(address token, uint256 feeRateBps) {
        require(token != address(0), "Zero token");
        _tokenContract = ITenureToken(token);
        feeRateBps = feeRateBps;
    }

    // Mint
    function mint(address to, uint256 amount) external {
        require(amount > 0, "Void amount");
        _tokenContract.mint(to, amount);
    }

    // Redeem with fee
    function redeem(address from, uint48 subId, uint256 amount) external {
        require(amount > 0, "Void amount");

        // Get mintTime for the sub-account
        uint64 mintTime = _tokenContract.getMintTime(from, subId);
        uint256 age = block.timestamp - mintTime; // age in seconds

        // Token holders can redeem token to earn points
        // Points are equal token amount less progressive age dependent fee
        uint256 fee = (amount * _feeRateBps * age) / (10000 * FEE_BASE);
        uint256 finalFee = fee > amount ? amount : fee;

        _pointsEarned[from] += amount - finalFee;

        // Burn the amount from the user
        _tokenContract.burn(from, subId, amount);
    }

    function pointsEarned(address account) external view returns (uint256) {
        return _pointsEarned[account];
    }
}
