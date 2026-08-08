// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../base/BaseParametricToken.sol";
import "../interfaces/IPredictionToken.sol";
import "../interfaces/IPredictionEngine.sol";
import "../libraries/Lib.sol";

contract PredictionToken is BaseParametricToken, IPredictionToken {
    // ====== CONSTANTS ======

    uint8 public constant NUMBER_OF_PARAMETERS = 2; // prediction (mutable), round (immutable)

    // ====== STRUCTS ======

    struct ParamConfig {
        bytes32 name;
        uint8 decimals;
        bool isMutable;
    }

    // ====== STATE ======

    uint64 private _maxRounds;

    // Parameter storage: separate from base's AccountBase
    mapping(address => uint64[NUMBER_OF_PARAMETERS]) private _normalParams;
    mapping(address => mapping(uint48 => uint64[NUMBER_OF_PARAMETERS]))
        private _subParams;

    ParamConfig[NUMBER_OF_PARAMETERS] private _paramConfig;

    // ====== MODIFIERS ======

    modifier onlyActiveRound(uint64 round_) {
        require(
            IPredictionEngine(_engine).roundStatus(round_) ==
                IPredictionEngine.Status.Active,
            "Round not active"
        );
        _;
    }

    // ====== CONSTRUCTOR ======

    constructor(
        string memory name_,
        string memory symbol_
    ) BaseParametricToken(name_, symbol_) {
        _paramConfig[0] = ParamConfig({
            name: "prediction",
            decimals: 8,
            isMutable: true
        });
        _paramConfig[1] = ParamConfig({
            name: "round",
            decimals: 0,
            isMutable: false
        });
    }

    // ====== CONTRACT MANAGEMENT ======

    function setMaxRounds(uint64 maxRounds_) external onlyEngine {
        _maxRounds = maxRounds_;
    }

    // ====== MINT & BURN (external) ======

    function mint(
        address to,
        uint256 amount,
        uint64 predictionPrice,
        uint64 round_
    ) external onlyActiveRound(round_) {
        require(to != address(0), "Mint to zero");
        require(amount > 0, "Void amount");
        require(predictionPrice > 0, "Zero prediction");
        require(round_ < _maxRounds, "Round out of range");

        bytes memory mintData = abi.encode(predictionPrice, round_);
        _mintInternal(to, amount, mintData);
    }

    function burn(
        address from,
        uint48 subId,
        uint256 amount
    ) external onlyEngine onlyValidSub(from, subId) {
        _burnInternal(from, subId, amount);
    }

    // ====== INTERNAL HOOKS ======

    function _copyAccountParametersToSub(
        address account,
        uint48 subId
    ) internal override {
        _subParams[account][subId][0] = _normalParams[account][0];
        _subParams[account][subId][1] = _normalParams[account][1];
    }

    function _getParams(
        address account,
        uint48 subId
    ) internal view override returns (uint64[] memory) {
        uint64[] memory params = new uint64[](NUMBER_OF_PARAMETERS);
        if (_accounts[account].accountType == AccountType.Super) {
            params[0] = _subParams[account][subId][0];
            params[1] = _subParams[account][subId][1];
        } else {
            params[0] = _normalParams[account][0];
            params[1] = _normalParams[account][1];
        }
        return params;
    }

    function _decodeMintDataToArray(
        bytes memory mintData
    ) internal pure override returns (uint64[] memory) {
        (uint64 decodedPrediction, uint64 decodedRound) = abi.decode(
            mintData,
            (uint64, uint64)
        );
        uint64[] memory params = new uint64[](2);
        params[0] = decodedPrediction;
        params[1] = decodedRound;
        return params;
    }

    function _updateTransferParametersAndComputeCredit(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    ) internal override returns (uint256 creditAmount) {
        // 1. Check immutable round conflict
        _requireNoRoundConflict(from, fromSubId, to, toSubId);

        // 2. Get pre‑execution state
        (uint64 fromPrediction, uint256 fromBalance) = _getPredictionAndBalance(
            from,
            fromSubId
        );
        (uint64 toPrediction, uint256 toBalance) = _getPredictionAndBalance(
            to,
            toSubId
        );

        // 3. Compute new prediction for recipient
        uint64 newToPrediction;
        if (toBalance == 0) {
            newToPrediction = fromPrediction;
        } else {
            newToPrediction = Lib.weightedAverage(
                fromPrediction,
                amount,
                toPrediction,
                toBalance
            );
        }

        // 4. Store updated prediction in recipient
        _setPrediction(to, toSubId, newToPrediction);

        // 5. Reset sender prediction if balance becomes zero
        if (fromBalance == amount) {
            _setPrediction(from, fromSubId, 0);
        }

        // For PredictionToken, creditAmount equals amount (zero-sum)
        return amount;
    }

    function _applyMintParametersAndComputeCredit(
        address to,
        uint256 amount,
        bytes memory mintData
    ) internal override returns (uint256 creditAmount) {
        (uint64 inputPrediction, uint64 inputRound) = abi.decode(
            mintData,
            (uint64, uint64)
        );

        (
            uint64 currentPrediction,
            uint256 currentBalance
        ) = _getPredictionAndBalance(to, 0);

        // Immutable round check
        uint64 currentRound = _getRound(to, 0);
        if (currentBalance > 0) {
            require(currentRound == inputRound, "Round mismatch");
        }

        // Compute new prediction
        uint64 newPrediction;
        if (currentBalance == 0) {
            newPrediction = inputPrediction;
        } else {
            newPrediction = Lib.weightedAverage(
                inputPrediction,
                amount,
                currentPrediction,
                currentBalance
            );
        }

        // Set both parameters
        _setPrediction(to, 0, newPrediction);
        _setRound(to, 0, inputRound);

        return amount; // zero-sum
    }

    function _applyBurnParameters(
        address from,
        uint48 subId,
        uint256 amount
    ) internal override {
        // If balance becomes zero, reset all parameters
        uint256 currentBalance = _getBalance(from, subId);
        if (currentBalance == amount) {
            _setPrediction(from, subId, 0);
            _setRound(from, subId, 0);
        }
    }

    function _resetAccountParameters(address account) internal override {
        _normalParams[account][0] = 0;
        _normalParams[account][1] = 0;
    }

    function _resetSubAccountParameters(
        address account,
        uint48 subId
    ) internal override {
        _subParams[account][subId][0] = 0;
        _subParams[account][subId][1] = 0;
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
        // For Prediction, debitAmount == creditAmount
        emit ParametricTransfer(
            from,
            fromSubId,
            to,
            toSubId,
            creditAmount,
            resultingParams
        );
    }

    // ====== HELPER FUNCTIONS (parameter access) ======

    function _getPredictionAndBalance(
        address account,
        uint48 subId
    ) private view returns (uint64 predictionPrice, uint256 balance) {
        if (_accounts[account].accountType == AccountType.Super) {
            predictionPrice = _subParams[account][subId][0];
            balance = _supers[account].subs[subId].balance;
        } else {
            predictionPrice = _normalParams[account][0];
            balance = _accounts[account].balance;
        }
    }

    function _getRound(
        address account,
        uint48 subId
    ) private view returns (uint64) {
        if (_accounts[account].accountType == AccountType.Super) {
            return _subParams[account][subId][1];
        } else {
            return _normalParams[account][1];
        }
    }

    function _setPrediction(
        address account,
        uint48 subId,
        uint64 value
    ) private {
        if (_accounts[account].accountType == AccountType.Super) {
            _subParams[account][subId][0] = value;
        } else {
            _normalParams[account][0] = value;
        }
    }

    function _setRound(address account, uint48 subId, uint64 value) private {
        if (_accounts[account].accountType == AccountType.Super) {
            _subParams[account][subId][1] = value;
        } else {
            _normalParams[account][1] = value;
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

    function _requireNoRoundConflict(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId
    ) private view {
        // If recipient balance is zero, no conflict
        uint256 toBalance = _getBalance(to, toSubId);
        if (toBalance == 0) return;

        uint64 fromRound = _getRound(from, fromSubId);
        uint64 toRound = _getRound(to, toSubId);
        require(fromRound == toRound, "Immutable round conflict");
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
            params[1] = _subParams[account][subId][1];
        } else {
            params[0] = _normalParams[account][0];
            params[1] = _normalParams[account][1];
        }
        return params;
    }

    function prediction(
        address account,
        uint48 subId
    ) public view onlyValidSub(account, subId) returns (uint64) {
        return parameterOf(0, account, subId);
    }

    function round(
        address account,
        uint48 subId
    ) public view onlyValidSub(account, subId) returns (uint64) {
        return parameterOf(1, account, subId);
    }

    function maxRounds() external view returns (uint64) {
        return _maxRounds;
    }
}
