// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IBundleToken.sol";
import "../libraries/Lib.sol";
import "../base/BaseParametricToken.sol";

contract BundleToken is BaseParametricToken, IBundleToken {
    // ====== CONSTANTS ======

    uint8 public constant NUMBER_OF_PARAMETERS = 1;
    bytes4 public constant INTERFACE_ID_NZS = bytes4(
        keccak256(
            "ParametricTransferNzs(address,uint48,address,uint48,uint256,uint256,uint64[],uint64[])"
        )
    );

    // ====== STRUCTS ======

    struct ParamConfig {
        bytes32 name;
        uint8 decimals;
        bool isMutable;
    }

    // ====== STATE ======

    mapping(address => uint64[NUMBER_OF_PARAMETERS]) private _normalParams;
    mapping(address => mapping(uint48 => uint64[NUMBER_OF_PARAMETERS]))
        private _subParams;
    ParamConfig[NUMBER_OF_PARAMETERS] private _paramConfig;

    // ====== CONSTRUCTOR ======

    constructor(
        string memory name_,
        string memory symbol_
    ) BaseParametricToken(name_, symbol_) {
        _paramConfig[0] = ParamConfig({
            name: "anchor",
            decimals: 8,
            isMutable: true
        });
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(BaseParametricToken) returns (bool) {
        return
            interfaceId == INTERFACE_ID_NZS ||
            super.supportsInterface(interfaceId);
    }

    // ====== MINT & BURN ======

    function mint(
        address to,
        uint256 amount,
        uint64 anchor_
    ) external onlyEngine {
        require(to != address(0), "Mint to zero");
        require(amount > 0, "Void amount");
        require(anchor_ > 0, "Zero anchor");

        bytes memory mintData = abi.encode(anchor_);
        _mintInternal(to, amount, mintData);
    }

    function burn(
        address from,
        uint48 subId,
        uint256 amount
    ) external onlyEngine onlyValidSub(from, subId) {
        _burnInternal(from, subId, amount);
    }

    // ====== VIRTUAL HOOK IMPLEMENTATIONS ======

    function _getParams(
        address account,
        uint48 subId
    ) internal view override returns (uint64[] memory) {
        uint64[] memory params = new uint64[](NUMBER_OF_PARAMETERS);
        if (_accounts[account].accountType == AccountType.Super) {
            params[0] = _subParams[account][subId][0];
        } else {
            params[0] = _normalParams[account][0];
        }
        return params;
    }

    function _decodeMintDataToArray(
        bytes memory mintData
    ) internal pure override returns (uint64[] memory) {
        (uint64 decodedAnchor) = abi.decode(mintData, (uint64));
        uint64[] memory params = new uint64[](1);
        params[0] = decodedAnchor;
        return params;
    }

    function _updateTransferParametersAndComputeCredit(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    ) internal override returns (uint256 creditAmount) {
        (uint64 fromAnchor, uint256 fromBal) = _getAnchorAndBalance(
            from,
            fromSubId
        );
        (uint64 toAnchor, uint256 toBal) = _getAnchorAndBalance(to, toSubId);

        uint64 newAnchor;
        uint256 newToBalance;

        if (toBal == 0) {
            // Empty destination: copy anchor, credit amount equals debit amount
            newAnchor = fromAnchor;
            newToBalance = amount;
            creditAmount = amount;
        } else {
            // Combine using Lib.combine
            (newAnchor, newToBalance) = Lib.combine(
                fromAnchor,
                amount,
                toAnchor,
                toBal
            );
            creditAmount = newToBalance - toBal; // NZS: amount added may differ from amount
        }

        _setAnchor(to, toSubId, newAnchor);

        if (fromBal == amount) {
            _setAnchor(from, fromSubId, 0);
        }

        // Store computed credit amount for balance update in base
        return creditAmount;
    }

    function _applyMintParametersAndComputeCredit(
        address to,
        uint256 amount,
        bytes memory mintData
    ) internal override returns (uint256 creditAmount) {
        uint64 anchor_ = abi.decode(mintData, (uint64));

        (uint64 currentAnchor, uint256 currentBal) = _getAnchorAndBalance(
            to,
            0
        );

        uint64 newAnchor;
        uint256 newBalance;

        if (currentBal == 0) {
            newAnchor = anchor_;
            newBalance = amount;
            creditAmount = amount;
        } else {
            (newAnchor, newBalance) = Lib.combine(
                anchor_,
                amount,
                currentAnchor,
                currentBal
            );
            creditAmount = newBalance - currentBal;
        }

        _setAnchor(to, 0, newAnchor);

        return creditAmount;
    }

    function _applyBurnParameters(
        address from,
        uint48 fromSubId,
        uint256 amount
    ) internal override {
        uint256 currentBalance = _getBalance(from, fromSubId);
        if (currentBalance == amount) {
            _setAnchor(from, fromSubId, 0);
        }
    }

    function _resetAccountParameters(address account) internal override {
        _normalParams[account][0] = 0;
    }

    function _resetSubAccountParameters(
        address account,
        uint48 subId
    ) internal override {
        _subParams[account][subId][0] = 0;
    }

    function _emitParametricTransferEvent(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 debitAmount,
        uint256 creditAmount,
        uint64[] memory incomingParams,
        uint64[] memory resultingParams,
        bool /* isSelfTransfer */
    ) internal override {
        emit ParametricTransferNzs(
            from,
            fromSubId,
            to,
            toSubId,
            debitAmount,
            creditAmount,
            incomingParams,
            resultingParams
        );
    }

    // ====== INTERNAL HELPERS ======

    function _getAnchorAndBalance(
        address account,
        uint48 subId
    ) private view returns (uint64 accAnchor, uint256 accBalance) {
        if (_accounts[account].accountType == AccountType.Super) {
            accAnchor = _subParams[account][subId][0];
            accBalance = _supers[account].subs[subId].balance;
        } else {
            accAnchor = _normalParams[account][0];
            accBalance = _accounts[account].balance;
        }
    }

    function _setAnchor(address account, uint48 subId, uint64 value) private {
        if (_accounts[account].accountType == AccountType.Super) {
            _subParams[account][subId][0] = value;
        } else {
            _normalParams[account][0] = value;
        }
    }

    function _getBalance(
        address account,
        uint48 subId
    ) private view returns (uint256) {
        if (_accounts[account].accountType == AccountType.Super) {
            return _supers[account].subs[subId].balance;
        } else {
            return _accounts[account].balance;
        }
    }

    // ====== VIEW FUNCTIONS ======

    function paramConfig(
        uint8 index
    ) external view returns (bytes32, uint8, bool) {
        return (
            _paramConfig[index].name,
            _paramConfig[index].decimals,
            _paramConfig[index].isMutable
        );
    }

    function parameterOf(
        uint8 paramIndex,
        address account,
        uint48 subId
    ) public view onlyValidSub(account, subId) returns (uint64) {
        require(paramIndex < NUMBER_OF_PARAMETERS, "Invalid param index");
        if (_accounts[account].accountType == AccountType.Super) {
            return _subParams[account][subId][paramIndex];
        } else {
            return _normalParams[account][paramIndex];
        }
    }

    function allParametersOf(
        address account,
        uint48 subId
    ) public view onlyValidSub(account, subId) returns (uint64[] memory) {
        uint64[] memory params = new uint64[](NUMBER_OF_PARAMETERS);
        if (_accounts[account].accountType == AccountType.Super) {
            params[0] = _subParams[account][subId][0];
        } else {
            params[0] = _normalParams[account][0];
        }
        return params;
    }

    function anchor(
        address account,
        uint48 subId
    ) public view onlyValidSub(account, subId) returns (uint64) {
        return parameterOf(0, account, subId);
    }
}
