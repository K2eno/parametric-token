// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "../../src/bundle/Router.sol";
import "../../src/bundle/Core.sol";
import "../../src/bundle/Bundle.sol";
import "../../src/interfaces/IBundleToken.sol";
import "../../src/bundle/BundleEngine.sol";
import "../../src/mock/AssetToken.sol";
import "../../src/interfaces/spec/IParametricToken.sol";
import "../../src/interfaces/spec/IParametricTokenNzs.sol";
import "../../src/libraries/Lib.sol";

contract BundleTokenTest is Test {
    Router public router;
    Core public core;
    Bundle public tokenLogic;
    BundleEngine public engine;
    AssetToken public wbtc;
    AssetToken public inv;

    address public admin = address(0x1);
    address public trader1 = address(0x2);
    address public trader2 = address(0x3);
    address public trader3 = address(0x4);
    uint64 public constant INITIAL_PRICE = 73000e8; // 30000 USD with 8 decimals

    struct ExpectedNzs {
        address from;
        address to;
        uint256 debit;
        uint256 credit;
        uint64 fromParam;
        uint64 toParam;
    }

    function setUp() public {
        // Deploy mocks
        wbtc = new AssetToken("WBTC", "WBTC", 2);
        inv = new AssetToken("INV", "INV", 100_000);

        vm.deal(admin, 100 ether);
        vm.deal(trader1, 100 ether);
        vm.deal(trader2, 100 ether);
        vm.deal(trader3, 100 ether);

        // Mint some tokens to traders for deposits if needed
        vm.startPrank(trader1);
        wbtc.mint(1e18); // 1 WBTC (18 decimals)
        inv.mint(100000e18);
        vm.stopPrank();

        vm.startPrank(trader2);
        wbtc.mint(1e18); // 1 WBTC (18 decimals)
        inv.mint(100000e18);
        vm.stopPrank();

        vm.startPrank(trader3);
        wbtc.mint(1e18); // 1 WBTC (18 decimals)
        inv.mint(100000e18);
        vm.stopPrank();

        // Deploy token and engine
        core = new Core();
        tokenLogic = new Bundle();
        router = new Router(
            address(core),
            address(tokenLogic),
            "BundleToken",
            "BUN"
        );

        // Deploy Engine with Router address
        engine = new BundleEngine(
            address(router),
            address(wbtc),
            address(inv),
            INITIAL_PRICE
        );

        // Set engine on Router (delegates to Bundle)
        IBundleToken(address(router)).setEngine(address(engine));

        // Transfer ownership to admin
        router.transferOwnership(admin);
        engine.transferOwnership(admin);
    }

    // ====== HELPERS ======

    function _token() internal view returns (IBundleToken) {
        return IBundleToken(address(router));
    }

    function _anchor(
        address account,
        uint48 subId
    ) internal view returns (uint64) {
        return _token().anchor(account, subId);
    }

    function _approveEngine(
        address trader,
        uint256 wbtcAmount,
        uint256 invAmount
    ) internal {
        vm.startPrank(trader);
        wbtc.approve(address(engine), wbtcAmount);
        inv.approve(address(engine), invAmount);
        vm.stopPrank();
    }

    // ====== DEPLOYMENT & STATE ======

    function test_Deployment_State() public view {
        assertEq(_token().name(), "BundleToken");
        assertEq(_token().symbol(), "BUN");
        assertEq(_token().decimals(), 18);
        assertEq(_token().totalSupply(), 0);
        assertEq(_token().balanceOf(admin), 0);
        assertEq(_token().NUMBER_OF_PARAMETERS(), 1);

        IParametricToken.ParamConfig[] memory params = _token().paramConfig();
        assertEq(params[0].name, "anchor");
        assertEq(params[0].decimals, 8);
        assertTrue(params[0].isMutable);

        assertTrue(
            _token().supportsInterface(type(IParametricTokenNzs).interfaceId)
        );
    }

    // ====== DEPOSIT ======

    function test_Deposit_Success() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;

        _approveEngine(trader1, wbtcAmount, invAmount);

        uint256 balanceBefore = _token().balanceOf(trader1);
        uint256 supplyBefore = _token().totalSupply();

        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        uint256 balanceAfter = _token().balanceOf(trader1);
        uint256 supplyAfter = _token().totalSupply();

        assertGt(balanceAfter, balanceBefore, "BUN balance should increase");
        assertGt(supplyAfter, supplyBefore, "Total supply should increase");
        assertGt(_anchor(trader1, 0), 0, "Anchor should be set");
    }

    function test_Deposit_Revert_ZeroAmounts() public {
        vm.prank(trader1);
        vm.expectRevert("Zero deposit");
        engine.deposit(0, 100e18);

        vm.prank(trader1);
        vm.expectRevert("Zero deposit");
        engine.deposit(1e18, 0);
    }

    function test_Deposit_TransfersTokens() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;

        uint256 wbtcBalanceBefore = wbtc.balanceOf(trader1);
        uint256 invBalanceBefore = inv.balanceOf(trader1);

        _approveEngine(trader1, wbtcAmount, invAmount);

        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        assertEq(
            wbtc.balanceOf(trader1),
            wbtcBalanceBefore - wbtcAmount,
            "WBTC not transferred"
        );
        assertEq(
            inv.balanceOf(trader1),
            invBalanceBefore - invAmount,
            "INV not transferred"
        );
        assertEq(
            wbtc.balanceOf(address(engine)),
            wbtcAmount,
            "Engine WBTC balance"
        );
        assertEq(
            inv.balanceOf(address(engine)),
            invAmount,
            "Engine INV balance"
        );
    }

    function test_Deposit_DifferentAmounts_CreatesDifferentAnchors() public {
        // Trader1 deposits with ratio X
        uint256 wbtc1 = 0.5e18;
        uint256 inv1 = 50000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);
        uint64 anchor1 = _anchor(trader1, 0);

        // Trader2 deposits with ratio Y
        uint256 wbtc2 = 0.2e18;
        uint256 inv2 = 80000e18;
        _approveEngine(trader2, wbtc2, inv2);
        vm.prank(trader2);
        engine.deposit(wbtc2, inv2);
        uint64 anchor2 = _anchor(trader2, 0);

        assertTrue(
            anchor1 != anchor2,
            "Anchors should differ for different ratios"
        );
    }

    // ====== REDEEM ======

    function test_Redeem_Success() public {
        // Deposit first
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        uint64 anchor = _anchor(trader1, 0);
        assertEq(anchor, 100000e8);

        uint256 bunBalance = _token().balanceOf(trader1);
        uint256 supplyBefore = _token().totalSupply();

        // Redeem half
        uint256 redeemAmount = bunBalance / 2;
        vm.prank(trader1);
        engine.redeem(redeemAmount, 0);

        uint256 supplyAfter = _token().totalSupply();
        assertEq(
            _token().balanceOf(trader1),
            bunBalance - redeemAmount,
            "BUN not burned"
        );
        assertEq(
            supplyAfter,
            supplyBefore - redeemAmount,
            "Total supply decreased"
        );
        // Anchor resets only if balance becomes zero (it doesn't – we redeemed half)
        assertEq(
            _anchor(trader1, 0),
            anchor,
            "Anchor should persist with remaining balance"
        );
    }

    function test_Redeem_Full_ResetsAnchor() public {
        // Deposit first
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        uint64 anchorBefore = _anchor(trader1, 0);
        assertGt(anchorBefore, 0, "Anchor should be set");

        uint256 bunBalance = _token().balanceOf(trader1);

        // Redeem all
        vm.prank(trader1);
        engine.redeem(bunBalance, 0);

        assertEq(_token().balanceOf(trader1), 0, "BUN fully burned");
        assertEq(_anchor(trader1, 0), 0, "Anchor should reset to 0");
        assertEq(_token().totalSupply(), 0, "Total supply reset");
    }

    function test_Redeem_Revert_ZeroAmount() public {
        vm.prank(trader1);
        vm.expectRevert("Zero amount");
        engine.redeem(0, 0);
    }

    function test_Redeem_Revert_ZeroAnchor() public {
        vm.prank(trader1);
        vm.expectRevert("Zero anchor");
        engine.redeem(100e18, 0);
    }

    function test_Redeem_Revert_InsufficientBalance() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        uint256 bunBalance = _token().balanceOf(trader1);
        vm.prank(trader1);
        vm.expectRevert("Insufficient balance");
        engine.redeem(bunBalance + 1, 0);
    }

    function test_Redeem_Revert_InvalidSubId() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        _token().parametricTransfer(
            0,
            trader1,
            1,
            _token().balanceOf(trader1) / 2
        );
        vm.stopPrank();

        vm.prank(trader1);
        vm.expectRevert("Sub-account doesn't exist");
        engine.redeem(100e18, 2);
    }

    // ====== DEPOSIT + REDEEM COMBINED ======

    function test_Deposit_Redeem_UpdatesTotalSupply() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);

        uint256 supplyBefore = _token().totalSupply();

        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        uint256 supplyAfterDeposit = _token().totalSupply();
        assertGt(
            supplyAfterDeposit,
            supplyBefore,
            "Supply should increase on deposit"
        );

        uint256 bunBalance = _token().balanceOf(trader1);
        vm.prank(trader1);
        engine.redeem(bunBalance, 0);

        uint256 supplyAfterRedeem = _token().totalSupply();
        assertEq(
            supplyAfterRedeem,
            supplyBefore,
            "Supply should return to original after full redeem"
        );
    }

    // ====== TRANSFERS ======

    function test_Transfer_ToExisting_Combine() public {
        // Deposit for trader1
        uint256 wbtc1 = 0.5e18;
        uint256 inv1 = 50000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);

        // Deposit for trader2
        uint256 wbtc2 = 0.3e18;
        uint256 inv2 = 30000e18;
        _approveEngine(trader2, wbtc2, inv2);
        vm.prank(trader2);
        engine.deposit(wbtc2, inv2);

        uint64 anchor1 = _anchor(trader1, 0);
        uint64 anchor2 = _anchor(trader2, 0);

        uint256 transferAmount = _token().balanceOf(trader1) / 2;

        vm.prank(trader1);
        _token().transfer(trader2, transferAmount);

        uint256 trader2Balance = _token().balanceOf(trader2);

        // The new anchor should be a weighted average
        (uint64 expectedAnchor, ) = Lib.combine(
            anchor1,
            transferAmount,
            anchor2,
            _token().balanceOf(trader2) - transferAmount
        );

        assertEq(_anchor(trader2, 0), expectedAnchor);
        assertGt(trader2Balance, 0);
    }

    function test_Transfer_NormalToEmpty_CopiesAnchor() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        uint256 transferAmount = _token().balanceOf(trader1) / 2;
        uint64 anchorBefore = _anchor(trader1, 0);

        vm.prank(trader1);
        _token().transfer(trader2, transferAmount);

        assertEq(_token().balanceOf(trader2), transferAmount);
        assertEq(_anchor(trader2, 0), anchorBefore);
        assertEq(_anchor(trader1, 0), anchorBefore);
    }

    function test_Transfer_ToExisting_Combine_And_NZS_Credit() public {
        // Deposit trader1
        uint256 wbtc1 = 0.5e18;
        uint256 inv1 = 50000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);

        // Deposit trader2
        uint256 wbtc2 = 0.1e18;
        uint256 inv2 = 30000e18;
        _approveEngine(trader2, wbtc2, inv2);
        vm.prank(trader2);
        engine.deposit(wbtc2, inv2);

        uint64 anchor1 = _anchor(trader1, 0);
        uint64 anchor2 = _anchor(trader2, 0);
        assertTrue(anchor1 != anchor2);
        uint256 balance1 = _token().balanceOf(trader1);
        uint256 balance2 = _token().balanceOf(trader2);

        uint256 transferAmount = balance1 / 2;

        // Compute expected NZS credit
        (uint64 expectedAnchor, uint256 expectedToBalance) = Lib.combine(
            anchor1,
            transferAmount,
            anchor2,
            balance2
        );
        uint256 expectedCredit = expectedToBalance - balance2;

        vm.prank(trader1);
        _token().transfer(trader2, transferAmount);

        assertEq(_token().balanceOf(trader2), expectedToBalance);
        assertEq(_anchor(trader2, 0), expectedAnchor);
        // Credit amount is NOT equal to transferAmount (NZS)
        assertTrue(expectedCredit != transferAmount);
    }

    function test_Transfer_Self_SameSubId_NoStateChange() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        uint64 anchorBefore = _anchor(trader1, 0);
        uint256 balanceBefore = _token().balanceOf(trader1);
        uint256 supplyBefore = _token().totalSupply();

        vm.prank(trader1);
        _token().transfer(trader1, balanceBefore / 2);

        assertEq(_token().balanceOf(trader1), balanceBefore);
        assertEq(_anchor(trader1, 0), anchorBefore);
        assertEq(_token().totalSupply(), supplyBefore);
    }

    function test_Transfer_Self_DifferentSubIds() public {
        // Deposit
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        vm.stopPrank();

        uint64 anchor = _anchor(trader1, 0);
        uint256 totalBalance = _token().balanceOf(trader1);

        // Transfer half to sub-account 1
        vm.prank(trader1);
        _token().parametricTransfer(0, trader1, 1, totalBalance / 2);

        assertEq(_token().parametricBalanceOf(trader1, 0), totalBalance / 2);
        assertEq(_token().parametricBalanceOf(trader1, 1), totalBalance / 2);
        assertEq(_anchor(trader1, 0), anchor);
        assertEq(_anchor(trader1, 1), anchor);

        // Transfer back from sub-1 to sub-0
        (uint64 newAnchor, uint256 newBalance) = Lib.combine(
            anchor,
            totalBalance / 4,
            anchor,
            totalBalance / 2
        );

        vm.prank(trader1);
        _token().parametricTransfer(1, trader1, 0, totalBalance / 4);

        assertEq(_token().parametricBalanceOf(trader1, 0), newBalance);
        assertEq(_token().parametricBalanceOf(trader1, 1), totalBalance / 4);
        assertEq(_anchor(trader1, 0), newAnchor);
        assertEq(_anchor(trader1, 1), anchor);
    }

    function test_ParametricTransfer_NormalToSuper() public {
        // Deposit trader1
        uint256 wbtc1 = 0.5e18;
        uint256 inv1 = 50000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);

        // Deposit trader2 and convert to Super
        uint256 wbtc2 = 0.3e18;
        uint256 inv2 = 30000e18;
        _approveEngine(trader2, wbtc2, inv2);
        vm.prank(trader2);
        engine.deposit(wbtc2, inv2);

        vm.startPrank(trader2);
        _token().convertToSuper();
        _token().createSubAccount();
        vm.stopPrank();

        uint64 anchor1 = _anchor(trader1, 0);
        uint64 anchor2 = _anchor(trader2, 0);
        uint256 balance1 = _token().balanceOf(trader1);
        uint256 balance2_0 = _token().parametricBalanceOf(trader2, 0);

        uint256 transferAmount = balance1 / 2;

        // Compute expected NZS credit
        (uint64 expectedAnchor, uint256 expectedToBalance) = Lib.combine(
            anchor1,
            transferAmount,
            anchor2,
            balance2_0
        );

        vm.prank(trader1);
        _token().parametricTransfer(0, trader2, 0, transferAmount);

        assertEq(_token().parametricBalanceOf(trader2, 0), expectedToBalance);
        assertEq(_anchor(trader2, 0), expectedAnchor);
    }

    function test_ParametricTransfer_ToSuperSubAccount() public {
        // Deposit trader1
        uint256 wbtc1 = 0.5e18;
        uint256 inv1 = 50000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);

        // Deposit trader2 and convert to Super with sub-account 1
        uint256 wbtc2 = 0.3e18;
        uint256 inv2 = 30000e18;
        _approveEngine(trader2, wbtc2, inv2);
        vm.prank(trader2);
        engine.deposit(wbtc2, inv2);

        vm.startPrank(trader2);
        _token().convertToSuper();
        _token().createSubAccount();
        // Move some tokens to sub-account 1
        uint256 half = _token().balanceOf(trader2) / 2;
        _token().parametricTransfer(0, trader2, 1, half);
        vm.stopPrank();

        uint64 anchor1 = _anchor(trader1, 0);
        uint64 anchor2 = _anchor(trader2, 1);
        uint256 balance1 = _token().balanceOf(trader1);
        uint256 balance2_1 = _token().parametricBalanceOf(trader2, 1);

        uint256 transferAmount = balance1 / 2;

        (uint64 expectedAnchor, uint256 expectedToBalance) = Lib.combine(
            anchor1,
            transferAmount,
            anchor2,
            balance2_1
        );

        vm.prank(trader1);
        _token().parametricTransfer(0, trader2, 1, transferAmount);

        assertEq(_token().parametricBalanceOf(trader2, 1), expectedToBalance);
        assertEq(_anchor(trader2, 1), expectedAnchor);
    }

    function test_NZS_Transfer_ChangesTotalSupply() public {
        // Deposit trader1
        uint256 wbtc1 = 0.5e18;
        uint256 inv1 = 50000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);

        // Deposit trader2
        uint256 wbtc2 = 0.1e18;
        uint256 inv2 = 30000e18;
        _approveEngine(trader2, wbtc2, inv2);
        vm.prank(trader2);
        engine.deposit(wbtc2, inv2);

        uint64 anchor1 = _anchor(trader1, 0);
        uint64 anchor2 = _anchor(trader2, 0);
        assertTrue(anchor1 != anchor2);
        uint256 balance1 = _token().balanceOf(trader1);
        uint256 balance2 = _token().balanceOf(trader2);

        uint256 supplyBefore = _token().totalSupply();
        uint256 transferAmount = balance1 / 2;

        // Compute expected credit
        (, uint256 expectedToBalance) = Lib.combine(
            anchor1,
            transferAmount,
            anchor2,
            balance2
        );
        uint256 expectedCredit = expectedToBalance - balance2;

        vm.prank(trader1);
        _token().transfer(trader2, transferAmount);

        uint256 supplyAfter = _token().totalSupply();

        // Total supply changes by creditAmount (NZS)
        assertEq(supplyAfter, supplyBefore - transferAmount + expectedCredit);
        assertTrue(expectedCredit != transferAmount);
        assertTrue(supplyAfter != supplyBefore);
    }

    function test_NZS_Transfer_NegativeCredit_DecreasesTotalSupply() public {
        // Deposit trader1 with large anchor
        uint256 wbtc1 = 0.1e18;
        uint256 inv1 = 10000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);

        // Deposit trader2 with small anchor (different ratio)
        uint256 wbtc2 = 0.5e18;
        uint256 inv2 = 100000e18;
        _approveEngine(trader2, wbtc2, inv2);
        vm.prank(trader2);
        engine.deposit(wbtc2, inv2);

        uint64 anchor1 = _anchor(trader1, 0);
        uint64 anchor2 = _anchor(trader2, 0);
        uint256 balance1 = _token().balanceOf(trader1);
        uint256 balance2 = _token().balanceOf(trader2);

        uint256 supplyBefore = _token().totalSupply();
        uint256 transferAmount = balance1; // Send all

        // Compute expected credit (may be negative)
        (, uint256 expectedToBalance) = Lib.combine(
            anchor1,
            transferAmount,
            anchor2,
            balance2
        );
        int256 expectedCredit = int256(expectedToBalance) - int256(balance2);

        vm.prank(trader1);
        _token().transfer(trader2, transferAmount);

        uint256 supplyAfter = _token().totalSupply();
        int256 supplyDelta = int256(supplyAfter) - int256(supplyBefore);
        int256 transferDelta = expectedCredit - int256(transferAmount);

        assertEq(supplyDelta, transferDelta);
    }

    function test_Transfer_Revert_ToZeroAddress() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        vm.prank(trader1);
        vm.expectRevert("ERC20: transfer to zero");
        _token().transfer(address(0), 100e18);
    }

    function test_ParametricTransfer_Revert_InvalidSubId() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        vm.prank(trader1);
        vm.expectRevert("Not super account");
        _token().parametricTransfer(1, trader2, 0, 100e18);
    }

    function test_ParametricTransfer_Revert_ToInvalidSubId() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        vm.prank(trader1);
        vm.expectRevert("Not super account");
        _token().parametricTransfer(0, trader2, 1, 100e18);
    }

    // ====== ALLOWANCES ======

    function test_Approve_SetsTotal_CapsSub() public {
        vm.prank(trader1);
        _token().approve(trader2, 1000);
        assertEq(_token().allowance(trader1, trader2), 1000);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        _token().approveForSub(1, trader2, 500, true, 0);
        vm.stopPrank();

        (uint48 subId, uint256 subAmount, bool oneOff, ) = _token()
            .subAllowance(trader1, trader2);
        assertEq(subId, 1);
        assertEq(subAmount, 500);
        assertTrue(oneOff);

        vm.prank(trader1);
        _token().approve(trader2, 0);

        (subId, subAmount, oneOff, ) = _token().subAllowance(trader1, trader2);
        assertEq(subId, 0);
        assertEq(subAmount, 0);
        assertFalse(oneOff);
        assertEq(_token().allowance(trader1, trader2), 0);
    }

    function test_ApproveForSub_MaintainsGeneralAllowance() public {
        vm.prank(trader1);
        _token().approve(trader2, 1000);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        _token().approveForSub(1, trader2, 300, false, 0);
        vm.stopPrank();

        assertEq(_token().allowance(trader1, trader2), 1000);
        (uint256 subAmount, , ) = _token().allowanceOf(trader1, 1, trader2);
        assertEq(subAmount, 300);

        vm.startPrank(trader1);
        _token().approveForSub(1, trader2, 200, false, 0);
        vm.stopPrank();

        (subAmount, , ) = _token().allowanceOf(trader1, 1, trader2);
        assertEq(subAmount, 200);
        assertEq(_token().allowance(trader1, trader2), 900);

        vm.startPrank(trader1);
        _token().approveForSub(1, trader2, 1200, false, 0);
        vm.stopPrank();

        assertEq(_token().allowance(trader1, trader2), 1200);
        (subAmount, , ) = _token().allowanceOf(trader1, 1, trader2);
        assertEq(subAmount, 1200);
    }

    function test_CommittedUntil_PreventsReduction() public {
        vm.prank(trader1);
        _token().approve(trader2, 1000);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        _token().createSubAccount();
        uint64 future = uint64(block.timestamp + 1000);
        _token().approveForSub(1, trader2, 500, false, future);
        vm.stopPrank();

        // Try to reduce sub allowance before expiry – should revert
        vm.startPrank(trader1);
        vm.expectRevert("Committed allowance can't be reduced");
        _token().approveForSub(1, trader2, 300, false, 0);
        vm.stopPrank();

        // Try to change subId – should revert
        vm.startPrank(trader1);
        vm.expectRevert("Committed allowance can't be changed");
        _token().approveForSub(2, trader2, 500, false, 0);
        vm.stopPrank();

        // But increasing is allowed
        vm.startPrank(trader1);
        _token().approveForSub(1, trader2, 600, false, 0);
        vm.stopPrank();

        (uint256 subAmount, , ) = _token().allowanceOf(trader1, 1, trader2);
        assertEq(subAmount, 600);

        // Check committedUntil still set
        (, , , uint64 committed) = _token().subAllowance(trader1, trader2);
        assertGt(committed, block.timestamp);
    }

    function test_CommittedUntil_ExpiredAllowsReduction() public {
        vm.prank(trader1);
        _token().approve(trader2, 1000);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        uint64 future = uint64(block.timestamp + 100);
        _token().approveForSub(1, trader2, 500, false, future);
        vm.stopPrank();

        // Warp past expiry
        vm.warp(block.timestamp + 200);

        // Now we can reduce
        vm.startPrank(trader1);
        _token().approveForSub(1, trader2, 200, false, 0);
        vm.stopPrank();

        (uint256 subAmount, , ) = _token().allowanceOf(trader1, 1, trader2);
        assertEq(subAmount, 200);
        // committedUntil should be reset to 0
        (, , , uint64 committed) = _token().subAllowance(trader1, trader2);
        assertEq(committed, 0);
    }

    function test_CommittedUntil_AllowanceNotExpired_SpendStillWorks() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        uint256 bunBalance = _token().balanceOf(trader1);
        assertGt(bunBalance, 400e18, "Not enough BUN tokens minted");

        vm.prank(trader1);
        _token().approve(trader2, 1000e18);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();

        // Set committed allowance on subId=1 for 500e18 (not one-off)
        uint64 future = uint64(block.timestamp + 1000);
        _token().approveForSub(1, trader2, 500e18, false, future);

        // Transfer 400e18 tokens to sub-account 1
        _token().parametricTransfer(0, trader1, 1, 400e18);
        vm.stopPrank();

        // Now spender (trader2) spends 200e18 from subId=1
        vm.prank(trader2);
        _token().parametricTransferFrom(trader1, 1, trader2, 0, 200e18);

        // Check remaining specific allowance
        (uint256 subAmount, , ) = _token().allowanceOf(trader1, 1, trader2);
        assertEq(
            subAmount,
            300e18,
            "Sub-allowance should be reduced by 200e18"
        );

        // Check that committedUntil is still set (not expired)
        (, , , uint64 committed) = _token().subAllowance(trader1, trader2);
        assertGt(
            committed,
            block.timestamp,
            "Commitment should still be active"
        );
    }

    // ====== NZS EVENT EMISSION ======

    function _verifyNzsEvent(
        Vm.Log memory log,
        ExpectedNzs memory expected
    ) internal pure {
        bytes32 eventSig = keccak256(
            "ParametricTransferNzs(address,uint48,address,uint48,uint256,int256,uint64[],uint64[])"
        );
        require(log.topics[0] == eventSig, "Wrong event");

        (
            uint48 toSubId,
            uint256 debitAmount,
            int256 creditAmount,
            uint64[] memory fromParams,
            uint64[] memory toParams
        ) = abi.decode(log.data, (uint48, uint256, int256, uint64[], uint64[]));

        assertEq(toSubId, 0, "toSubId");
        assertEq(debitAmount, expected.debit, "debit");
        assertEq(uint256(creditAmount), expected.credit, "credit");
        assertEq(fromParams.length, 1, "fromParams length");
        assertEq(fromParams[0], expected.fromParam, "fromParam");
        assertEq(toParams.length, 1, "toParams length");
        assertEq(toParams[0], expected.toParam, "toParam");

        assertEq(
            address(uint160(uint256(log.topics[1]))),
            expected.from,
            "from"
        );
        assertEq(uint48(uint256(log.topics[2])), 0, "fromSubId");
        assertEq(address(uint160(uint256(log.topics[3]))), expected.to, "to");
    }

    function test_NZS_Event_Emitted_OnTransfer() public {
        // Deposit trader1
        uint256 wbtcAmount = 0.8e18;
        uint256 invAmount = 80000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        // Deposit trader2
        uint256 wbtc2 = 0.2e18;
        uint256 inv2 = 20000e18;
        _approveEngine(trader2, wbtc2, inv2);
        vm.prank(trader2);
        engine.deposit(wbtc2, inv2);

        uint64 trader1Anchor = _anchor(trader1, 0);
        uint64 trader2Anchor = _anchor(trader2, 0);
        uint256 trader1Balance = _token().balanceOf(trader1);
        uint256 trader2Balance = _token().balanceOf(trader2);

        uint256 transferAmount = trader1Balance / 2;

        (uint64 expectedAnchor, uint256 expectedToBalance) = Lib.combine(
            trader1Anchor,
            transferAmount,
            trader2Anchor,
            trader2Balance
        );
        uint256 expectedCredit = expectedToBalance - trader2Balance;

        ExpectedNzs memory expected = ExpectedNzs({
            from: trader1,
            to: trader2,
            debit: transferAmount,
            credit: expectedCredit,
            fromParam: trader1Anchor,
            toParam: expectedAnchor
        });

        vm.recordLogs();
        vm.prank(trader1);
        _token().transfer(trader2, transferAmount);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSig = keccak256(
            "ParametricTransferNzs(address,uint48,address,uint48,uint256,int256,uint64[],uint64[])"
        );

        bool found = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                _verifyNzsEvent(logs[i], expected);
                found = true;
                break;
            }
        }
        assertTrue(found, "Event not emitted");
    }

    // ====== SUB-ACCOUNT MANAGEMENT ======

    function test_ConvertToSuper_Success() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        uint64 anchorBefore = _anchor(trader1, 0);

        vm.prank(trader1);
        _token().convertToSuper();

        assertTrue(_token().isSuperAccount(trader1));
        assertEq(_token().subsCountOf(trader1), 1);
        assertEq(
            _token().parametricBalanceOf(trader1, 0),
            _token().balanceOf(trader1)
        );
        assertEq(_anchor(trader1, 0), anchorBefore);
    }

    function test_CreateSubAccount_Success() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        vm.startPrank(trader1);
        _token().convertToSuper();
        uint48 subId = _token().createSubAccount();
        vm.stopPrank();

        assertEq(subId, 1);
        assertEq(_token().subsCountOf(trader1), 2);
        assertEq(_token().parametricBalanceOf(trader1, 1), 0);
        assertEq(_anchor(trader1, 1), 0);
    }

    // ====== QUERIES ======

    function test_ParameterOf_Valid() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        uint64 anchor = _anchor(trader1, 0);
        assertEq(_token().parameterOf(trader1, 0, 0), anchor);
    }

    function test_ParameterOf_Revert_InvalidParamIndex() public {
        vm.expectRevert("Invalid param index");
        _token().parameterOf(trader1, 0, 1);
    }

    function test_AnchorGetter() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        assertEq(_token().anchor(trader1, 0), _anchor(trader1, 0));
    }

    function test_IsNonZeroSum() public view {
        assertTrue(
            _token().isNonZeroSum(),
            "Bundle token must be non-zero-sum"
        );
    }

    // ====== GAS REPORTING ======

    function test_GasReport_approveForSub() public {
        // Deposit to get BUN tokens (so they have parameters)
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        vm.stopPrank();

        vm.prank(trader1);
        _token().approve(trader2, 1000e18);

        for (uint i = 0; i < 12; i++) {
            vm.prank(trader1);
            _token().approveForSub(1, trader2, 100e18 * (i + 1), false, 0);
        }
    }

    function test_GasReport_allowanceOf() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        _token().approveForSub(1, trader2, 500e18, false, 0);
        vm.stopPrank();

        for (uint i = 0; i < 12; i++) {
            (uint256 al, , ) = _token().allowanceOf(trader1, 1, trader2);
            al += 1;
        }
    }

    function test_GasReport_parameterOf() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        for (uint i = 0; i < 12; i++) {
            _token().parameterOf(trader1, 0, 0);
        }
    }

    function test_GasReport_parametricBalanceOf() public {
        uint256 wbtcAmount = 0.5e18;
        uint256 invAmount = 50000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        vm.prank(trader1);
        _token().convertToSuper();

        for (uint i = 0; i < 12; i++) {
            _token().parametricBalanceOf(trader1, 0);
        }
    }

    function test_GasReport_transfer_() public {
        // Deposit two different ratios to get different anchors
        uint256 wbtc1 = 0.5e18;
        uint256 inv1 = 50000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);

        uint bunBal = _token().balanceOf(trader1);
        vm.prank(trader1);
        _token().transfer(trader2, bunBal);

        // Second deposit with different ratio to change anchor
        uint256 wbtc2 = 0.1e18;
        uint256 inv2 = 40000e18;
        _approveEngine(trader1, wbtc2, inv2);
        vm.prank(trader1);
        engine.deposit(wbtc2, inv2);

        bunBal = _token().balanceOf(trader1);

        vm.prank(trader1);
        _token().convertToSuper();

        for (uint i = 0; i < 12; i++) {
            vm.prank(trader1);
            _token().transfer(trader2, bunBal / 20);
        }
    }

    function test_GasReport_transferFrom() public {
        uint256 wbtc1 = 0.5e18;
        uint256 inv1 = 50000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);

        uint bunBal = _token().balanceOf(trader1);
        vm.prank(trader1);
        _token().transfer(trader2, bunBal);

        uint256 wbtc2 = 0.1e18;
        uint256 inv2 = 40000e18;
        _approveEngine(trader1, wbtc2, inv2);
        vm.prank(trader1);
        engine.deposit(wbtc2, inv2);

        bunBal = _token().balanceOf(trader1);

        vm.prank(trader1);
        _token().convertToSuper();
        vm.prank(trader1);
        _token().approve(trader2, bunBal);

        uint256 amount = 50e18;
        for (uint i = 0; i < 12; i++) {
            vm.prank(trader2);
            _token().transferFrom(trader1, trader2, bunBal / 20);
        }
    }

    function test_GasReport_parametricTransfer_() public {
        uint256 wbtc1 = 0.5e18;
        uint256 inv1 = 50000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);

        uint bunBal = _token().balanceOf(trader1);
        vm.prank(trader1);
        _token().transfer(trader2, bunBal);

        uint256 wbtc2 = 0.1e18;
        uint256 inv2 = 40000e18;
        _approveEngine(trader1, wbtc2, inv2);
        vm.prank(trader1);
        engine.deposit(wbtc2, inv2);

        bunBal = _token().balanceOf(trader1);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        vm.stopPrank();

        // Move some to sub-account 1
        vm.prank(trader1);
        _token().parametricTransfer(0, trader1, 1, bunBal);

        uint256 amount = 50e18;
        for (uint i = 0; i < 12; i++) {
            vm.prank(trader1);
            _token().parametricTransfer(1, trader2, 0, bunBal / 20);
        }
    }

    function test_GasReport_parametricTransferFrom() public {
        uint256 wbtc1 = 0.5e18;
        uint256 inv1 = 50000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);

        uint bunBal = _token().balanceOf(trader1);
        vm.prank(trader1);
        _token().transfer(trader2, bunBal);

        uint256 wbtc2 = 0.1e18;
        uint256 inv2 = 40000e18;
        _approveEngine(trader1, wbtc2, inv2);
        vm.prank(trader1);
        engine.deposit(wbtc2, inv2);

        bunBal = _token().balanceOf(trader1);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        _token().parametricTransfer(0, trader1, 1, bunBal);
        _token().approveForSub(1, trader2, bunBal, false, 0);
        vm.stopPrank();

        uint256 amount = 50e18;
        for (uint i = 0; i < 12; i++) {
            vm.prank(trader2);
            _token().parametricTransferFrom(trader1, 1, trader2, 0, amount);
        }
    }

    function test_GasReport_mint() public {
        // Mint directly via engine to create BUN tokens with anchor
        uint256 wbtcAmount = 0.1e18;
        uint256 invAmount = 10000e18;
        _approveEngine(trader1, wbtcAmount, invAmount);
        vm.prank(trader1);
        engine.deposit(wbtcAmount, invAmount);

        vm.prank(trader1);
        _token().convertToSuper();

        // Now mint directly using engine mint (which is onlyEngine)
        uint256 amount = 50e18;
        for (uint i = 0; i < 12; i++) {
            vm.prank(address(engine));
            _token().mint(trader1, amount, 30000e8 + uint64(i * 1000e8));
        }
    }

    function test_GasReport_burn() public {
        // Deposit to get enough BUN
        uint256 wbtc1 = 0.5e18;
        uint256 inv1 = 50000e18;
        _approveEngine(trader1, wbtc1, inv1);
        vm.prank(trader1);
        engine.deposit(wbtc1, inv1);

        uint bunBal = _token().balanceOf(trader1);

        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        vm.stopPrank();

        uint256 amount = 50e18;
        for (uint i = 0; i < 12; i++) {
            vm.prank(address(engine));
            _token().burn(trader1, 0, bunBal / 20);
        }
    }
}
