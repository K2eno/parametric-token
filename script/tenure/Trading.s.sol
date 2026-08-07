// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/StdJson.sol";

import "../../src/tenure/TenureToken.sol";
import "../../src/tenure/TenureEngine.sol";

contract TenureTrading is Script {
    uint256 constant ADMIN_PK =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant TRADER1_PK =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant TRADER2_PK =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant TRADER3_PK =
        0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    uint64 constant REWARDS_BASE = 30 days;

    TenureToken internal token;
    TenureEngine internal engine;
    address internal trader1;
    address internal trader2;
    address internal trader3;

    function run() external {
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/out/tenure_deployed_addresses.json"
        );
        string memory json = vm.readFile(path);

        address tokenAddr = stdJson.readAddress(json, ".tenureToken");
        address engineAddr = stdJson.readAddress(json, ".tenureEngine");

        token = TenureToken(tokenAddr);
        engine = TenureEngine(engineAddr);

        trader1 = vm.addr(TRADER1_PK);
        trader2 = vm.addr(TRADER2_PK);
        trader3 = vm.addr(TRADER3_PK);

        console.log("Using Token at:", tokenAddr);
        console.log("Using Engine at:", engineAddr);

        // ---- Initial time ----
        vm.roll(1);
        vm.warp(1000);

        // ---- Mint tokens to traders via engine ----
        uint256 mintAmount = 1000e18; // 1000 tokens each

        // Trader1: mint once
        _mint(trader1, mintAmount);
        console.log(
            "Trader1 minted:",
            token.balanceOf(trader1) / 1e18,
            "tokens"
        );

        // Trader2: mint 2 times
        _mint(trader2, mintAmount);
        _mint(trader2, mintAmount / 2);
        console.log(
            "Trader2 minted:",
            token.balanceOf(trader2) / 1e18,
            "tokens"
        );

        // Trader3: convert to Super and mint to sub0, then transfer to sub1 and sub2
        _nextBlock();
        vm.broadcast(TRADER3_PK);
        token.convertToSuper(trader3);

        _nextBlock();
        vm.broadcast(TRADER3_PK);
        token.createSubAccount(trader3); // subId 1

        _nextBlock();
        vm.broadcast(TRADER3_PK);
        token.createSubAccount(trader3); // subId 2

        console.log("Trader3 converted to Super with 3 sub-accounts.");

        // Mint to sub0 (engine always mints to sub0)
        _mint(trader3, mintAmount);

        // Transfer some to sub1 and sub2
        uint256 sub0Bal = token.parametricBalanceOf(trader3, 0);
        uint256 transferAmount = sub0Bal / 3;
        _nextBlock();
        vm.broadcast(TRADER3_PK);
        token.parametricTransfer(0, trader3, 1, transferAmount);

        _mint(trader3, mintAmount);

        sub0Bal = token.parametricBalanceOf(trader3, 0);
        transferAmount = sub0Bal / 3;
        _nextBlock();
        vm.broadcast(TRADER3_PK);
        token.parametricTransfer(0, trader3, 0, sub0Bal);
        _nextBlock();
        vm.broadcast(TRADER3_PK);
        token.parametricTransfer(0, trader3, 2, transferAmount);

        console.log("Trader3 minted to sub0, transferred to sub1 and sub2.");
        console.log(
            "Trader3 balances: sub0, sub1, sub3:",
            token.parametricBalanceOf(trader3, 0) / 1e18,
            token.parametricBalanceOf(trader3, 1) / 1e18,
            token.parametricBalanceOf(trader3, 2) / 1e18
        );

        // ---- Advance time to accrue rewards ----
        // Wait 30 days + 1 second to get full rewards
        _nextBlock();
        vm.warp(block.timestamp + REWARDS_BASE + 1);
        console.log("Time advanced by", REWARDS_BASE / 1 days, "days + 1 sec.");

        // ---- Traders redeem their tokens ----
        // Trader1 redeems all from sub0
        uint256 trader1Bal = token.balanceOf(trader1);
        _redeem(trader1, 0, trader1Bal);
        console.log("Trader1 redeemed:", trader1Bal / 1e18, "tokens");

        // Trader2 redeems all from sub0
        uint256 trader2Bal = token.balanceOf(trader2);
        _redeem(trader2, 0, trader2Bal);
        console.log("Trader2 redeemed:", trader2Bal / 1e18, "tokens");

        // Trader3 redeems from each sub-account
        uint256 balSub0 = token.parametricBalanceOf(trader3, 0);
        uint256 balSub1 = token.parametricBalanceOf(trader3, 1);
        uint256 balSub2 = token.parametricBalanceOf(trader3, 2);

        _redeem(trader3, 0, balSub0);
        _redeem(trader3, 1, balSub1);
        _redeem(trader3, 2, balSub2);

        console.log("Trader3 redeemed from all sub-accounts.");

        // ---- Check points earned ----
        uint256 points1 = engine.pointsEarned(trader1);
        uint256 points2 = engine.pointsEarned(trader2);
        uint256 points3 = engine.pointsEarned(trader3);

        console.log("Trader1 points earned:", points1 / 1e18);
        console.log("Trader2 points earned:", points2 / 1e18);
        console.log("Trader3 points earned:", points3 / 1e18);

        // ---- Final balances ----
        console.log(
            "Trader1 final token balance:",
            token.balanceOf(trader1) / 1e18
        );
        console.log(
            "Trader2 final token balance:",
            token.balanceOf(trader2) / 1e18
        );
        console.log(
            "Trader3 final token balance:",
            token.balanceOf(trader3) / 1e18
        );
    }

    function _nextBlock() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function _mint(address to, uint256 amount) internal {
        _nextBlock();
        uint256 pk = (to == trader1) ? TRADER1_PK : TRADER2_PK;
        vm.broadcast(pk);
        engine.mint(to, amount);
    }

    function _redeem(address from, uint48 subId, uint256 amount) internal {
        _nextBlock();
        uint256 pk = (from == trader1) ? TRADER1_PK : TRADER2_PK;
        vm.broadcast(pk);
        engine.redeem(from, subId, amount);
    }
}
