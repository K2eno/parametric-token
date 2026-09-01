// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/ITenureToken.sol";
import "../interfaces/ITenureEngine.sol";

contract TenureEngine is Ownable, ITenureEngine {
    // ====== CONSTANTS ======

    uint64 public constant REWARDS_BASE = 30 days;

    // ====== STATE ======

    ITenureToken private _token;

    uint64 private _rewardsRateBps;
    mapping(address => uint256) private _pointsEarned;

    // ====== CONSTRUCTOR ======

    constructor(address token, uint64 rewardsRateBps_) Ownable(msg.sender) {
        require(token != address(0), "Zero token");
        _token = ITenureToken(token);
        _rewardsRateBps = rewardsRateBps_;
    }

    // ====== FUNCTIONS ======s

    // Mint
    function mint(address to, uint256 amount) external {
        require(amount > 0, "Void amount");
        _token.mint(to, amount);
    }

    // Redeem and get age-based rewards
    function redeem(address from, uint48 subId, uint256 amount) external {
        require(amount > 0, "Void amount");

        // Get mintTime for the sub-account
        uint64 mintTime = _token.mintTime(from, subId);
        uint256 age = block.timestamp - mintTime; // age in seconds

        // Points are proportional to token amount and age
        uint256 rewards =
            (amount * _rewardsRateBps * age) / (10000 * REWARDS_BASE);

        _pointsEarned[from] += rewards;

        _token.burn(from, subId, amount);
    }

    // ====== GETTERS ======

    function pointsEarned(address account) external view returns (uint256) {
        return _pointsEarned[account];
    }

    function rewardsRateBps() external view returns (uint64) {
        return _rewardsRateBps;
    }
}
