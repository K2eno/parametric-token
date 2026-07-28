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

    function combine(
        uint64 a1,
        uint256 b1,
        uint64 a2,
        uint256 b2
    ) external pure returns (uint64 newAnchor, uint256 newBalance) {
        // If either balance is zero, return the other
        if (b1 == 0) return (a2, b2);
        if (b2 == 0) return (a1, b1);

        // If anchors are equal, simple sum
        if (a1 == a2) return (a1, b1 + b2);

        // Convert to uint256 for arithmetic
        uint256 anchor1 = uint256(a1);
        uint256 anchor2 = uint256(a2);

        // Compute numerator = b1*a1 + b2*a2
        uint256 numerator = b1 * anchor1 + b2 * anchor2;

        // Compute denominator = b1/a1 + b2/a2 = (b1*a2 + b2*a1) / (a1*a2)
        uint256 productSum = b1 * anchor2 + b2 * anchor1;
        uint256 product = anchor1 * anchor2;

        // newAnchor^2 = numerator * product / productSum
        uint256 squared = (numerator * product) / productSum;

        // Compute integer square root (anchor has 8 decimals)
        uint256 anchor3 = sqrt(squared);

        // newBalance = (productSum / product) * a3
        newBalance = (productSum * anchor3) / product;
        newAnchor = uint64(anchor3);
    }

    // Babylonian square root (rounded down) for uint256
    function sqrt(uint256 x) public pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}
