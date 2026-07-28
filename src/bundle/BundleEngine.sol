// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IBundleToken.sol";
import "../interfaces/IBundleEngine.sol";
import "../libraries/Lib.sol";

contract BundleEngine is Ownable, IBundleEngine {
    // ====== CONSTANTS ======

    uint256 public constant K = 100000; // constant in inverse price formula
    uint256 public constant PRICE_DECIMALS = 8; // all prices have 8 decimals
    uint256 public constant TOKEN_DECIMALS = 18; // all tokens have 18 decimals
    uint64 public constant MIN_DIFF = 10e8;

    // ====== STATE ======

    IBundleToken private _token;
    IERC20 private _wbtc;
    IERC20 private _inv;

    uint64 private _indexPrice; // WBTC price

    // ====== CONSTRUCTOR ======

    constructor(
        address bundleToken,
        address wbtc,
        address inv,
        uint64 initialPrice // 8 decimal
    ) Ownable(msg.sender) {
        require(bundleToken != address(0), "Zero bundle token");
        require(wbtc != address(0), "Zero WBTC");
        require(inv != address(0), "Zero INV");
        require(initialPrice > 0, "Zero initial price");

        _token = IBundleToken(bundleToken);
        _wbtc = IERC20(wbtc);
        _inv = IERC20(inv);
        _indexPrice = initialPrice;
    }

    // ====== FUNCTIONS ======

    // Admin functions
    function updateIndexPrice(uint64 range) external onlyOwner {
        require(range > MIN_DIFF && range < _indexPrice, "Invalid range");
        uint64 minPrice = _indexPrice - range / 2;

        uint256 random = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao))
        );
        _indexPrice = uint64((random % range) + minPrice);

        emit PriceUpdated(_indexPrice);
    }

    // Deposits
    // User deposits WBTC and INV, receives BUN tokens minted to sub-account 0.
    function deposit(uint256 wbtcAmount, uint256 invAmount) external {
        require(wbtcAmount > 0 && invAmount > 0, "Zero deposit");

        // Transfer tokens from user to this contract
        if (wbtcAmount > 0) {
            require(
                _wbtc.transferFrom(msg.sender, address(this), wbtcAmount),
                "WBTC transfer failed"
            );
        }
        if (invAmount > 0) {
            require(
                _inv.transferFrom(msg.sender, address(this), invAmount),
                "INV transfer failed"
            );
        }

        // Compute anchor and BUN amount to mint
        (uint64 anchor, uint256 bunAmount) = _computeMintValues(
            wbtcAmount,
            invAmount
        );

        // Mint BUN to user (sub-account 0)
        _token.mint(msg.sender, bunAmount, anchor);

        emit Deposited(msg.sender, wbtcAmount, invAmount, bunAmount, anchor);
    }

    // Redemption
    // User burns BUN from a specific sub-account and receives underlying WBTC and INV.
    function redeem(uint256 bunAmount, uint48 subId) external {
        require(bunAmount > 0, "Zero amount");

        // Get the anchor of the user's sub-account
        uint64 anchor = _token.parameterOf(0, msg.sender, subId);
        require(anchor > 0, "Zero anchor");

        // Compute the underlying WBTC and INV amounts for the burned BUN
        (uint256 wbtcReturn, uint256 invReturn) = _computeAssetsAmounts(
            bunAmount,
            anchor
        );

        // Burn the BUN tokens
        _token.burn(msg.sender, subId, bunAmount);

        // Transfer underlying assets to user
        if (wbtcReturn > 0) {
            require(
                _wbtc.transfer(msg.sender, wbtcReturn),
                "WBTC transfer failed"
            );
        }
        if (invReturn > 0) {
            require(
                _inv.transfer(msg.sender, invReturn),
                "INV transfer failed"
            );
        }

        emit Redeemed(msg.sender, subId, bunAmount, wbtcReturn, invReturn);
    }

    // ====== HELPERS ======

    // Compute anchor and BUN amount from deposit of WBTC and INV
    function _computeMintValues(
        uint256 wbtcAmount,
        uint256 invAmount
    ) private pure returns (uint64 anchor, uint256 bunAmount) {
        require(wbtcAmount > 0 && invAmount > 0, "Both zero");

        // Anchor = sqrt( (K * invAmount) / wbtcAmount )
        // K = 100000 (no decimals)
        uint256 numerator = K * invAmount; // 100000 * invAmount
        uint256 squared = (numerator * 10 ** (2 * PRICE_DECIMALS)) / wbtcAmount;
        anchor = uint64(Lib.sqrt(squared));

        // BUN amount = 2 * sqrt(K * wbtcAmount * invAmount)
        uint256 product = K * wbtcAmount * invAmount;
        bunAmount = 2 * Lib.sqrt(product); // 18 decimals
    }

    // Compute WBTC and INV amounts for a given BUN amount and anchor
    function _computeAssetsAmounts(
        uint256 bunAmount,
        uint64 anchor
    ) private pure returns (uint256 wbtcAmount, uint256 invAmount) {
        require(anchor > 0, "Zero anchor");

        // WBTC amount = b * 10^PRICE_DECIMALS / (2 * anchor)
        wbtcAmount = (bunAmount * 10 ** PRICE_DECIMALS) / (2 * anchor);

        // INV amount = b * anchor / (2 * K * 10 ** PRICE_DECIMALS)
        invAmount = (bunAmount * anchor) / (2 * K * 10 ** PRICE_DECIMALS);
    }

    // ====== GETTERS ======

    function indexPrice() external view returns (uint64) {
        return _indexPrice;
    }
}
