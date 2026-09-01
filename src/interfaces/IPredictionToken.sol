// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./spec/IParametricToken.sol";
import "./spec/IParametricPermissions.sol";

interface IPredictionToken is
    IERC20Metadata,
    IERC165,
    IParametricToken,
    IParametricPermissions
{
    // ====== FUNCTIONS ======

    function mint(
        address to,
        uint256 amount,
        uint64 predictionPrice,
        uint64 round
    ) external;
    function burn(address from, uint48 fromSubId, uint256 amount) external;

    // ====== SETTERS ======

    function setEngine(address engine_) external;
    function setMaxRounds(uint64 maxRounds) external;

    // ====== GETTERS ======

    function allParametersOf(
        address account,
        uint48 subId
    ) external view returns (uint64[] memory);
    function prediction(
        address account,
        uint48 subId
    ) external view returns (uint64);
    function round(
        address account,
        uint48 subId
    ) external view returns (uint64);
    function engine() external view returns (address);
    function maxRounds() external view returns (uint64);
}
