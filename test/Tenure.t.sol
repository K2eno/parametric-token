// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

import "../../src/tenure/Router.sol";
import "../../src/tenure/Core.sol";
import "../../src/tenure/Tenure.sol";
import "../../src/interfaces/ITenureToken.sol";
import "../../src/tenure/TenureEngine.sol";
import "../../src/interfaces/spec/IParametricToken.sol";
import "../../src/libraries/Lib.sol";

contract TenureTokenTest is Test {
    Router public router;
    Core public core;
    Tenure public tokenLogic;
    TenureEngine public engine;

    address public admin = address(0x1);
    address public trader1 = address(0x2);
    address public trader2 = address(0x3);
    address public trader3 = address(0x4);

    uint64 public constant REWARDS_RATE = 100; // 1% per 30 days
    uint256 public constant INITIAL_TIMESTAMP = 1_700_000_000;

    function setUp() public {
        vm.warp(INITIAL_TIMESTAMP);

        // Deploy logic contracts
        core = new Core();
        tokenLogic = new Tenure();

        // Deploy Router (no permissions)
        router = new Router(
            address(core),
            address(tokenLogic),
            "TenureToken",
            "TEN"
        );

        // Deploy Engine
        engine = new TenureEngine(address(router), REWARDS_RATE);

        // Set engine on Router (delegates to Tenure)
        ITenureToken(address(router)).setEngine(address(engine));

        // Transfer ownership to admin
        router.transferOwnership(admin);
        engine.transferOwnership(admin);

        vm.deal(admin, 100 ether);
        vm.deal(trader1, 100 ether);
        vm.deal(trader2, 100 ether);
        vm.deal(trader3, 100 ether);
    }

    // ====== HELPERS ======

    function _token() internal view returns (ITenureToken) {
        return ITenureToken(address(router));
    }

    function _mintTime(
        address account,
        uint48 subId
    ) internal view returns (uint64) {
        return _token().mintTime(account, subId);
    }

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

    // ====== DEPLOYMENT & STATE ======

    function test_Deployment_State() public view {
        assertEq(_token().name(), "TenureToken");
        assertEq(_token().symbol(), "TEN");
        assertEq(_token().decimals(), 18);
        assertEq(_token().totalSupply(), 0);
        assertEq(_token().balanceOf(admin), 0);
        assertEq(_token().NUMBER_OF_PARAMETERS(), 1);

        IParametricToken.ParamConfig[]
            memory params = new IParametricToken.ParamConfig[](1);
        params = _token().paramConfig();
        assertEq(params[0].name, "mintTime");
        assertEq(params[0].decimals, 0);
        assertTrue(params[0].isMutable);

        // Engine state
        assertEq(engine.rewardsRateBps(), REWARDS_RATE);
    }

    // ====== MINTING ======

    function test_Mint_Success() public {
        uint256 amount = 1000e18;
        vm.warp(INITIAL_TIMESTAMP + 100);
        _mint(trader1, amount);
        assertEq(_token().balanceOf(trader1), amount);
        assertEq(_mintTime(trader1, 0), uint64(INITIAL_TIMESTAMP + 100));
        assertEq(_token().totalSupply(), amount);
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
        assertEq(_token().balanceOf(trader1), a1 + a2);
    }

    function test_Mint_ToSuperAccount_Sub0() public {
        vm.startPrank(trader1);
        _token().convertToSuper();
        vm.stopPrank();
        uint256 amount = 1000e18;
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, amount);
        assertEq(_token().parametricBalanceOf(trader1, 0), amount);
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
        assertEq(_token().parametricBalanceOf(trader1, 0), amount + amount);
    }

    // ====== TRANSFERS ======

    function test_Transfer_NormalToNormal_Success() public {
        uint256 amount = 1000e18;
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, amount);
        vm.prank(trader1);
        _token().transfer(trader2, amount);
        assertEq(_token().balanceOf(trader1), 0);
        assertEq(_token().balanceOf(trader2), amount);
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
        _token().transfer(trader2, 500e18);
        uint64 expected = uint64(
            (uint256(t2) * 500e18 + uint256(t1) * 500e18) / (500e18 + 500e18)
        );
        assertEq(_token().balanceOf(trader1), 500e18);
        assertEq(_token().balanceOf(trader2), 1000e18);
        assertEq(_mintTime(trader2, 0), expected);
        assertEq(_mintTime(trader1, 0), t1); // sender balance not zero
    }

    function test_Transfer_ToEmpty_CopiesMintTime() public {
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        _token().transfer(trader2, 500e18);
        assertEq(_token().balanceOf(trader2), 500e18);
        assertEq(_mintTime(trader2, 0), mintTime);
    }

    function test_Transfer_Self_SameSubId_NoStateChange() public {
        _mint(trader1, 1000e18);
        uint64 mintTime = _mintTime(trader1, 0);
        vm.prank(trader1);
        _token().transfer(trader1, 500e18);
        assertEq(_token().balanceOf(trader1), 1000e18);
        assertEq(_mintTime(trader1, 0), mintTime);
    }

    function test_Transfer_Self_DifferentSubIds() public {
        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        vm.stopPrank();
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        _token().parametricTransfer(0, trader1, 1, 500e18);
        assertEq(_token().parametricBalanceOf(trader1, 0), 500e18);
        assertEq(_token().parametricBalanceOf(trader1, 1), 500e18);
        assertEq(_mintTime(trader1, 0), mintTime);
        assertEq(_mintTime(trader1, 1), mintTime);
        vm.prank(trader1);
        _token().parametricTransfer(1, trader1, 0, 250e18);
        assertEq(_token().parametricBalanceOf(trader1, 0), 750e18);
        assertEq(_token().parametricBalanceOf(trader1, 1), 250e18);
        assertEq(_mintTime(trader1, 0), mintTime);
        assertEq(_mintTime(trader1, 1), mintTime);
    }

    function test_Transfer_Revert_InsufficientBalance() public {
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        vm.expectRevert("Insufficient balance");
        _token().transfer(trader2, 1001e18);
    }

    function test_ParametricTransfer_Revert_NormalFromSubId() public {
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        vm.expectRevert("Not super account");
        _token().parametricTransfer(1, trader2, 0, 500e18);
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
        (subAmount, oneOff, ) = _token().allowanceOf(trader1, 1, trader2);
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

    function test_ApproveForSub_SuperOnly_Revert() public {
        vm.prank(trader1);
        vm.expectRevert("Not super account");
        _token().approveForSub(0, trader2, 100, false, 0);
    }

    function test_ApproveForSub_InvalidSubId_Revert() public {
        vm.startPrank(trader1);
        _token().convertToSuper();
        vm.expectRevert("Sub-account doesn't exist");
        _token().approveForSub(1, trader2, 100, false, 0);
        vm.stopPrank();
    }

    function test_ApproveForSub_SingleSubAccount_Revert() public {
        vm.startPrank(trader1);
        _token().convertToSuper();
        vm.expectRevert("Single sub-account");
        _token().approveForSub(0, trader2, 0, false, 0);
        vm.stopPrank();
    }

    function test_ApproveForSub_SubIdZero_RequiresZeroAmount() public {
        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        vm.expectRevert("SubId 0 requires zero amount");
        _token().approveForSub(0, trader2, 100, false, 0);
        vm.stopPrank();
    }

    function test_ApproveForSub_SubIdZero_RequiresFalseOneOff() public {
        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        vm.expectRevert("SubId 0 requires false oneOff");
        _token().approveForSub(0, trader2, 0, true, 0);
        vm.stopPrank();
    }

    function test_ApproveForSub_OneOffRequiresPositiveAmount() public {
        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        vm.expectRevert("OneOff requires positive sub allowance");
        _token().approveForSub(1, trader2, 0, true, 0);
        vm.stopPrank();
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

        // Reduce sub
        vm.startPrank(trader1);
        _token().approveForSub(1, trader2, 200, false, 0);
        vm.stopPrank();

        (subAmount, , ) = _token().allowanceOf(trader1, 1, trader2);
        assertEq(subAmount, 200);
        assertEq(_token().allowance(trader1, trader2), 900);

        // Increase sub beyond total
        vm.startPrank(trader1);
        _token().approveForSub(1, trader2, 1200, false, 0);
        vm.stopPrank();

        assertEq(_token().allowance(trader1, trader2), 1200);
        (subAmount, , ) = _token().allowanceOf(trader1, 1, trader2);
        assertEq(subAmount, 1200);
    }

    function test_TransferFrom_Normal_SpendsTotal() public {
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        _token().approve(trader2, 500e18);
        vm.prank(trader2);
        _token().transferFrom(trader1, trader2, 200e18);
        assertEq(_token().balanceOf(trader1), 800e18);
        assertEq(_token().balanceOf(trader2), 200e18);
        assertEq(_token().allowance(trader1, trader2), 300e18);
        assertEq(_mintTime(trader2, 0), _mintTime(trader1, 0)); // same
    }

    function test_TransferFrom_Super_SubIdNonZero_SpendsGeneral() public {
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount(); // subId=1
        _token().createSubAccount(); // subId=2
        _token().parametricTransfer(0, trader1, 2, 300e18);
        _token().approveForSub(1, trader2, 200e18, false, 0);
        _token().approve(trader2, 500e18);
        vm.stopPrank();

        vm.prank(trader2);
        _token().parametricTransferFrom(trader1, 2, trader2, 0, 100e18);

        assertEq(_token().allowance(trader1, trader2), 400e18);
        (uint256 subAmount, , ) = _token().allowanceOf(trader1, 1, trader2);
        assertEq(subAmount, 200e18);
        assertEq(_token().parametricBalanceOf(trader1, 2), 200e18);
        assertEq(_token().balanceOf(trader2), 100e18);
        assertEq(_mintTime(trader2, 0), _mintTime(trader1, 0)); // same
    }

    function test_ParametricTransferFrom_Super_SpendsSub() public {
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        _token().parametricTransfer(0, trader1, 1, 700e18);
        _token().approveForSub(1, trader2, 500e18, false, 0);
        vm.stopPrank();

        vm.prank(trader2);
        _token().parametricTransferFrom(trader1, 1, trader2, 0, 200e18);

        (uint256 subAmount, , ) = _token().allowanceOf(trader1, 1, trader2);
        assertEq(subAmount, 300e18);
        assertEq(_token().allowance(trader1, trader2), 300e18);
        assertEq(_token().balanceOf(trader1), 800e18);
        assertEq(_token().parametricBalanceOf(trader1, 0), 300e18);
        assertEq(_token().parametricBalanceOf(trader1, 1), 500e18);
        assertEq(_token().balanceOf(trader2), 200e18);
        assertEq(_mintTime(trader2, 0), _mintTime(trader1, 0)); // same
        // sender prediction remains because balance not zero
        assertEq(_mintTime(trader1, 0), _mintTime(trader1, 0));
    }

    // ====== ONE-OFF ALLOWANCES ======

    function test_OneOffAllowance_SpendExactSubId_ConsumesAll() public {
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        _token().approveForSub(1, trader2, 300e18, true, 0);
        _token().parametricTransfer(0, trader1, 1, 100e18);
        vm.stopPrank();

        vm.prank(trader2);
        _token().parametricTransferFrom(trader1, 1, trader2, 0, 100e18);

        (uint256 subAmount, bool oneOff, ) = _token().allowanceOf(
            trader1,
            1,
            trader2
        );
        assertEq(subAmount, 0);
        assertFalse(oneOff);
        assertEq(_token().allowance(trader1, trader2), 0);
    }

    function test_OneOffAllowance_SpendDifferentSubId_Ignored() public {
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        _token().createSubAccount();
        _token().parametricTransfer(0, trader1, 2, 500e18);
        _token().approveForSub(1, trader2, 300e18, true, 0);
        _token().approve(trader2, 500e18);
        vm.stopPrank();

        vm.prank(trader2);
        _token().parametricTransferFrom(trader1, 2, trader2, 0, 100e18);

        (uint256 subAmount, bool oneOff, ) = _token().allowanceOf(
            trader1,
            1,
            trader2
        );
        assertEq(subAmount, 300e18);
        assertTrue(oneOff);
        assertEq(_token().allowance(trader1, trader2), 400e18);
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
        assertEq(_token().balanceOf(trader1), 0);
        assertEq(_token().totalSupply(), 0);
        assertEq(_mintTime(trader1, 0), 0);
        // Points should be earned
        assertGt(engine.pointsEarned(trader1), 0);
    }

    function test_Burn_Partial_NoReset() public {
        _mint(trader1, 1000e18);
        uint64 mintTime = _mintTime(trader1, 0);
        vm.warp(block.timestamp + 1 days);
        _redeem(trader1, 0, 400e18);
        assertEq(_token().balanceOf(trader1), 600e18);
        assertEq(_token().totalSupply(), 600e18);
        assertEq(_mintTime(trader1, 0), mintTime); // unchanged
        assertGt(engine.pointsEarned(trader1), 0);
    }

    function test_Burn_Revert_NotEngine() public {
        vm.prank(trader1);
        vm.expectRevert("Not engine");
        _token().burn(trader1, 0, 100e18);
    }

    function test_Burn_Revert_SubIdInvalid() public {
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        _token().convertToSuper();
        _token().createSubAccount();
        vm.stopPrank();
        vm.prank(address(engine));
        vm.expectRevert("Sub-account doesn't exist");
        _token().burn(trader1, 2, 100e18);
    }

    function test_Burn_Revert_InsufficientBalance() public {
        _mint(trader1, 1000e18);
        vm.prank(address(engine));
        vm.expectRevert("Insufficient balance");
        _token().burn(trader1, 0, 1001e18);
    }

    // ====== SUB-ACCOUNT MANAGEMENT ======

    function test_ConvertToSuper_Success() public {
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, 1000e18);
        vm.prank(trader1);
        _token().convertToSuper();
        assertTrue(_token().isSuperAccount(trader1));
        assertEq(_token().subsCountOf(trader1), 1);
        assertEq(_token().parametricBalanceOf(trader1, 0), 1000e18);
        assertEq(_mintTime(trader1, 0), mintTime); // copied
    }

    function test_ConvertToSuper_Revert_NotNormal() public {
        vm.prank(trader1);
        _token().convertToSuper();
        vm.prank(trader1);
        vm.expectRevert("Not normal account");
        _token().convertToSuper();
    }

    function test_CreateSubAccount_Success() public {
        _mint(trader1, 1000e18);
        vm.startPrank(trader1);
        _token().convertToSuper();
        uint48 subId = _token().createSubAccount();
        vm.stopPrank();
        assertEq(subId, 1);
        assertEq(_token().subsCountOf(trader1), 2);
        assertEq(_token().parametricBalanceOf(trader1, 1), 0);
        assertEq(_mintTime(trader1, 1), 0);
    }

    function test_CreateSubAccount_Revert_NotSuper() public {
        vm.prank(trader1);
        vm.expectRevert("Not super account");
        _token().createSubAccount();
    }

    // ====== QUERIES ======

    function test_ParameterOf_Valid() public {
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, 1000e18);
        assertEq(_token().parameterOf(trader1, 0, 0), mintTime);
        // Normal account
        assertEq(_token().parameterOf(trader1, 0, 0), mintTime);
    }

    function test_ParameterOf_Revert_InvalidParamIndex() public {
        vm.expectRevert("Invalid param index");
        _token().parameterOf(trader1, 0, 1);
    }

    function test_MintTimeGetter() public {
        uint64 mintTime = uint64(block.timestamp);
        _mint(trader1, 1000e18);
        assertEq(_token().mintTime(trader1, 0), mintTime);
    }
}
