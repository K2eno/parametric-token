// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/ITenureToken.sol";
import "../libraries/Lib.sol";
import "../base/BaseParametricToken.sol";

contract TenureToken is BaseParametricToken, ITenureToken {
    // ====== CONSTANTS ======

    uint8 public constant NUMBER_OF_PARAMETERS = 1;

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
            name: "mintTime",
            decimals: 0,
            isMutable: true
        });
    }

    // ====== MINT & BURN ======

    function mint(address to, uint256 amount) external onlyEngine {
        require(to != address(0), "Mint to zero");
        require(amount > 0, "Void amount");

        // Mint data: block.timestamp
        bytes memory mintData = abi.encode(uint64(block.timestamp));
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
        (uint64 decodedMintTime) = abi.decode(mintData, (uint64));
        uint64[] memory params = new uint64[](1);
        params[0] = decodedMintTime;
        return params;
    }

    function _updateTransferParametersAndComputeCredit(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    ) internal override returns (uint256 creditAmount) {
        (uint64 fromTime, uint256 fromBal) = _getMintTimeAndBalance(
            from,
            fromSubId
        );
        (uint64 toTime, uint256 toBal) = _getMintTimeAndBalance(to, toSubId);

        uint64 newTime;
        if (toBal == 0) {
            newTime = fromTime;
        } else {
            newTime = Lib.weightedAverage(fromTime, amount, toTime, toBal);
        }

        _setMintTime(to, toSubId, newTime);

        if (fromBal == amount) {
            _setMintTime(from, fromSubId, 0);
        }

        return amount;
    }

    function _applyMintParametersAndComputeCredit(
        address to,
        uint256 amount,
        bytes memory mintData
    ) internal override returns (uint256 creditAmount) {
        uint64 inputMintTime = abi.decode(mintData, (uint64));

        (uint64 toMintTime, uint256 toBal) = _getMintTimeAndBalance(to, 0);

        uint64 newTime;
        if (toBal == 0) {
            newTime = inputMintTime;
        } else {
            newTime = Lib.weightedAverage(
                inputMintTime,
                amount,
                toMintTime,
                toBal
            );
        }

        _setMintTime(to, 0, newTime);

        return amount;
    }

    function _applyBurnParameters(
        address from,
        uint48 subId,
        uint256 amount
    ) internal override {
        uint256 currentBalance = _getBalance(from, subId);
        if (currentBalance == amount) {
            _setMintTime(from, subId, 0);
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
        uint256,
        uint256 creditAmount,
        uint64[] memory,
        uint64[] memory resultingParams,
        bool
    ) internal override {
        emit ParametricTransfer(
            from,
            fromSubId,
            to,
            toSubId,
            creditAmount,
            resultingParams
        );
    }

    // ====== INTERNAL HELPERS ======

    function _getMintTimeAndBalance(
        address account,
        uint48 subId
    ) private view returns (uint64 accMintTime, uint256 accBalance) {
        if (_accounts[account].accountType == AccountType.Super) {
            accMintTime = _subParams[account][subId][0];
            accBalance = _supers[account].subs[subId].balance;
        } else {
            accMintTime = _normalParams[account][0];
            accBalance = _accounts[account].balance;
        }
    }

    function _setMintTime(address account, uint48 subId, uint64 value) private {
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

    function mintTime(
        address account,
        uint48 subId
    ) public view onlyValidSub(account, subId) returns (uint64) {
        return parameterOf(0, account, subId);
    }
}
