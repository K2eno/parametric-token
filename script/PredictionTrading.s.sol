// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/StdJson.sol";

import "../src/implementations/PredictionToken.sol";
import "../src/implementations/PredictionEngine.sol";

contract PredictionTrading is Script {
    uint256 constant ADMIN_PK =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant TRADER1_PK =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant TRADER2_PK =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant TRADER3_PK =
        0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    uint64 constant ROUND_DURATION = 3600;
    uint64 constant ROUND = 0;
    uint64 constant NEXT_ROUND = ROUND + 1;

    function run() external {
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/out/deployed_addresses.json"
        );
        string memory json = vm.readFile(path);

        address tokenAddr = stdJson.readAddress(json, ".predictionToken");
        address engineAddr = stdJson.readAddress(json, ".predictionEngine");

        PredictionToken token = PredictionToken(tokenAddr);
        PredictionEngine engine = PredictionEngine(engineAddr);

        // address admin = vm.addr(ADMIN_PK);
        address trader1 = vm.addr(TRADER1_PK);
        address trader2 = vm.addr(TRADER2_PK);
        address trader3 = vm.addr(TRADER3_PK);

        console.log("Using Token at:", tokenAddr);
        console.log("Using Engine at:", engineAddr);

        // ---------- Step 1: Warp to start time ----------
        vm.roll(1);

        // ---------- Step 2: Wallet4 (trader3) converts to Super and adds sub-accounts ----------
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        token.convertToSuper(trader3);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        token.createSubAccount(trader3); // subId 1

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        token.createSubAccount(trader3); // subId 2

        console.log(
            "Trader3 converted to Super with sub-accounts:",
            token.subsCountOf(trader3)
        );

        // ---------- Step 3: Mint tokens with different predictions ----------
        uint64 startPrice = engine.getStartPrice();

        // Mint for trader1: two mints (different predictions) – will average
        uint64 price1 = randomPrice(startPrice, 2000e8, 1);
        uint64 price2 = randomPrice(startPrice, 3000e8, 2);
        uint256 amount = 1000e18; // 1000 tokens

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER1_PK);
        token.mint(trader1, amount, price1, ROUND);
        console.log("Timestamp:", block.timestamp);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER1_PK);
        token.mint(trader1, amount, price2, ROUND);
        console.log(
            "Trader1 mint: balance and prediction:",
            token.balanceOf(trader1) / 1e18,
            token.getPredictionPrice(trader1, 0) / 1e8
        );
        console.log("Timestamp:", block.timestamp);

        // Mint for trader2: two mints (different predictions)
        uint64 price3 = randomPrice(startPrice, 2000e8, 3);
        uint64 price4 = randomPrice(startPrice, 3000e8, 4);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER2_PK);
        token.mint(trader2, amount, price3, ROUND);
        console.log("Timestamp:", block.timestamp);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER2_PK);
        token.mint(trader2, amount / 2, price4, ROUND);
        console.log(
            "Trader2 mint: balance and prediction:",
            token.balanceOf(trader2) / 1e18,
            token.getPredictionPrice(trader2, 0) / 1e8
        );
        console.log("Timestamp:", block.timestamp);

        // Mint for trader3 (wallet4) on sub0, sub1, sub2 with different predictions
        uint64 price5 = randomPrice(startPrice, 4000e8, 5);
        uint64 price6 = randomPrice(startPrice, 3000e8, 6);
        uint64 price7 = randomPrice(startPrice, 2000e8, 7);

        // For sub0, mint twice to average
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        token.mint(trader3, amount * 2, price5, ROUND); // mints to sub0 (default)
        console.log("Timestamp:", block.timestamp);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        token.parametricTransfer(0, trader3, 1, amount); // transfer to sub1
        console.log("Timestamp:", block.timestamp);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        token.mint(trader3, amount, price6, ROUND); // sub0 gets averaged
        console.log("Timestamp:", block.timestamp);

        uint256 sub0Balance = token.parametricBalanceOf(trader3, 0);
        uint256 transferAmount = sub0Balance / 3;

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        token.parametricTransfer(0, trader3, 2, transferAmount);
        console.log("Timestamp:", block.timestamp);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        token.mint(trader3, amount, price7, ROUND); // sub0 gets averaged
        console.log("Timestamp:", block.timestamp);

        console.log(
            "Trader3 mint: total balance:",
            token.balanceOf(trader3) / 1e18
        );
        console.log(
            "Trader3 mint: balance and prediction sub0:",
            token.parametricBalanceOf(trader3, 0) / 1e18,
            token.getPredictionPrice(trader3, 0) / 1e8
        );
        console.log(
            "Trader3 mint: balance and prediction sub1:",
            token.parametricBalanceOf(trader3, 1) / 1e18,
            token.getPredictionPrice(trader3, 1) / 1e8
        );
        console.log(
            "Trader3 mint: balance and prediction sub2:",
            token.parametricBalanceOf(trader3, 2) / 1e18,
            token.getPredictionPrice(trader3, 2) / 1e8
        );

        console.log("Minting completed for all traders.");

        // ---------- Step 4: Advance time past round end ----------
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + ROUND_DURATION + 1);

        // ---------- Step 5: Admin closes round with a range ----------
        uint64 range = 2000e8;
        vm.broadcast(ADMIN_PK);
        engine.closeRound(ROUND, range);

        console.log("Round closed, assetPrice set.");

        // ---------- Step 6: Traders report (burn tokens) ----------
        // Trader1 reports from sub0
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER1_PK);
        engine.report(ROUND, 0);

        // Trader2 reports from sub0
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER2_PK);
        engine.report(ROUND, 0);

        // Trader3 reports from sub0, sub1, sub2
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        engine.report(ROUND, 0);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        engine.report(ROUND, 1);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        engine.report(ROUND, 2);

        console.log("All reports submitted.");

        // ---------- Step 7: Admin closes reporting ----------
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(ADMIN_PK);
        engine.closeReporting(ROUND);

        console.log("Reporting closed, claiming phase started.");

        // ---------- Step 8: Traders claim ----------
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER1_PK);
        engine.claim(ROUND, 0);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER2_PK);
        engine.claim(ROUND, 0);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        engine.claim(ROUND, 0);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        engine.claim(ROUND, 1);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        engine.claim(ROUND, 2);

        console.log("All claims completed.");

        // ---------- Step 9: Check points ----------
        console.log(
            "Trader1 points:",
            engine.getPointsEarned(ROUND, trader1) / 1e18
        );
        console.log(
            "Trader2 points:",
            engine.getPointsEarned(ROUND, trader2) / 1e18
        );
        console.log(
            "Trader3 points:",
            engine.getPointsEarned(ROUND, trader3) / 1e18
        );

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        vm.broadcast(TRADER3_PK);
        token.mint(trader3, amount, price7, NEXT_ROUND);
        console.log(
            "Trader3 mint: balance and prediction sub0:",
            token.parametricBalanceOf(trader3, 0) / 1e18,
            token.getPredictionPrice(trader3, 0) / 1e8
        );
    }

    function randomPrice(
        uint64 startPrice,
        uint64 range,
        uint8 seed
    ) private view returns (uint64) {
        require(range < startPrice);
        uint256 random = uint256(
            keccak256(abi.encodePacked(block.timestamp, range, seed))
        );
        return uint64(startPrice - range / 2 + (random % range));
    }
}
