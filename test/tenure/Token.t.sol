// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/tenure/TenureToken.sol";
import "../../src/tenure/TenureEngine.sol";

contract TenureTokenTest is Test {
    TenureToken public token;
    TenureEngine public engine;
    address public admin = address(0x1);
    address public trader1 = address(0x2);
    address public trader2 = address(0x3);
    address public trader3 = address(0x4);

    uint64 public constant REWARDS_RATE = 100; // 1% per 30 days
    uint256 public constant INITIAL_TIMESTAMP = 1_700_000_000;

    function setUp() public {
        vm.warp(INITIAL_TIMESTAMP);
        token = new TenureToken("TenureToken", "TEN");
        engine = new TenureEngine(address(token), REWARDS_RATE);
        token.setEngine(address(engine));
        vm.deal(admin, 100 ether);
        vm.deal(trader1, 100 ether);
        vm.deal(trader2, 100 ether);
        vm.deal(trader3, 100 ether);
    }

    // --- Helpers ---

    function _mint(address trader, uint256 amount) internal {
        vm.startPrank(trader); // engine's mint is public (anyone can call)
        engine.mint(trader, amount);
        vm.stopPrank();
    }

    function _redeem(address trader, uint48 subId, uint256 amount) internal {
        vm.startPrank(trader);
        engine.redeem(trader, subId, amount);
        vm.stopPrank();
    }

    function _mintTime(
        address account,
        uint48 subId
    ) internal view returns (uint64) {
        return token.mintTime(account, subId);
    }

    // ====== DEPLOYMENT & STATE ======

    function test_Deployment_State() public view {
        assertEq(token.name(), "TenureToken");
        assertEq(token.symbol(), "TEN");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(admin), 0);
        assertEq(token.NUMBER_OF_PARAMETERS(), 1);
        (bytes32 name, uint8 decimals, bool isMutable) = token.paramConfig(0);
        assertEq(name, "mintTime");
        assertEq(decimals, 0);
        assertTrue(isMutable);
        // Engine state
        assertEq(engine.rewardsRateBps(), REWARDS_RATE);
    }

    // ====== MINTING ======

    function test_Mint_Success() public {
        uint256 amount = 1000e18;
        vm.warp(INITIAL_TIMESTAMP + 100);
        _mint(trader1, amount);
        assertEq(token.balanceOf(trader1), amount);
        assertEq(_mintTime(trader1, 0), uint64(INITIAL_TIMESTAMP + 100));
        assertEq(token.totalSupply(), amount);
    }

    function test_Mint_Revert_ZeroAddress() public {
        vm.expectRevert("Mint to zero");
        engine.mint(address(0), 100e18);
    }

    function test_Mint_Revert_ZeroAmount() public {
        vm.expectRevert("Void amount");
        engine.mint(trader1, 0);
    }

    function test_Mint_WeightedAverage_ExistingBalance() public {
        uint256 a1 = 1000e18;
        uint256 a2 = 2000e18;
        uint64 t1 = uint64(INITIAL_TIMESTAMP + 100);
        uint64 t2 = uint64(INITIAL_TIMESTAMP + 200);
        vm.warp(t1);
        _mint(trader1, a1);
        vm.warp(t2);
        _mint(trader1, a2);
        uint64 expected = uint64(
            (uint256(t1) * a1 + uint256(t2) * a2) / (a1 + a2)
        );
        assertEq(_mintTime(trader1, 0), expected);
        assertEq(token.balanceOf(trader1), a1 + a2);
    }

    function test_Mint_ToSuperAccount_Sub0() public {
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        vm.stopPrank();
        uint256 amount = 1000e18;
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, amount);
        assertEq(token.parametricBalanceOf(trader1, 0), amount);
        assertEq(_mintTime(trader1, 0), mintTime);
        // Second mint should average
        vm.warp(mintTime + 100);
        uint64 newTime = uint64(block.timestamp);
        _mint(trader1, amount);
        uint64 expected = uint64(
            (uint256(mintTime) * amount + uint256(newTime) * amount) /
                (amount + amount)
        );
        assertEq(_mintTime(trader1, 0), expected);
        assertEq(token.parametricBalanceOf(trader1, 0), amount + amount);
    }

    // ====== TRANSFERS ======

    function test_Transfer_NormalToNormal_Success() public {
        uint256 amount = 1000e18;
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, amount);
        vm.prank(trader1);
        token.transfer(trader2, amount);
        assertEq(token.balanceOf(trader1), 0);
        assertEq(token.balanceOf(trader2), amount);
        assertEq(_mintTime(trader2, 0), mintTime);
        assertEq(_mintTime(trader1, 0), 0); // reset
    }

    function test_Transfer_ToExistingBalance_WeightedAverage() public {
        uint64 t1 = uint64(block.timestamp);
        uint64 t2 = uint64(block.timestamp + 100);
        vm.warp(t1);
        _mint(trader1, 1000e18);
        vm.warp(t2);
        _mint(trader2, 500e18);
        vm.prank(trader1);
        token.transfer(trader2, 500e18);
        uint64 expected = uint64(
            (uint256(t2) * 500e18 + uint256(t1) * 500e18) / (500e18 + 500e18)
        );
        assertEq(token.balanceOf(trader1), 500e18);
        assertEq(token.balanceOf(trader2), 1000e18);
        assertEq(_mintTime(trader2, 0), expected);
        assertEq(_mintTime(trader1, 0), t1); // sender balance not zero
    }

    function test_Transfer_ToEmpty_CopiesMintTime() public {
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        token.transfer(trader2, 500e18);
        assertEq(token.balanceOf(trader2), 500e18);
        assertEq(_mintTime(trader2, 0), mintTime);
    }

    function test_Transfer_Self_SameSubId_NoStateChange() public {
        _mint(trader1, 1000e18);
        uint64 mintTime = _mintTime(trader1, 0);
        vm.prank(trader1);
        token.transfer(trader1, 500e18);
        assertEq(token.balanceOf(trader1), 1000e18);
        assertEq(_mintTime(trader1, 0), mintTime);
    }

    function test_Transfer_Self_DifferentSubIds() public {
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        vm.stopPrank();
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        token.parametricTransfer(0, trader1, 1, 500e18);
        assertEq(token.parametricBalanceOf(trader1, 0), 500e18);
        assertEq(token.parametricBalanceOf(trader1, 1), 500e18);
        assertEq(_mintTime(trader1, 0), mintTime);
        assertEq(_mintTime(trader1, 1), mintTime);
        vm.prank(trader1);
        token.parametricTransfer(1, trader1, 0, 250e18);
        assertEq(token.parametricBalanceOf(trader1, 0), 750e18);
        assertEq(token.parametricBalanceOf(trader1, 1), 250e18);
        assertEq(_mintTime(trader1, 0), mintTime);
        assertEq(_mintTime(trader1, 1), mintTime);
    }

    function test_Transfer_Revert_InsufficientBalance() public {
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        vm.expectRevert("Insufficient balance");
        token.transfer(trader2, 1001e18);
    }

    function test_ParametricTransfer_Revert_NormalFromSubId() public {
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        vm.expectRevert("Not super account");
        token.parametricTransfer(1, trader2, 0, 500e18);
    }

    // ====== ALLOWANCES ======

    function test_Approve_SetsTotal_CapsSub() public {
        vm.prank(trader1);
        token.approve(trader2, 1000);
        assertEq(token.allowance(trader1, trader2), 1000);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        token.approveForSub(1, trader2, 500, true);
        vm.stopPrank();
        (uint48 subId, uint256 subAmount, bool oneOff) = token.subAllowance(
            trader1,
            trader2
        );
        assertEq(subId, 1);
        assertEq(subAmount, 500);
        assertTrue(oneOff);
        (subAmount, oneOff) = token.allowanceForSub(trader1, 1, trader2);
        assertEq(subAmount, 500);
        assertTrue(oneOff);
        vm.prank(trader1);
        token.approve(trader2, 0);
        (subId, subAmount, oneOff) = token.subAllowance(trader1, trader2);
        assertEq(subId, 1); // remains
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

    function test_ApproveForSub_SingleSubAccount_Revert() public {
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        vm.expectRevert("Single sub-account");
        token.approveForSub(0, trader2, 0, false);
        vm.stopPrank();
    }

    function test_ApproveForSub_SubIdZero_RequiresZeroAmount() public {
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        vm.expectRevert("SubId 0 requires zero amount");
        token.approveForSub(0, trader2, 100, false);
        vm.stopPrank();
    }

    function test_ApproveForSub_SubIdZero_RequiresFalseOneOff() public {
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        vm.expectRevert("SubId 0 requires false oneOff");
        token.approveForSub(0, trader2, 0, true);
        vm.stopPrank();
    }

    function test_ApproveForSub_OneOffRequiresPositiveAmount() public {
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
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

        // Reduce sub
        vm.startPrank(trader1);
        token.approveForSub(1, trader2, 200, false);
        vm.stopPrank();

        (subAmount, ) = token.allowanceForSub(trader1, 1, trader2);
        assertEq(subAmount, 200);
        assertEq(token.allowance(trader1, trader2), 900);
        general = token.allowance(trader1, trader2) - subAmount;
        assertEq(general, 700);

        // Increase sub beyond total
        vm.startPrank(trader1);
        token.approveForSub(1, trader2, 1200, false);
        vm.stopPrank();

        assertEq(token.allowance(trader1, trader2), 1200);
        (subAmount, ) = token.allowanceForSub(trader1, 1, trader2);
        assertEq(subAmount, 1200);
        general = token.allowance(trader1, trader2) - subAmount;
        assertEq(general, 0);
    }

    function test_TransferFrom_Normal_SpendsTotal() public {
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        token.approve(trader2, 500e18);
        vm.prank(trader2);
        token.transferFrom(trader1, trader2, 200e18);
        assertEq(token.balanceOf(trader1), 800e18);
        assertEq(token.balanceOf(trader2), 200e18);
        assertEq(token.allowance(trader1, trader2), 300e18);
        assertEq(_mintTime(trader2, 0), _mintTime(trader1, 0)); // same
    }

    function test_TransferFrom_Super_SubIdNonZero_SpendsGeneral() public {
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1); // subId=1
        token.createSubAccount(trader1); // subId=2
        token.parametricTransfer(0, trader1, 2, 300e18);
        token.approveForSub(1, trader2, 200e18, false);
        token.approve(trader2, 500e18);
        vm.stopPrank();

        vm.prank(trader2);
        token.parametricTransferFrom(trader1, 2, trader2, 0, 100e18);

        assertEq(token.allowance(trader1, trader2), 400e18);
        (uint256 subAmount, ) = token.allowanceForSub(trader1, 1, trader2);
        assertEq(subAmount, 200e18);
        assertEq(token.parametricBalanceOf(trader1, 2), 200e18);
        assertEq(token.balanceOf(trader2), 100e18);
        assertEq(_mintTime(trader2, 0), _mintTime(trader1, 0)); // same
    }

    function test_ParametricTransferFrom_Super_SpendsSub() public {
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        token.parametricTransfer(0, trader1, 1, 700e18);
        token.approveForSub(1, trader2, 500e18, false);
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
        assertEq(_mintTime(trader2, 0), _mintTime(trader1, 0)); // same
        // sender prediction remains because balance not zero
        assertEq(_mintTime(trader1, 0), _mintTime(trader1, 0));
    }

    // ====== ONE-OFF ALLOWANCES ======

    function test_OneOffAllowance_SpendExactSubId_ConsumesAll() public {
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        token.approveForSub(1, trader2, 300e18, true);
        token.parametricTransfer(0, trader1, 1, 100e18);
        vm.stopPrank();

        vm.prank(trader2);
        token.parametricTransferFrom(trader1, 1, trader2, 0, 100e18);

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
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        token.createSubAccount(trader1);
        token.parametricTransfer(0, trader1, 2, 500e18);
        token.approveForSub(1, trader2, 300e18, true);
        token.approve(trader2, 500e18);
        vm.stopPrank();

        vm.prank(trader2);
        token.parametricTransferFrom(trader1, 2, trader2, 0, 100e18);

        (uint256 subAmount, bool oneOff) = token.allowanceForSub(
            trader1,
            1,
            trader2
        );
        assertEq(subAmount, 300e18);
        assertTrue(oneOff);
        assertEq(token.allowance(trader1, trader2), 400e18);
    }

    // ====== BURNS ======

    function test_Burn_Success_ResetsOnZero() public {
        _mint(trader1, 1000e18);
        uint64 timestamp = uint64(block.timestamp);
        uint64 mintTime = _mintTime(trader1, 0);
        assertEq(timestamp, mintTime);
        vm.warp(block.timestamp + 1 days);
        // Burn via engine.redeem
        _redeem(trader1, 0, 1000e18);
        assertEq(token.balanceOf(trader1), 0);
        assertEq(token.totalSupply(), 0);
        assertEq(_mintTime(trader1, 0), 0);
        // Points should be earned
        assertGt(engine.pointsEarned(trader1), 0);
    }

    function test_Burn_Partial_NoReset() public {
        _mint(trader1, 1000e18);
        uint64 mintTime = _mintTime(trader1, 0);
        vm.warp(block.timestamp + 1 days);
        _redeem(trader1, 0, 400e18);
        assertEq(token.balanceOf(trader1), 600e18);
        assertEq(token.totalSupply(), 600e18);
        assertEq(_mintTime(trader1, 0), mintTime); // unchanged
        assertGt(engine.pointsEarned(trader1), 0);
    }

    function test_Burn_Revert_NotEngine() public {
        vm.prank(trader1);
        vm.expectRevert("Not engine");
        token.burn(trader1, 0, 100e18);
    }

    function test_Burn_Revert_SubIdInvalid() public {
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        vm.stopPrank();
        vm.prank(address(engine));
        vm.expectRevert("Sub-account doesn't exist");
        token.burn(trader1, 2, 100e18);
    }

    function test_Burn_Revert_InsufficientBalance() public {
        _mint(trader1, 1000e18);
        vm.prank(address(engine));
        vm.expectRevert("Insufficient balance");
        token.burn(trader1, 0, 1001e18);
    }

    // ====== SUB-ACCOUNT MANAGEMENT ======

    function test_ConvertToSuper_Success() public {
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        token.convertToSuper(trader1);
        assertEq(
            uint8(token.accountType(trader1)),
            uint8(IParametricToken.AccountType.Super)
        );
        assertEq(token.subsCountOf(trader1), 1);
        assertEq(token.parametricBalanceOf(trader1, 0), 1000e18);
        assertEq(_mintTime(trader1, 0), mintTime); // copied
    }

    function test_ConvertToSuper_Revert_NotNormal() public {
        vm.prank(trader1);
        token.convertToSuper(trader1);
        vm.prank(trader1);
        vm.expectRevert("Not normal account");
        token.convertToSuper(trader1);
    }

    function test_CreateSubAccount_Success() public {
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        uint48 subId = token.createSubAccount(trader1);
        vm.stopPrank();
        assertEq(subId, 1);
        assertEq(token.subsCountOf(trader1), 2);
        assertEq(token.parametricBalanceOf(trader1, 1), 0);
        assertEq(_mintTime(trader1, 1), 0);
    }

    function test_CreateSubAccount_Revert_NotSuper() public {
        vm.prank(trader1);
        vm.expectRevert("Not super account");
        token.createSubAccount(trader1);
    }

    // ====== QUERIES ======

    function test_ParameterOf_Valid() public {
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, 1000e18);
        assertEq(token.parameterOf(0, trader1, 0), mintTime);
        // Normal account
        assertEq(token.parameterOf(0, trader1, 0), mintTime);
    }

    function test_ParameterOf_Revert_InvalidParamIndex() public {
        vm.expectRevert("Invalid param index");
        token.parameterOf(1, trader1, 0);
    }

    function test_AllParametersOf() public {
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, 1000e18);
        uint64[] memory params = token.allParametersOf(trader1, 0);
        assertEq(params.length, 1);
        assertEq(params[0], mintTime);
    }

    function test_MintTimeGetter() public {
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, 1000e18);
        assertEq(token.mintTime(trader1, 0), mintTime);
    }
}
