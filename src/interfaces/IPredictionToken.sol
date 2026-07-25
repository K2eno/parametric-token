// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./IParametricToken.sol";

interface IPredictionToken is IParametricToken {
    function mint(
        address to,
        uint256 amount,
        uint64 predictionPrice,
        uint64 round
    ) external;
    function burn(address from, uint48 subId, uint256 amount) external;
    function setMaxRounds(uint64 maxRounds) external;
}
