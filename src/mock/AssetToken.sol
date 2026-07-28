// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AssetToken is ERC20 {
    uint256 private _maxMint;

    constructor(
        string memory name,
        string memory symbol,
        uint maxMintEth
    ) ERC20(name, symbol) {
        _maxMint = maxMintEth * 1e18;
    }

    function mint(uint amount) public {
        require(amount <= _maxMint);
        _mint(msg.sender, amount);
    }

    function maxMint() external view returns (uint256) {
        return _maxMint;
    }
}
