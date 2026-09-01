// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./spec/IParametricToken.sol";

interface ITenureToken is IERC20Metadata, IERC165, IParametricToken {
    // ====== FUNCTIONS ======

    function mint(address to, uint256 amount) external;
    function burn(address from, uint48 subId, uint256 amount) external;

    // ====== SETTERS ======

    function setEngine(address engine_) external;

    // ====== GETTERS ======

    function mintTime(
        address account,
        uint48 subId
    ) external view returns (uint64);
    function engine() external view returns (address);
}
