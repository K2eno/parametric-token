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

    PredictionToken internal token;
    PredictionEngine internal engine;
    address internal trader1;
    address internal trader2;
    address internal trader3;
    uint64 internal startPrice;

    function run() external {
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/out/deployed_addresses.json"
        );
        string memory json = vm.readFile(path);

        address tokenAddr = stdJson.readAddress(json, ".predictionToken");
        address engineAddr = stdJson.readAddress(json, ".predictionEngine");

        token = PredictionToken(tokenAddr);
        engine = PredictionEngine(engineAddr);

        // address admin = vm.addr(ADMIN_PK);
        trader1 = vm.addr(TRADER1_PK);
        trader2 = vm.addr(TRADER2_PK);
        trader3 = vm.addr(TRADER3_PK);

        console.log("Using Token at:", tokenAddr);
        console.log("Using Engine at:", engineAddr);

        // ---------- Step 1: Warp to start time ----------
        vm.roll(1);

        // ---------- Step 2: Wallet4 (trader3) converts to Super and adds sub-accounts ----------
        _nextBlock();
        vm.broadcast(TRADER3_PK);
        token.convertToSuper(trader3);

        _nextBlock();
        vm.broadcast(TRADER3_PK);
        token.createSubAccount(trader3); // subId 1

        _nextBlock();
        vm.broadcast(TRADER3_PK);
        token.createSubAccount(trader3); // subId 2

        console.log(
            "Trader3 converted to Super with sub-accounts:",
            token.subsCountOf(trader3)
        );

        // ---------- Step 3: Mint tokens with different predictions ----------
        startPrice = engine.getStartPrice();

        // Mint for trader1: two mints (different predictions) – will average
        uint64 price1 = _randomPrice(2000e8, 1);
        uint64 price2 = _randomPrice(3000e8, 2);
        uint256 amount = 1000e18; // 1000 tokens

        _mint(trader1, amount, price1, ROUND);
        _mint(trader1, amount, price2, ROUND);
        console.log(
            "Trader1 mint: balance and prediction:",
            token.balanceOf(trader1) / 1e18,
            token.parameterOf(0, trader1, 0) / 1e8
        );

        // Mint for trader2: two mints (different predictions)
        uint64 price3 = _randomPrice(2000e8, 3);
        uint64 price4 = _randomPrice(3000e8, 4);

        _mint(trader2, amount, price3, ROUND);
        _mint(trader2, amount / 2, price4, ROUND);
        console.log(
            "Trader2 mint: balance and prediction:",
            token.balanceOf(trader2) / 1e18,
            token.parameterOf(0, trader2, 0) / 1e8
        );

        // Mint for trader3 (wallet4) on sub0, sub1, sub2 with different predictions
        uint64 price5 = _randomPrice(4000e8, 5);
        uint64 price6 = _randomPrice(3000e8, 6);
        uint64 price7 = _randomPrice(2000e8, 7);

        // For sub0, mint twice to average
        _mint(trader3, amount * 2, price5, ROUND);

        _nextBlock();
        vm.broadcast(TRADER3_PK);
        token.parametricTransfer(0, trader3, 1, amount); // transfer to sub1

        _mint(trader3, amount, price6, ROUND);

        uint256 sub0Balance = token.parametricBalanceOf(trader3, 0);
        uint256 transferAmount = sub0Balance / 3;

        _nextBlock();
        vm.broadcast(TRADER3_PK);
        token.parametricTransfer(0, trader3, 2, transferAmount);

        _mint(trader3, amount, price7, ROUND);

        console.log(
            "Trader3 mint: total balance:",
            token.balanceOf(trader3) / 1e18
        );
        console.log(
            "Trader3 mint: balance and prediction sub0:",
            token.parametricBalanceOf(trader3, 0) / 1e18,
            token.parameterOf(0, trader3, 0) / 1e8
        );
        console.log(
            "Trader3 mint: balance and prediction sub1:",
            token.parametricBalanceOf(trader3, 1) / 1e18,
            token.parameterOf(0, trader3, 1) / 1e8
        );
        console.log(
            "Trader3 mint: balance and prediction sub2:",
            token.parametricBalanceOf(trader3, 2) / 1e18,
            token.parameterOf(0, trader3, 2) / 1e8
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
        _report(TRADER1_PK, 0, ROUND);
        _report(TRADER2_PK, 0, ROUND);
        _report(TRADER3_PK, 0, ROUND);
        _report(TRADER3_PK, 1, ROUND);
        _report(TRADER3_PK, 2, ROUND);

        console.log("All reports submitted.");

        // ---------- Step 7: Admin closes reporting ----------
        _nextBlock();
        vm.broadcast(ADMIN_PK);
        engine.closeReporting(ROUND);

        console.log("Reporting closed, claiming phase started.");

        // ---------- Step 8: Traders claim ----------
        _claim(TRADER1_PK, 0, ROUND);
        _claim(TRADER2_PK, 0, ROUND);
        _claim(TRADER3_PK, 0, ROUND);
        _claim(TRADER3_PK, 1, ROUND);
        _claim(TRADER3_PK, 2, ROUND);

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

        _mint(trader3, amount, price7, NEXT_ROUND);
        console.log(
            "Trader3 mint: balance and prediction sub0:",
            token.parametricBalanceOf(trader3, 0) / 1e18,
            token.parameterOf(0, trader3, 0) / 1e8
        );
    }

    function _nextBlock() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function _randomPrice(
        uint64 range,
        uint8 seed
    ) internal view returns (uint64) {
        require(range < startPrice);
        uint256 random = uint256(
            keccak256(abi.encodePacked(block.timestamp, range, seed))
        );
        return uint64(startPrice - range / 2 + (random % range));
    }

    function _mint(
        address to,
        uint256 amount,
        uint64 price,
        uint64 round
    ) internal {
        _nextBlock();
        vm.broadcast(
            to == trader1
                ? TRADER1_PK
                : (to == trader2 ? TRADER2_PK : TRADER3_PK)
        );
        token.mint(to, amount, price, round);
    }

    function _report(uint256 pk, uint48 subId, uint64 round) internal {
        _nextBlock();
        vm.broadcast(pk);
        engine.report(round, subId);
    }

    function _claim(uint256 pk, uint48 subId, uint64 round) internal {
        _nextBlock();
        vm.broadcast(pk);
        engine.claim(round, subId);
    }
}
