// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "../interfaces/spec/IParametricToken.sol";
import "../interfaces/ITenureToken.sol";

import "./Storage.sol";

contract Router is Ownable, ERC165, Storage {
    // ====== IMMUTABLE LOGIC ADDRESSES ======

    address public immutable LOGIC_CORE;
    address public immutable LOGIC_TENURE_TOKEN;

    // ====== CONSTRUCTOR ======

    constructor(
        address core,
        address tenure,
        string memory name_,
        string memory symbol_
    ) Ownable(msg.sender) {
        LOGIC_CORE = core;
        LOGIC_TENURE_TOKEN = tenure;

        AppStorage storage s = _s();
        s.name = name_;
        s.symbol = symbol_;
        s.totalSupply = 0;
        // s.engine default to 0
        s.paramConfig.push(
            IParametricToken.ParamConfig({
                name: "mintTime",
                decimals: 0,
                isMutable: true
            })
        );
    }

    // ====== FALLBACK ======

    fallback() external payable {
        address target;
        bytes4 sel = msg.sig;

        // Core functions (ERC-20, allowances, sub-accounts)
        if (
            sel == IERC20.approve.selector ||
            sel == IERC20.allowance.selector ||
            sel == IERC20.balanceOf.selector ||
            sel == IERC20.totalSupply.selector ||
            sel == IERC20Metadata.name.selector ||
            sel == IERC20Metadata.symbol.selector ||
            sel == IERC20Metadata.decimals.selector ||
            sel == IParametricToken.convertToSuper.selector ||
            sel == IParametricToken.createSubAccount.selector ||
            sel == IParametricToken.isSuperAccount.selector ||
            sel == IParametricToken.subsCountOf.selector ||
            sel == IParametricToken.parametricBalanceOf.selector ||
            sel == IParametricToken.approveForSub.selector ||
            sel == IParametricToken.subAllowance.selector ||
            sel == IParametricToken.allowanceOf.selector ||
            sel == IParametricToken.parameterOf.selector
        ) {
            target = LOGIC_CORE;
        }
        // Tenure-specific functions
        else if (
            sel == IParametricToken.paramConfig.selector ||
            sel == IERC20.transfer.selector ||
            sel == IERC20.transferFrom.selector ||
            sel == IParametricToken.parametricTransfer.selector ||
            sel == IParametricToken.parametricTransferFrom.selector ||
            sel == ITenureToken.mint.selector ||
            sel == ITenureToken.burn.selector ||
            sel == ITenureToken.mintTime.selector ||
            sel == ITenureToken.engine.selector ||
            sel == ITenureToken.setEngine.selector
        ) {
            target = LOGIC_TENURE_TOKEN;
        } else {
            revert("Selector not found");
        }

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}

    // ====== FUNCTIONS ======

    function NUMBER_OF_PARAMETERS() external pure returns (uint8) {
        return NUMBER_OF_PARAMS;
    }

    // ====== SUPPORTS INTERFACE ======

    function supportsInterface(
        bytes4 interfaceId
    ) public pure override returns (bool) {
        return interfaceId == type(IParametricToken).interfaceId;
    }
}
