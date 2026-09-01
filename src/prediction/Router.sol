// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "../interfaces/spec/IParametricToken.sol";
import "../interfaces/spec/IParametricPermissions.sol";
import "../interfaces/IPredictionToken.sol";

import "./Storage.sol";

contract Router is Ownable, ERC165, Storage {
    // ====== IMMUTABLE LOGIC ADDRESSES ======

    address public immutable LOGIC_CORE;
    address public immutable LOGIC_PERMISSIONS;
    address public immutable LOGIC_PREDICTION_TOKEN;

    // ====== CONSTRUCTOR ======

    constructor(
        address core,
        address permissions,
        address prediction,
        string memory name_,
        string memory symbol_
    ) Ownable(msg.sender) {
        LOGIC_CORE = core;
        LOGIC_PERMISSIONS = permissions;
        LOGIC_PREDICTION_TOKEN = prediction;

        AppStorage storage s = _s();
        s.name = name_;
        s.symbol = symbol_;
        s.totalSupply = 0;
        // s.maxRounds and s.engine default to 0
        s.paramConfig.push(
            IParametricToken.ParamConfig({
                name: "prediction",
                decimals: 8,
                isMutable: true
            })
        );
        s.paramConfig.push(
            IParametricToken.ParamConfig({
                name: "round",
                decimals: 0,
                isMutable: false
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
            sel == IParametricToken.parameterOf.selector ||
            sel == IPredictionToken.allParametersOf.selector
        ) {
            target = LOGIC_CORE;
        }
        // Permissions functions
        else if (
            sel == IParametricPermissions.permitForSub.selector ||
            sel == IParametricPermissions.permissionOf.selector ||
            sel == IParametricPermissions.allPermissionsOf.selector
        ) {
            target = LOGIC_PERMISSIONS;
        }
        // Prediction-specific functions
        else if (
            sel == IParametricToken.paramConfig.selector ||
            sel == IERC20.transfer.selector ||
            sel == IERC20.transferFrom.selector ||
            sel == IParametricToken.parametricTransfer.selector ||
            sel == IParametricToken.parametricTransferFrom.selector ||
            sel == IPredictionToken.mint.selector ||
            sel == IPredictionToken.burn.selector ||
            sel == IPredictionToken.prediction.selector ||
            sel == IPredictionToken.round.selector ||
            sel == IPredictionToken.engine.selector ||
            sel == IPredictionToken.maxRounds.selector ||
            sel == IPredictionToken.setEngine.selector ||
            sel == IPredictionToken.setMaxRounds.selector
        ) {
            target = LOGIC_PREDICTION_TOKEN;
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
        return
            interfaceId == type(IParametricToken).interfaceId ||
            interfaceId == type(IParametricPermissions).interfaceId;
    }
}
