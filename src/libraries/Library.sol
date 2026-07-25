// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library Lib {
    function weightedAverage(
        uint64 param1,
        uint256 amount1,
        uint64 param2,
        uint256 amount2
    ) external pure returns (uint64) {
        require(param1 > 0 && amount1 > 0, "Invalid values");
        uint256 product = uint256(param1) * amount1 + uint256(param2) * amount2;
        uint256 sum = amount1 + amount2;
        return uint64(product / sum);
    }
}
