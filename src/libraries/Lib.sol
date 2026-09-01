// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library Lib {
    function weightedAverage(
        uint64 fromParam,
        uint256 fromAmount,
        uint64 toParam,
        uint256 toAmount
    ) external pure returns (uint64) {
        require(fromParam > 0 && fromAmount > 0, "Invalid values");
        if (fromParam == toParam) return fromParam;
        uint256 productSum =
            uint256(fromParam) * fromAmount + uint256(toParam) * toAmount;
        uint256 sum = fromAmount + toAmount;
        return uint64(productSum / sum);
    }

    function combine(
        uint64 fromAnchor,
        uint256 fromAmount,
        uint64 toAnchor,
        uint256 toBalance
    ) external pure returns (uint64 newAnchor, uint256 newBalance) {
        // If either balance is zero, return the other
        if (fromAmount == 0) return (toAnchor, toBalance);
        if (toBalance == 0) return (fromAnchor, fromAmount);

        // If anchors are equal, simple sum
        if (fromAnchor == toAnchor) return (fromAnchor, fromAmount + toBalance);

        // Convert to uint256 for arithmetic
        uint256 anchor1 = uint256(fromAnchor);
        uint256 anchor2 = uint256(toAnchor);

        // Compute numerator = b1*a1 + b2*a2
        uint256 numerator = fromAmount * anchor1 + toBalance * anchor2;

        // Compute denominator = b1/a1 + b2/a2 = (b1*a2 + b2*a1) / (a1*a2)
        uint256 productSum = fromAmount * anchor2 + toBalance * anchor1;
        uint256 product = anchor1 * anchor2;

        // newAnchor^2 = numerator * product / productSum
        uint256 squared = (numerator * product) / productSum;

        // Compute integer square root (anchor has 8 decimals)
        uint256 resultAnchor = sqrt(squared);

        // newBalance = (productSum / product) * resultAnchor
        newBalance = (productSum * resultAnchor) / product;
        newAnchor = uint64(resultAnchor);
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
