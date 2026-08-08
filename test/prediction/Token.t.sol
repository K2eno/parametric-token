// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

import "../../src/prediction/PredictionToken.sol";
import "../../src/prediction/PredictionEngine.sol";

contract PredictionTokenTest is Test {
    PredictionToken public token;
    PredictionEngine public engine;
    address public admin = address(0x1);
    address public trader1 = address(0x2);
    address public trader2 = address(0x3);
    address public trader3 = address(0x4);
    uint64 public constant START_PRICE = 73500e8; // 73500 USD
    uint64 public constant ROUND_DURATION = 3600;
    uint64 public constant ROUND = 0;
    uint64 public constant NEXT_ROUND = 1;
    uint64 public constant MAX_ROUNDS = 5;

    function setUp() public {
        vm.warp(1_700_000_000);

        token = new PredictionToken("PredictionToken", "PRED");
        engine = new PredictionEngine(address(token), START_PRICE);
        token.setEngine(address(engine));
        engine.setupToken();

        token.transferOwnership(admin);
        engine.transferOwnership(admin);

        vm.deal(admin, 100 ether);
        vm.deal(trader1, 100 ether);
        vm.deal(trader2, 100 ether);
        vm.deal(trader3, 100 ether);
    }

    // ====== HELPERS ======

    function _warpToActiveRound(uint64 round) internal {
        uint256 resolution = engine.roundResolutionTime(round);
        if (resolution == 0) return;
        if (block.timestamp >= resolution) {
            vm.warp(resolution - ROUND_DURATION / 3);
        }
    }

    function _mint(
        address trader,
        uint256 amount,
        uint64 price,
        uint64 round
    ) internal {
        vm.startPrank(trader);
        token.mint(trader, amount, price, round);
        vm.stopPrank();
    }

    function _prediction(
        address account,
        uint48 subId
    ) internal view returns (uint64) {
        return token.parameterOf(0, account, subId);
    }

    function _roundParam(
        address account,
        uint48 subId
    ) internal view returns (uint64) {
        return token.parameterOf(1, account, subId);
    }

    // ====== DEPLOYMENT & STATE ======

    function test_Deployment_State() public view {
        assertEq(token.name(), "PredictionToken");
        assertEq(token.symbol(), "PRED");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(admin), 0);
        assertEq(token.NUMBER_OF_PARAMETERS(), 2);
        (bytes32 name, uint8 decimals, bool isMutable) = token.paramConfig(0);
        assertEq(name, "prediction");
        assertEq(decimals, 8);
        assertTrue(isMutable);
        (name, decimals, isMutable) = token.paramConfig(1);
        assertEq(name, "round");
        assertEq(decimals, 0);
        assertFalse(isMutable);
    }

    // ====== MINTING ======

    function test_Mint_Success() public {
        uint64 price = 70000e8;
        uint256 amount = 1000e18;
        _warpToActiveRound(ROUND);
        _mint(trader1, amount, price, ROUND);
        assertEq(token.balanceOf(trader1), amount);
        assertEq(_prediction(trader1, 0), price);
        assertEq(_roundParam(trader1, 0), ROUND);
        assertEq(token.totalSupply(), amount);
    }

    function test_Mint_Revert_ZeroAddress() public {
        vm.prank(trader1);
        vm.expectRevert("Mint to zero");
        token.mint(address(0), 100e18, 70000e8, ROUND);
    }

    function test_Mint_Revert_ZeroAmount() public {
        vm.prank(trader1);
        vm.expectRevert("Void amount");
        token.mint(trader1, 0, 70000e8, ROUND);
    }

    function test_Mint_Revert_ZeroPrediction() public {
        vm.prank(trader1);
        vm.expectRevert("Zero prediction");
        token.mint(trader1, 100e18, 0, ROUND);
    }

    function test_Mint_Revert_InactiveRound() public {
        // Close the round to make it inactive
        uint256 resolution = engine.roundResolutionTime(ROUND);
        vm.warp(resolution + 1);
        vm.prank(admin);
        engine.closeRound(ROUND, 2000e8);
        vm.prank(trader1);
        vm.expectRevert("Round not active");
        token.mint(trader1, 100e18, 70000e8, ROUND);
    }

    function test_Mint_Revert_RoundOutOfRange() public {
        uint64 maxRounds = uint64(engine.MAX_ROUNDS());
        vm.prank(trader1);
        vm.expectRevert("Round out of range");
        token.mint(trader1, 100e18, 70000e8, maxRounds);
    }

    function test_Mint_WeightedAverage_ExistingBalance() public {
        _warpToActiveRound(ROUND);
        uint64 p1 = 70000e8;
        uint64 p2 = 80000e8;
        uint256 a1 = 1000e18;
        uint256 a2 = 2000e18;
        _mint(trader1, a1, p1, ROUND);
        _mint(trader1, a2, p2, ROUND);
        uint64 expected = uint64(
            (uint256(p1) * a1 + uint256(p2) * a2) / (a1 + a2)
        );
        assertEq(_prediction(trader1, 0), expected);
        assertEq(_roundParam(trader1, 0), ROUND);
        assertEq(token.balanceOf(trader1), a1 + a2);
    }

    function test_Mint_Revert_RoundMismatch_ExistingBalance() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.prank(trader1);
        vm.expectRevert("Round mismatch");
        token.mint(trader1, 1000e18, 80000e8, NEXT_ROUND);
    }

    function test_Mint_ToSuperAccount_Sub0() public {
        _warpToActiveRound(ROUND);
        vm.prank(trader1);
        token.convertToSuper(trader1);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        assertEq(token.parametricBalanceOf(trader1, 0), 1000e18);
        assertEq(_prediction(trader1, 0), 70000e8);
        _mint(trader1, 2000e18, 80000e8, ROUND);
        uint64 expected = uint64(
            (uint256(70000e8) * 1000e18 + 80000e8 * 2000e18) /
                (1000e18 + 2000e18)
        );
        assertEq(_prediction(trader1, 0), expected);
        assertEq(token.parametricBalanceOf(trader1, 0), 3000e18);
    }

    // ====== TRANSFERS ======

    function test_Transfer_NormalToNormal_Success() public {
        _warpToActiveRound(ROUND);
        uint64 price = 70000e8;
        uint256 amount = 1000e18;
        _mint(trader1, amount, price, ROUND);
        vm.prank(trader1);
        token.transfer(trader2, amount);
        assertEq(token.balanceOf(trader1), 0);
        assertEq(token.balanceOf(trader2), amount);
        assertEq(_prediction(trader2, 0), price);
        assertEq(_roundParam(trader2, 0), ROUND);
        assertEq(_prediction(trader1, 0), 0);
        assertEq(_roundParam(trader1, 0), 0);
    }

    function test_Transfer_ToExistingBalance_SameRound() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        _mint(trader2, 500e18, 80000e8, ROUND);
        vm.prank(trader1);
        token.transfer(trader2, 500e18);
        uint64 expected = uint64(
            (80000e8 * 500e18 + 70000e8 * 500e18) / (500e18 + 500e18)
        );
        assertEq(token.balanceOf(trader1), 500e18);
        assertEq(token.balanceOf(trader2), 1000e18);
        assertEq(_prediction(trader2, 0), expected);
        assertEq(_roundParam(trader2, 0), ROUND);
        assertEq(_prediction(trader1, 0), 70000e8);
    }

    function test_Transfer_Revert_RoundConflict() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        uint256 t0 = engine.roundResolutionTime(ROUND);
        vm.warp(t0 + 1);
        _mint(trader2, 1000e18, 80000e8, NEXT_ROUND);
        vm.prank(trader1);
        vm.expectRevert("Immutable round conflict");
        token.transfer(trader2, 500e18);
    }

    function test_Transfer_Self_SameSubId_NoStateChange() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.prank(trader1);
        token.transfer(trader1, 500e18);
        assertEq(token.balanceOf(trader1), 1000e18);
        assertEq(_prediction(trader1, 0), 70000e8);
        assertEq(_roundParam(trader1, 0), ROUND);
    }

    function test_Transfer_Self_DifferentSubIds() public {
        _warpToActiveRound(ROUND);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        vm.stopPrank();
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.prank(trader1);
        token.parametricTransfer(0, trader1, 1, 500e18);
        assertEq(token.parametricBalanceOf(trader1, 0), 500e18);
        assertEq(token.parametricBalanceOf(trader1, 1), 500e18);
        assertEq(_prediction(trader1, 0), 70000e8);
        assertEq(_prediction(trader1, 1), 70000e8);
        vm.prank(trader1);
        token.parametricTransfer(1, trader1, 0, 250e18);
        assertEq(token.parametricBalanceOf(trader1, 0), 750e18);
        assertEq(token.parametricBalanceOf(trader1, 1), 250e18);
        assertEq(_prediction(trader1, 0), 70000e8);
        assertEq(_prediction(trader1, 1), 70000e8);
    }

    function test_Transfer_ToEmpty_CopiesParams() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.prank(trader1);
        token.transfer(trader2, 500e18);
        assertEq(token.balanceOf(trader2), 500e18);
        assertEq(_prediction(trader2, 0), 70000e8);
        assertEq(_roundParam(trader2, 0), ROUND);
    }

    function test_Transfer_Revert_InsufficientBalance() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.prank(trader1);
        vm.expectRevert("Insufficient balance");
        token.transfer(trader2, 1001e18);
    }

    function test_ParametricTransfer_Revert_NormalFromSubId() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.prank(trader1);
        vm.expectRevert("Not super account");
        token.parametricTransfer(1, trader2, 0, 500e18);
    }

    // ====== ALLOWANCES ======

    function test_Approve_SetsTotal_CapsSub() public {
        vm.prank(trader1);
        token.approve(trader2, 1000);
        assertEq(token.allowance(trader1, trader2), 1000);

        // Set up super account with at least two sub-accounts
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1); // subId=1
        // Now approve for subId=1 (non-zero allowed)
        token.approveForSub(1, trader2, 500, true);
        vm.stopPrank();

        (uint256 subAmount, bool oneOff) = token.allowanceForSub(
            trader1,
            1,
            trader2
        );
        assertEq(subAmount, 500);
        assertTrue(oneOff);

        // Override with approve zero
        vm.prank(trader1);
        token.approve(trader2, 0);
        (subAmount, oneOff) = token.allowanceForSub(trader1, 1, trader2);
        assertEq(subAmount, 0);
        assertFalse(oneOff);
        assertEq(token.allowance(trader1, trader2), 0);
    }

    function test_ApproveForSub_SuperOnly_Revert() public {
        vm.prank(trader1);
        vm.expectRevert("Not super account");
        token.approveForSub(0, trader2, 100, false);
    }

    function test_ApproveForSub_InvalidSubId_Revert() public {
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        vm.expectRevert("Sub-account doesn't exist");
        token.approveForSub(1, trader2, 100, false);
        vm.stopPrank();
    }

    function test_ApproveForSub_OneOffRequiresPositiveAmount_Revert() public {
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        // subId=1, amount=0, oneOff=true should revert
        vm.expectRevert("OneOff requires positive sub allowance");
        token.approveForSub(1, trader2, 0, true);
        vm.stopPrank();
    }

    function test_ApproveForSub_MaintainsGeneralAllowance() public {
        vm.prank(trader1);
        token.approve(trader2, 1000);

        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        token.approveForSub(1, trader2, 300, false);
        vm.stopPrank();

        assertEq(token.allowance(trader1, trader2), 1000);
        (uint256 subAmount, ) = token.allowanceForSub(trader1, 1, trader2);
        assertEq(subAmount, 300);
        uint256 general = token.allowance(trader1, trader2) - subAmount;
        assertEq(general, 700);

        // Reduce sub to 200 – general should stay 700
        vm.startPrank(trader1);
        token.approveForSub(1, trader2, 200, false);
        vm.stopPrank();

        (subAmount, ) = token.allowanceForSub(trader1, 1, trader2);
        assertEq(subAmount, 200);
        general = token.allowance(trader1, trader2) - subAmount;
        assertEq(general, 700);

        // Increase sub to 1200 – total should raise to 1200 + general? Actually total = general + sub = 700 + 1200 = 1900
        vm.startPrank(trader1);
        token.approveForSub(1, trader2, 1200, false);
        vm.stopPrank();

        // assertEq(token.allowance(trader1, trader2), 700 + 1200);
        // (subAmount, ) = token.allowanceForSub(trader1, 1, trader2);
        // assertEq(subAmount, 1200);
        // general = token.allowance(trader1, trader2) - subAmount;
        // assertEq(general, 700);
    }

    function test_TransferFrom_Normal_SpendsTotal() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.prank(trader1);
        token.approve(trader2, 500e18);
        vm.prank(trader2);
        token.transferFrom(trader1, trader2, 200e18);
        assertEq(token.balanceOf(trader1), 800e18);
        assertEq(token.balanceOf(trader2), 200e18);
        assertEq(token.allowance(trader1, trader2), 300e18);
        assertEq(_prediction(trader1, 0), 70000e8);
        assertEq(_prediction(trader2, 0), 70000e8);
    }

    function test_TransferFrom_Super_SubIdNonZero_SpendsGeneral() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1); // subId=1
        token.createSubAccount(trader1); // subId=2
        // Move some tokens to subId=2
        token.parametricTransfer(0, trader1, 2, 300e18);
        // Set sub-allowance on subId=1
        token.approveForSub(1, trader2, 200e18, false);
        // Set general allowance
        token.approve(trader2, 500e18);
        vm.stopPrank();

        // Spend from subId=2 (different from subId=1) => should use general
        vm.prank(trader2);
        token.parametricTransferFrom(trader1, 2, trader2, 0, 100e18);

        // General allowance reduced by 100: total = 500-100 = 400
        assertEq(token.allowance(trader1, trader2), 400e18);
        // Sub-allowance unchanged: 200e18
        (uint256 subAmount, ) = token.allowanceForSub(trader1, 1, trader2);
        assertEq(subAmount, 200e18);
        // subId=2 balance reduced by 100
        assertEq(token.parametricBalanceOf(trader1, 2), 200e18);
        assertEq(token.balanceOf(trader2), 100e18);
        assertEq(_prediction(trader2, 0), 70000e8);
    }

    function test_ParametricTransferFrom_Super_SpendsSub() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 72000e8, ROUND);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        token.approveForSub(1, trader2, 500e18, false);
        token.parametricTransfer(0, trader1, 1, 700e18);
        vm.stopPrank();

        vm.prank(trader2);
        token.parametricTransferFrom(trader1, 1, trader2, 0, 200e18);

        (uint256 subAmount, ) = token.allowanceForSub(trader1, 1, trader2);
        assertEq(subAmount, 300e18);
        assertEq(token.allowance(trader1, trader2), 300e18);
        assertEq(token.balanceOf(trader1), 800e18);
        assertEq(token.parametricBalanceOf(trader1, 0), 300e18);
        assertEq(token.parametricBalanceOf(trader1, 1), 500e18);
        assertEq(token.balanceOf(trader2), 200e18);
        assertEq(_prediction(trader2, 0), 72000e8);
        // Sender prediction remains 70000e8 because balance not zero
        assertEq(_prediction(trader1, 0), 72000e8);
    }

    // ====== ONE-OFF ALLOWANCES ======

    function test_OneOffAllowance_SpendExactSubId_ConsumesAll() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        vm.expectRevert("Single sub-account");
        token.approveForSub(0, trader2, 300e18, false);
        token.createSubAccount(trader1);
        token.approveForSub(1, trader2, 300e18, true);
        assertEq(token.allowance(trader1, trader2), 300e18);
        token.parametricTransfer(0, trader1, 1, 400e18);
        vm.stopPrank();

        vm.startPrank(trader2);
        vm.expectRevert("Insufficient allowance");
        token.parametricTransferFrom(trader1, 1, trader2, 0, 350e18);
        token.parametricTransferFrom(trader1, 1, trader2, 0, 200e18);
        vm.stopPrank();

        (uint256 subAmount, bool oneOff) = token.allowanceForSub(
            trader1,
            1,
            trader2
        );
        assertEq(subAmount, 0);
        assertFalse(oneOff);
        assertEq(token.allowance(trader1, trader2), 0);
    }

    function test_OneOffAllowance_SpendDifferentSubId_Ignored() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        token.createSubAccount(trader1); // subId=2
        token.parametricTransfer(0, trader1, 2, 500e18);
        token.approveForSub(1, trader2, 300e18, true);
        token.approve(trader2, 500e18);
        vm.stopPrank();

        vm.prank(trader2);
        // Spend from subId=2, which is different from subId=1 => ignore oneOff
        token.parametricTransferFrom(trader1, 2, trader2, 0, 100e18);

        (uint256 subAmount, bool oneOff) = token.allowanceForSub(
            trader1,
            1,
            trader2
        );
        assertEq(subAmount, 300e18);
        assertTrue(oneOff);
        // General allowance reduced: total = 500 - 100 = 400, sub=300 => general=100
        assertEq(token.allowance(trader1, trader2), 400e18);
    }

    // ====== BURNS ======

    function test_Burn_Success_ResetsOnZero() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.prank(address(engine));
        token.burn(trader1, 0, 1000e18);
        assertEq(token.balanceOf(trader1), 0);
        assertEq(token.totalSupply(), 0);
        assertEq(_prediction(trader1, 0), 0);
        assertEq(_roundParam(trader1, 0), 0);
    }

    function test_Burn_Success_Partial_NoReset() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.prank(address(engine));
        token.burn(trader1, 0, 400e18);
        assertEq(token.balanceOf(trader1), 600e18);
        assertEq(token.totalSupply(), 600e18);
        assertEq(_prediction(trader1, 0), 70000e8);
        assertEq(_roundParam(trader1, 0), ROUND);
    }

    function test_Burn_Revert_NotEngine() public {
        vm.prank(trader1);
        vm.expectRevert("Not engine");
        token.burn(trader1, 0, 100e18);
    }

    function test_Burn_Revert_SubIdInvalid() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        vm.stopPrank();
        vm.prank(address(engine));
        vm.expectRevert("Sub-account doesn't exist");
        token.burn(trader1, 2, 100e18);
    }

    function test_Burn_Revert_InsufficientBalance() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.prank(address(engine));
        vm.expectRevert("Insufficient balance");
        token.burn(trader1, 0, 1001e18);
    }

    // ====== SUB-ACCOUNT MANAGEMENT ======

    function test_ConvertToSuper_Success() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 74000e8, ROUND);
        vm.prank(trader1);
        token.convertToSuper(trader1);
        assertEq(
            uint8(token.accountType(trader1)),
            uint8(IParametricToken.AccountType.Super)
        );
        assertEq(token.subsCountOf(trader1), 1);
        assertEq(token.parametricBalanceOf(trader1, 0), 1000e18);
        assertEq(_prediction(trader1, 0), 74000e8);
        assertEq(_roundParam(trader1, 0), ROUND);
    }

    function test_ConvertToSuper_Revert_NotNormal() public {
        vm.prank(trader1);
        token.convertToSuper(trader1);
        vm.prank(trader1);
        vm.expectRevert("Not normal account");
        token.convertToSuper(trader1);
    }

    function test_CreateSubAccount_Success() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        uint48 subId = token.createSubAccount(trader1);
        vm.stopPrank();
        assertEq(subId, 1);
        assertEq(token.subsCountOf(trader1), 2);
        assertEq(token.parametricBalanceOf(trader1, 1), 0);
        assertEq(_prediction(trader1, 1), 0);
        assertEq(_roundParam(trader1, 1), 0);
    }

    function test_CreateSubAccount_Revert_NotSuper() public {
        vm.prank(trader1);
        vm.expectRevert("Not super account");
        token.createSubAccount(trader1);
    }

    // ====== QUERIES ======

    function test_ParameterOf_Valid() public {
        _warpToActiveRound(ROUND);
        _mint(trader1, 1000e18, 70000e8, ROUND);
        assertEq(token.parameterOf(0, trader1, 0), 70000e8);
        assertEq(token.parameterOf(1, trader1, 0), ROUND);
    }

    function test_ParameterOf_Revert_InvalidParamIndex() public {
        vm.expectRevert("Invalid param index");
        token.parameterOf(2, trader1, 0);
    }
}
