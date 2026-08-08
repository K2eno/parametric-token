// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/bundle/BundleToken.sol";
import "../../src/bundle/BundleEngine.sol";
import "../../src/mock/AssetToken.sol";
import "../../src/interfaces/IParametricTokenNzs.sol";

contract BundleTokenTest is Test {
    BundleToken public token;
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
        token = new BundleToken("BundleToken", "BUN");
        engine = new BundleEngine(
            address(token),
            address(wbtc),
            address(inv),
            INITIAL_PRICE
        );
        token.setEngine(address(engine));
    }

    // --- Helpers ---

    function _anchor(
        address account,
        uint48 subId
    ) internal view returns (uint64) {
        return token.anchor(account, subId);
    }

    function _mintToken(address to, uint256 amount, uint64 anchor_) internal {
        vm.startPrank(address(engine));
        token.mint(to, amount, anchor_);
        vm.stopPrank();
    }

    function _burnToken(address from, uint48 subId, uint256 amount) internal {
        vm.startPrank(address(engine));
        token.burn(from, subId, amount);
        vm.stopPrank();
    }

    // ====== DEPLOYMENT & STATE ======

    function test_Deployment_State() public view {
        assertEq(token.name(), "BundleToken");
        assertEq(token.symbol(), "BUN");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(admin), 0);
        assertEq(token.NUMBER_OF_PARAMETERS(), 1);
        (bytes32 name, uint8 decimals, bool isMutable) = token.paramConfig(0);
        assertEq(name, "anchor");
        assertEq(decimals, 8);
        assertTrue(isMutable);
        // Check NZS interface support
        assertTrue(
            token.supportsInterface(type(IParametricTokenNzs).interfaceId)
        );
    }

    // ====== MINTING ======

    function test_Mint_Success() public {
        uint256 amount = 1000e18;
        uint64 anchor_ = 30000e8;
        _mintToken(trader1, amount, anchor_);
        assertEq(token.balanceOf(trader1), amount);
        assertEq(_anchor(trader1, 0), anchor_);
        assertEq(token.totalSupply(), amount);
    }

    function test_Mint_Revert_ZeroAddress() public {
        vm.prank(address(engine));
        vm.expectRevert("Mint to zero");
        token.mint(address(0), 1000e18, 30000e8);
    }

    function test_Mint_Revert_ZeroAmount() public {
        vm.prank(address(engine));
        vm.expectRevert("Void amount");
        token.mint(trader1, 0, 30000e8);
    }

    function test_Mint_Revert_ZeroAnchor() public {
        vm.prank(address(engine));
        vm.expectRevert("Zero anchor");
        token.mint(trader1, 1000e18, 0);
    }

    function test_Mint_Combine_ExistingBalance() public {
        _mintToken(trader1, 1000e18, 30000e8);
        uint256 amount2 = 2000e18;
        uint64 anchor2 = 32000e8;
        _mintToken(trader1, amount2, anchor2);
        (uint64 newAnchor, uint256 newBalance) = Lib.combine(
            anchor2,
            amount2,
            30000e8,
            1000e18
        );
        assertEq(_anchor(trader1, 0), newAnchor);
        assertEq(token.balanceOf(trader1), newBalance);
        assertEq(token.totalSupply(), newBalance);
    }

    // ====== TRANSFERS ======

    function test_Transfer_NormalToEmpty_CopiesAnchor() public {
        _mintToken(trader1, 1000e18, 30000e8);
        uint256 transferAmount = 500e18;
        vm.prank(trader1);
        token.transfer(trader2, transferAmount);
        assertEq(token.balanceOf(trader1), 1000e18 - transferAmount);
        assertEq(token.balanceOf(trader2), transferAmount);
        assertEq(_anchor(trader2, 0), 30000e8);
        assertEq(_anchor(trader1, 0), 30000e8);
    }

    function test_Transfer_ToExisting_Combine() public {
        _mintToken(trader1, 1000e18, 30000e8);
        _mintToken(trader2, 800e18, 32000e8);
        uint256 transferAmount = 500e18;
        (uint64 expectedAnchor, uint256 expectedToBalance) = Lib.combine(
            30000e8,
            transferAmount,
            32000e8,
            800e18
        );
        uint256 expectedCredit = expectedToBalance - 800e18;

        vm.prank(trader1);
        token.transfer(trader2, transferAmount);

        assertEq(token.balanceOf(trader1), 1000e18 - transferAmount);
        assertEq(token.balanceOf(trader2), expectedToBalance);
        assertEq(_anchor(trader2, 0), expectedAnchor);
        assertEq(_anchor(trader1, 0), 30000e8);
        assertTrue(expectedCredit != transferAmount); // NZS
    }

    function test_Transfer_Self_SameSubId_NoStateChange() public {
        _mintToken(trader1, 1000e18, 30000e8);
        uint64 anchorBefore = _anchor(trader1, 0);
        vm.prank(trader1);
        token.transfer(trader1, 500e18);
        assertEq(token.balanceOf(trader1), 1000e18);
        assertEq(_anchor(trader1, 0), anchorBefore);
    }

    function test_Transfer_Self_DifferentSubIds() public {
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        vm.stopPrank();
        _mintToken(trader1, 1000e18, 30000e8);
        vm.prank(trader1);
        token.parametricTransfer(0, trader1, 1, 400e18);
        assertEq(token.parametricBalanceOf(trader1, 0), 600e18);
        assertEq(token.parametricBalanceOf(trader1, 1), 400e18);
        assertEq(_anchor(trader1, 0), 30000e8);
        assertEq(_anchor(trader1, 1), 30000e8);
        vm.prank(trader1);
        token.parametricTransfer(1, trader1, 0, 200e18);
        (uint64 newAnchor, uint256 newBalance) = Lib.combine(
            30000e8,
            200e18,
            30000e8,
            600e18
        );
        assertEq(token.parametricBalanceOf(trader1, 0), newBalance);
        assertEq(token.parametricBalanceOf(trader1, 1), 200e18);
        assertEq(_anchor(trader1, 0), newAnchor);
        assertEq(_anchor(trader1, 1), 30000e8);
    }

    function test_Transfer_Revert_InsufficientBalance() public {
        _mintToken(trader1, 1000e18, 30000e8);
        vm.prank(trader1);
        vm.expectRevert("Insufficient balance");
        token.transfer(trader2, 1001e18);
    }

    function test_ParametricTransfer_Revert_NormalFromSubId() public {
        _mintToken(trader1, 1000e18, 30000e8);
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
        vm.prank(trader1);
        token.approve(trader2, 0);
        (subId, subAmount, oneOff) = token.subAllowance(trader1, trader2);
        assertEq(subId, 1);
        assertEq(subAmount, 0);
        assertFalse(oneOff);
        assertEq(token.allowance(trader1, trader2), 0);
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
        vm.startPrank(trader1);
        token.approveForSub(1, trader2, 200, false);
        vm.stopPrank();
        (subAmount, ) = token.allowanceForSub(trader1, 1, trader2);
        assertEq(subAmount, 200);
        assertEq(token.allowance(trader1, trader2), 900);
        general = token.allowance(trader1, trader2) - subAmount;
        assertEq(general, 700);
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
        _mintToken(trader1, 1000e18, 30000e8);
        vm.prank(trader1);
        token.approve(trader2, 500e18);
        vm.prank(trader2);
        token.transferFrom(trader1, trader2, 200e18);
        assertEq(token.balanceOf(trader1), 800e18);
        assertEq(token.balanceOf(trader2), 200e18);
        assertEq(token.allowance(trader1, trader2), 300e18);
        assertEq(_anchor(trader2, 0), 30000e8);
    }

    function test_TransferFrom_Super_SubIdNonZero_SpendsGeneral() public {
        _mintToken(trader1, 1000e18, 30000e8);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        token.createSubAccount(trader1);
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
        assertEq(_anchor(trader2, 0), 30000e8);
    }

    function test_ParametricTransferFrom_Super_SpendsSub() public {
        _mintToken(trader1, 1000e18, 30000e8);
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
        assertEq(_anchor(trader2, 0), 30000e8);
    }

    function test_OneOffAllowance_SpendExactSubId_ConsumesAll() public {
        _mintToken(trader1, 1000e18, 30000e8);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        token.parametricTransfer(0, trader1, 1, 500e18);
        token.approveForSub(1, trader2, 300e18, true);
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
        _mintToken(trader1, 1000e18, 30000e8);
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
        _mintToken(trader1, 1000e18, 30000e8);
        _burnToken(trader1, 0, 1000e18);
        assertEq(token.balanceOf(trader1), 0);
        assertEq(token.totalSupply(), 0);
        assertEq(_anchor(trader1, 0), 0);
    }

    function test_Burn_Partial_NoReset() public {
        _mintToken(trader1, 1000e18, 30000e8);
        uint64 anchorBefore = _anchor(trader1, 0);
        _burnToken(trader1, 0, 400e18);
        assertEq(token.balanceOf(trader1), 600e18);
        assertEq(token.totalSupply(), 600e18);
        assertEq(_anchor(trader1, 0), anchorBefore);
    }

    function test_Burn_Revert_NotEngine() public {
        vm.prank(trader1);
        vm.expectRevert("Not engine");
        token.burn(trader1, 0, 100e18);
    }

    function test_Burn_Revert_SubIdInvalid() public {
        _mintToken(trader1, 1000e18, 30000e8);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        token.createSubAccount(trader1);
        vm.stopPrank();
        vm.prank(address(engine));
        vm.expectRevert("Sub-account doesn't exist");
        token.burn(trader1, 2, 100e18);
    }

    function test_Burn_Revert_InsufficientBalance() public {
        _mintToken(trader1, 1000e18, 30000e8);
        vm.prank(address(engine));
        vm.expectRevert("Insufficient balance");
        token.burn(trader1, 0, 1001e18);
    }

    // ====== SUB-ACCOUNT MANAGEMENT ======

    function test_ConvertToSuper_Success() public {
        _mintToken(trader1, 1000e18, 30000e8);
        uint64 anchorBefore = _anchor(trader1, 0);
        vm.prank(trader1);
        token.convertToSuper(trader1);
        assertEq(
            uint8(token.accountType(trader1)),
            uint8(IParametricToken.AccountType.Super)
        );
        assertEq(token.subsCountOf(trader1), 1);
        assertEq(token.parametricBalanceOf(trader1, 0), 1000e18);
        assertEq(_anchor(trader1, 0), anchorBefore);
    }

    function test_ConvertToSuper_Revert_NotNormal() public {
        vm.prank(trader1);
        token.convertToSuper(trader1);
        vm.prank(trader1);
        vm.expectRevert("Not normal account");
        token.convertToSuper(trader1);
    }

    function test_CreateSubAccount_Success() public {
        _mintToken(trader1, 1000e18, 30000e8);
        vm.startPrank(trader1);
        token.convertToSuper(trader1);
        uint48 subId = token.createSubAccount(trader1);
        vm.stopPrank();
        assertEq(subId, 1);
        assertEq(token.subsCountOf(trader1), 2);
        assertEq(token.parametricBalanceOf(trader1, 1), 0);
        assertEq(_anchor(trader1, 1), 0);
    }

    function test_CreateSubAccount_Revert_NotSuper() public {
        vm.prank(trader1);
        vm.expectRevert("Not super account");
        token.createSubAccount(trader1);
    }

    // ====== QUERIES ======

    function test_ParameterOf_Valid() public {
        _mintToken(trader1, 1000e18, 30000e8);
        assertEq(token.parameterOf(0, trader1, 0), 30000e8);
    }

    function test_ParameterOf_Revert_InvalidParamIndex() public {
        vm.expectRevert("Invalid param index");
        token.parameterOf(1, trader1, 0);
    }

    function test_AllParametersOf() public {
        _mintToken(trader1, 1000e18, 30000e8);
        uint64[] memory params = token.allParametersOf(trader1, 0);
        assertEq(params.length, 1);
        assertEq(params[0], 30000e8);
    }

    function test_AnchorGetter() public {
        _mintToken(trader1, 1000e18, 30000e8);
        assertEq(token.anchor(trader1, 0), 30000e8);
    }

    // ====== NZS EVENT EMISSION ======

    function _verifyNzsEvent(
        Vm.Log memory log,
        ExpectedNzs memory expected
    ) internal pure {
        bytes32 eventSig = keccak256(
            "ParametricTransferNzs(address,uint48,address,uint48,uint256,uint256,uint64[],uint64[])"
        );
        require(log.topics[0] == eventSig, "Wrong event");

        (
            uint48 toSubId,
            uint256 debitAmount,
            uint256 creditAmount,
            uint64[] memory fromParams,
            uint64[] memory toParams
        ) = abi.decode(
                log.data,
                (uint48, uint256, uint256, uint64[], uint64[])
            );

        assertEq(toSubId, 0, "toSubId");
        assertEq(debitAmount, expected.debit, "debit");
        assertEq(creditAmount, expected.credit, "credit");
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
        uint64 trader1Anchor = 90000e8;
        uint64 trader2Anchor = 54000e8;
        uint256 trader1Balance = 1000e18;
        uint256 trader2Balance = 2800e18;

        _mintToken(trader1, trader1Balance, trader1Anchor);
        _mintToken(trader2, trader2Balance, trader2Anchor);

        uint256 transferAmount = 500e18;

        (uint64 expectedAnchor, uint256 expectedToBalance) = Lib.combine(
            trader1Anchor,
            transferAmount,
            trader2Anchor,
            trader2Balance
        );
        uint256 expectedCredit = expectedToBalance - trader2Balance;

        // Build expected struct
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
        token.transfer(trader2, transferAmount);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSig = keccak256(
            "ParametricTransferNzs(address,uint48,address,uint48,uint256,uint256,uint64[],uint64[])"
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
}
