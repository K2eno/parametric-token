// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/StdJson.sol";

import "../../src/mock/AssetToken.sol";
import "../../src/bundle/BundleToken.sol";
import "../../src/bundle/BundleEngine.sol";

contract BundleTrading is Script {
    uint256 constant ADMIN_PK =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant TRADER1_PK =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant TRADER2_PK =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant TRADER3_PK =
        0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    AssetToken internal wbtc;
    AssetToken internal inv;
    BundleToken internal bundle;
    BundleEngine internal engine;

    address internal trader1;
    address internal trader2;
    address internal trader3;

    function run() external {
        // Read deployed addresses
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/out/bundle_deployed_addresses.json"
            )
        );
        address wbtcAddr = stdJson.readAddress(json, ".wbtc");
        address invAddr = stdJson.readAddress(json, ".inv");
        address bundleAddr = stdJson.readAddress(json, ".bundleToken");
        address engineAddr = stdJson.readAddress(json, ".bundleEngine");

        wbtc = AssetToken(wbtcAddr);
        inv = AssetToken(invAddr);
        bundle = BundleToken(bundleAddr);
        engine = BundleEngine(engineAddr);

        trader1 = vm.addr(TRADER1_PK);
        trader2 = vm.addr(TRADER2_PK);
        trader3 = vm.addr(TRADER3_PK);

        console.log("Using WBTC:", wbtcAddr);
        console.log("Using INV:", invAddr);
        console.log("Using BundleToken:", bundleAddr);
        console.log("Using BundleEngine:", engineAddr);

        // ---- Initial time ----
        vm.roll(1);

        // ---- Admin mints initial WBTC and INV to traders ----
        uint256 wbtcMintAmount = 0.5e18;
        uint256 invMintAmount = 5000e18;
        _mintTo(wbtc, trader1, wbtcMintAmount);
        _mintTo(wbtc, trader2, wbtcMintAmount);
        _mintTo(wbtc, trader3, wbtcMintAmount);
        _mintTo(inv, trader1, invMintAmount);
        _mintTo(inv, trader2, invMintAmount);
        _mintTo(inv, trader3, invMintAmount);
        console.log("Minted WBTC and INV to all traders.");

        // ---- Trader1: 2 deposits, 2 redeems ----
        _deposit(trader1, 0.1e18, 200e18);
        _deposit(trader1, 0.15e18, 400e18);

        uint bunBalance1 = bundle.parametricBalanceOf(trader1, 0);
        _redeem(trader1, 0, bunBalance1 / 3);
        _redeem(trader1, 0, bunBalance1 / 6);

        // ---- Admin updates price ----
        _updatePrice(2300e8);
        console.log("Price updated to:", engine.indexPrice() / 1e8);

        // ---- Trader2: 2 deposits, 2 redeems ----
        _deposit(trader2, 0.05e18, 150e18);
        _deposit(trader2, 0.35e18, 3200e18);

        uint bunBalance2 = bundle.parametricBalanceOf(trader2, 0);
        _redeem(trader2, 0, bunBalance2 / 2);
        _redeem(trader2, 0, bunBalance2 / 2);

        // ---- Admin updates price again ----
        _updatePrice(1500e8);
        console.log("Price updated to:", engine.indexPrice() / 1e8);

        // ---- Trader3: convert to Super, then deposits to sub0, sub1, sub2, and redeems ----
        _nextBlock();
        vm.broadcast(TRADER3_PK);
        bundle.convertToSuper(trader3);
        _nextBlock();
        vm.broadcast(TRADER3_PK);
        bundle.createSubAccount(trader3); // subId 1
        _nextBlock();
        vm.broadcast(TRADER3_PK);
        bundle.createSubAccount(trader3); // subId 2
        console.log("Trader3 converted to Super with 3 sub-accounts.");

        _depositToSub(trader3, 2, 0.11e18, 850e18);
        _depositToSub(trader3, 1, 0.08e18, 2200e18);
        _depositToSub(trader3, 0, 0.22e18, 1200e18);

        uint bunBalance3 = bundle.parametricBalanceOf(trader3, 0);
        _redeemFromSub(trader3, 0, bunBalance3);

        uint bunBalance4 = bundle.parametricBalanceOf(trader3, 1);
        _redeemFromSub(trader3, 1, bunBalance4 / 2);

        uint bunBalance5 = bundle.parametricBalanceOf(trader3, 2);
        _redeemFromSub(trader3, 2, bunBalance5 / 3);

        // Final summary
        console.log("===== FINAL BALANCES =====");
        _logBalances(trader1);
        _logBalances(trader2);
        _logBalances(trader3);
    }

    // Helpers

    function _nextBlock() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function _mintTo(AssetToken token, address to, uint256 amount) internal {
        _nextBlock();
        vm.broadcast(ADMIN_PK);
        token.mint(amount);
        // The mint function mints to msg.sender (admin), so we need to transfer to trader.
        _nextBlock();
        vm.broadcast(ADMIN_PK);
        token.transfer(to, amount);
    }

    function _updatePrice(uint64 range) internal {
        _nextBlock();
        vm.broadcast(ADMIN_PK);
        engine.updateIndexPrice(range);
    }

    function _deposit(
        address trader,
        uint256 wbtcAmount,
        uint256 invAmount
    ) internal {
        uint256 pk = _getPK(trader);
        // Approve spending
        _nextBlock();
        vm.broadcast(pk);
        wbtc.approve(address(engine), wbtcAmount);
        _nextBlock();
        vm.broadcast(pk);
        inv.approve(address(engine), invAmount);
        // Deposit
        _nextBlock();
        vm.broadcast(pk);
        engine.deposit(wbtcAmount, invAmount);
        console.log(
            "Deposited: WBTC:",
            wbtcAmount / 1e18,
            "INV:",
            invAmount / 1e18
        );
    }

    function _depositToSub(
        address trader,
        uint48 subId,
        uint256 wbtcAmount,
        uint256 invAmount
    ) internal {
        // Deposit to sub0 first, then transfer to target subId
        // Since deposit always mints to sub0, we need to transfer the BUN to the target subId.
        // First do a normal deposit to sub0.
        _deposit(trader, wbtcAmount, invAmount);
        // Then transfer BUN from sub0 to target subId.
        uint256 bunBalance = bundle.parametricBalanceOf(trader, 0);
        if (bunBalance > 0 && subId > 0) {
            _nextBlock();
            vm.broadcast(_getPK(trader));
            bundle.parametricTransfer(0, trader, subId, bunBalance);
            console.log(
                "Transferred BUN from sub0 to sub",
                subId,
                bunBalance / 2
            );
        }
    }

    function _redeem(address trader, uint48 subId, uint256 bunAmount) internal {
        uint256 pk = _getPK(trader);
        _nextBlock();
        vm.broadcast(pk);
        engine.redeem(bunAmount, subId);
        console.log("Redeemed from sub", subId, "BUN:", bunAmount / 1e18);
    }

    function _redeemFromSub(
        address trader,
        uint48 subId,
        uint256 bunAmount
    ) internal {
        _redeem(trader, subId, bunAmount);
    }

    function _getPK(address trader) internal pure returns (uint256) {
        if (trader == vm.addr(TRADER1_PK)) return TRADER1_PK;
        if (trader == vm.addr(TRADER2_PK)) return TRADER2_PK;
        if (trader == vm.addr(TRADER3_PK)) return TRADER3_PK;
        revert("Unknown trader");
    }

    function _logBalances(address trader) internal view {
        uint256 w = wbtc.balanceOf(trader);
        uint256 i = inv.balanceOf(trader);
        uint256 b = bundle.balanceOf(trader);
        console.log("Trader", trader, "WBTC:", w / 1e18);
        console.log("INV:", i / 1e18, "BUN:", b / 1e18);
        // Also log sub-account balances if super
        if (bundle.accountType(trader) == IParametricToken.AccountType.Super) {
            uint48 count = bundle.subsCountOf(trader);
            for (uint48 s = 0; s < count; s++) {
                uint256 subBal = bundle.parametricBalanceOf(trader, s);
                uint64 anchor = bundle.parameterOf(0, trader, s);
                console.log(
                    "sub, balance and anchor",
                    s,
                    subBal / 1e18,
                    anchor / 1e8
                );
            }
        }
    }
}
