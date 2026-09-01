// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/spec/IParametricToken.sol";
import "../interfaces/IPredictionToken.sol";
import "../interfaces/IPredictionEngine.sol";
import "../libraries/Lib.sol";
import "./Storage.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract Prediction is Storage {
    // ====== MODIFIERS ======

    modifier onlyEngine() {
        AppStorage storage s = _s();
        require(msg.sender == s.engine, "Not engine");
        _;
    }

    modifier onlyRouterOwner() {
        require(msg.sender == IOwnable(address(this)).owner(), "Not owner");
        _;
    }

    modifier onlyValidSub(address account, uint48 subId) {
        AppStorage storage s = _s();
        if (subId > 0) {
            require(
                s.accounts[account].accountType == AccountType.Super,
                "Not super account"
            );
            require(
                subId < s.supers[account].subsCount,
                "Sub-account doesn't exist"
            );
        }
        _;
    }

    modifier onlyActiveRound(uint64 round_) {
        AppStorage storage s = _s();
        require(
            IPredictionEngine(s.engine).roundStatus(round_) ==
                IPredictionEngine.Status.Active,
            "Round not active"
        );
        _;
    }

    // ====== PARAMS QUERIES ======

    function paramConfig()
        external
        view
        returns (IParametricToken.ParamConfig[] memory)
    {
        return _s().paramConfig;
    }

    // ====== PREDICTION-SPECIFIC FUNCTIONS ======

    function mint(
        address to,
        uint256 amount,
        uint64 inputPrediction,
        uint64 inputRound
    ) external onlyActiveRound(inputRound) {
        require(to != address(0), "Mint to zero");
        require(amount > 0, "Void amount");
        require(inputPrediction > 0, "Zero prediction");

        AppStorage storage s = _s();
        require(inputRound < s.maxRounds, "Round out of range");

        bytes memory mintData = abi.encode(inputPrediction, inputRound);
        _mintInternal(to, amount, mintData);
    }

    function burn(
        address from,
        uint48 subId,
        uint256 amount
    ) external onlyEngine onlyValidSub(from, subId) {
        _burnInternal(from, subId, amount);
    }

    // ====== TRANSFER FUNCTIONS ======

    function transfer(address to, uint256 amount) external returns (bool) {
        return _parametricTransfer(msg.sender, 0, to, 0, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        return _parametricTransfer(from, 0, to, 0, amount);
    }

    function parametricTransfer(
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    )
        external
        onlyValidSub(msg.sender, fromSubId)
        onlyValidSub(to, toSubId)
        returns (bool)
    {
        return _parametricTransfer(msg.sender, fromSubId, to, toSubId, amount);
    }

    function parametricTransferFrom(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    )
        external
        onlyValidSub(from, fromSubId)
        onlyValidSub(to, toSubId)
        returns (bool)
    {
        address spender = msg.sender;
        require(
            _sufficientAllowanceForSub(from, spender, fromSubId, amount),
            "Insufficient allowance"
        );
        _spendParametricAllowance(from, spender, fromSubId, amount);
        return _parametricTransfer(from, fromSubId, to, toSubId, amount);
    }

    // ====== INTERNAL TRANSFER LOGIC ======

    function _mintInternal(
        address to,
        uint256 amount,
        bytes memory mintData
    ) internal {
        require(to != address(0), "Mint to zero");
        require(amount > 0, "Void amount");

        AppStorage storage s = _s();

        uint64[] memory mintParams = _decodeMintDataToArray(mintData);
        _checkPermissions(address(0), to, 0, mintParams);

        // Delegate parameter computation, returns creditAmount (amount added)
        uint256 creditAmount = _applyMintParametersAndComputeCredit(
            to,
            amount,
            mintData
        );

        // Update balance
        if (s.accounts[to].accountType == AccountType.Super) {
            s.supers[to].subs[0].balance += creditAmount;
        }
        s.accounts[to].balance += creditAmount;
        s.totalSupply += creditAmount;

        uint64[] memory resultingParams = _getParams(to, 0);

        _emitParametricTransferEvent(
            address(0),
            0,
            to,
            0,
            amount,
            creditAmount,
            mintParams,
            resultingParams,
            false
        );
        emit IERC20.Transfer(address(0), to, creditAmount);
    }

    function _burnInternal(
        address from,
        uint48 fromSubId,
        uint256 amount
    ) internal {
        require(from != address(0), "Burn from zero");
        require(amount > 0, "Void amount");

        AppStorage storage s = _s();

        // Capture pre-debit params
        uint64[] memory initialParams = _getParams(from, fromSubId);

        // Delegate parameter updates (resets if balance becomes zero)
        _applyBurnParameters(from, fromSubId, amount);

        // Deduct from sender
        if (s.accounts[from].accountType == AccountType.Super) {
            SuperAccount storage superAcc = s.supers[from];
            uint256 fromSubBalance = superAcc.subs[fromSubId].balance;
            require(fromSubBalance >= amount, "Insufficient balance");
            superAcc.subs[fromSubId].balance -= amount;
        } else {
            require(s.accounts[from].balance >= amount, "Insufficient balance");
        }
        s.accounts[from].balance -= amount;
        s.totalSupply -= amount;

        // Capture post-credit receiver params
        uint64[] memory resultingParams = _getParams(from, fromSubId);

        _emitParametricTransferEvent(
            from,
            fromSubId,
            address(0),
            0,
            amount,
            0,
            initialParams,
            resultingParams,
            false
        );
        emit IERC20.Transfer(from, address(0), amount);
    }

    function _parametricTransfer(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    ) internal returns (bool) {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");
        require(amount > 0, "Void amount");

        AppStorage storage s = _s();

        uint64[] memory incomingParams = _getParams(from, fromSubId);

        // Self-transfer short‑circuit
        if (from == to && fromSubId == toSubId) {
            _emitParametricTransferEvent(
                from,
                fromSubId,
                to,
                toSubId,
                amount,
                amount,
                incomingParams,
                incomingParams,
                true
            );
            emit IERC20.Transfer(from, to, amount);
            return true;
        }

        // Pre‑transfer hook (permissions)
        _beforeParametricTransfer(
            from,
            fromSubId,
            to,
            toSubId,
            amount,
            incomingParams
        );

        // Update parameters and compute credit
        uint256 creditAmount = _updateTransferParametersAndComputeCredit(
            from,
            fromSubId,
            to,
            toSubId,
            amount
        );

        // Deduct from sender
        if (s.accounts[from].accountType == AccountType.Super) {
            uint256 subBalance = s.supers[from].subs[fromSubId].balance;
            require(subBalance >= amount, "Insufficient balance");
            s.supers[from].subs[fromSubId].balance = subBalance - amount;
        } else {
            require(s.accounts[from].balance >= amount, "Insufficient balance");
        }
        s.accounts[from].balance -= amount;
        s.totalSupply -= amount;

        // Add to receiver
        if (s.accounts[to].accountType == AccountType.Super) {
            s.supers[to].subs[toSubId].balance += creditAmount;
        }
        s.accounts[to].balance += creditAmount;
        s.totalSupply += creditAmount;

        uint64[] memory resultingParams = _getParams(to, toSubId);

        _emitParametricTransferEvent(
            from,
            fromSubId,
            to,
            toSubId,
            amount,
            creditAmount,
            incomingParams,
            resultingParams,
            false
        );
        emit IERC20.Transfer(from, to, creditAmount);

        return true;
    }

    // ====== ALLOWANCE SPENDING HELPERS ======

    function _sufficientAllowanceForSub(
        address owner,
        address spender,
        uint48 fromSubId,
        uint256 amount
    ) private view returns (bool) {
        Allowance storage al = _s().allowances[owner][spender];
        if (fromSubId == al.subId && fromSubId > 0) {
            return al.sub >= amount;
        } else {
            return al.total - al.sub >= amount;
        }
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 value
    ) private {
        AppStorage storage s = _s();
        if (s.accounts[owner].accountType == AccountType.Super) {
            _spendParametricAllowance(owner, spender, 0, value);
        } else {
            uint256 current = s.allowances[owner][spender].total;
            if (current != type(uint256).max) {
                require(current >= value, "Insufficient general allowance");
                s.allowances[owner][spender].total = current - value;
            }
        }
    }

    function _spendParametricAllowance(
        address owner,
        address spender,
        uint48 fromSubId,
        uint256 amount
    ) private {
        AppStorage storage s = _s();
        Allowance storage al = s.allowances[owner][spender];
        if (al.committedUntil < block.timestamp) al.committedUntil = 0;

        if (fromSubId == al.subId && fromSubId > 0) {
            require(al.sub >= amount, "Insufficient sub-allowance");
            uint256 spend = al.oneOff ? al.sub : amount;
            al.sub -= spend;
            al.total -= spend;
            if (al.oneOff) {
                al.oneOff = false;
                al.committedUntil = 0;
            }
        } else {
            uint256 general = al.total - al.sub;
            require(general >= amount, "Insufficient general allowance");
            al.total -= amount;
        }
    }

    // ====== PARAMETER UPDATE HELPERS ======

    function _beforeParametricTransfer(
        address from,
        uint48,
        address to,
        uint48 toSubId,
        uint256,
        uint64[] memory incomingParams
    ) internal virtual {
        // Permissions check
        _checkPermissions(from, to, toSubId, incomingParams);
    }

    function _decodeMintDataToArray(
        bytes memory mintData
    ) internal pure returns (uint64[] memory) {
        (uint64 inputPrediction, uint64 inputRound) = abi.decode(
            mintData,
            (uint64, uint64)
        );
        uint64[] memory params = new uint64[](2);
        params[0] = inputPrediction;
        params[1] = inputRound;
        return params;
    }

    function _updateTransferParametersAndComputeCredit(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    ) internal returns (uint256 creditAmount) {
        (
            uint64 fromPrediction,
            uint64 fromRound,
            uint256 fromBalance
        ) = _getPredictionAndRoundAndBalance(from, fromSubId);
        (
            uint64 toPrediction,
            uint64 toRound,
            uint256 toBalance
        ) = _getPredictionAndRoundAndBalance(to, toSubId);

        // Immutable round conflict check
        if (toBalance > 0)
            require(fromRound == toRound, "Immutable round conflict");

        uint64 newToPrediction;
        if (toBalance == 0) {
            newToPrediction = fromPrediction;
            _setRound(to, toSubId, fromRound);
        } else {
            newToPrediction = Lib.weightedAverage(
                fromPrediction,
                amount,
                toPrediction,
                toBalance
            );
        }

        _setPrediction(to, toSubId, newToPrediction);

        if (fromBalance == amount) {
            _setPrediction(from, fromSubId, 0);
            _setRound(from, fromSubId, 0);
        }

        return amount; // zero‑sum for predictions
    }

    function _applyMintParametersAndComputeCredit(
        address to,
        uint256 amount,
        bytes memory mintData
    ) internal returns (uint256 creditAmount) {
        (uint64 inputPrediction, uint64 inputRound) = abi.decode(
            mintData,
            (uint64, uint64)
        );

        // Get current state (sub‑account 0)
        (
            uint64 currentPrediction,
            uint64 currentRound,
            uint256 currentBalance
        ) = _getPredictionAndRoundAndBalance(to, 0);

        // Immutable round check
        if (currentBalance > 0) {
            require(currentRound == inputRound, "Round mismatch");
        }

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

        _setPrediction(to, 0, newPrediction);
        _setRound(to, 0, inputRound);

        return amount; // zero‑sum for predictions
    }

    function _applyBurnParameters(
        address from,
        uint48 subId,
        uint256 amount
    ) internal {
        uint256 currentBalance = _getBalance(from, subId);
        if (currentBalance == amount) {
            _setPrediction(from, subId, 0);
            _setRound(from, subId, 0);
        }
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
    ) internal {
        emit IParametricToken.ParametricTransfer(
            from,
            fromSubId,
            to,
            toSubId,
            creditAmount,
            resultingParams
        );
    }

    // ====== PERMISSION CHECK ======

    function _checkPermissions(
        address from,
        address to,
        uint48 toSubId,
        uint64[] memory incomingParams
    ) private view {
        require(
            incomingParams.length == NUMBER_OF_PARAMS,
            "Param count mismatch"
        );
        AppStorage storage s = _s();
        for (uint8 i = 0; i < NUMBER_OF_PARAMS; i++) {
            if (!s.paramConfig[i].isMutable) continue;

            IParametricPermissions.Permission storage p = s.permissions[to][
                toSubId
            ][i];

            if (!p.enabled) continue;
            if (p.soft && from == to) continue;

            require(
                incomingParams[i] >= p.min && incomingParams[i] <= p.max,
                "Permission violation"
            );
        }
    }

    // ====== PARAMETER GET/SET HELPERS ======

    function _getBalance(
        address account,
        uint48 subId
    ) private view returns (uint256) {
        AppStorage storage s = _s();
        if (s.accounts[account].accountType == AccountType.Super) {
            return s.supers[account].subs[subId].balance;
        } else {
            return s.accounts[account].balance;
        }
    }

    function _getPredictionAndRoundAndBalance(
        address account,
        uint48 subId
    )
        private
        view
        returns (
            uint64 currentPrediction,
            uint64 currentRound,
            uint256 currentBalance
        )
    {
        AppStorage storage s = _s();
        if (s.accounts[account].accountType == AccountType.Super) {
            currentPrediction = s.supers[account].subs[subId].parameters[0];
            currentRound = s.supers[account].subs[subId].parameters[1];
            currentBalance = s.supers[account].subs[subId].balance;
        } else {
            currentPrediction = s.accounts[account].parameters[0];
            currentRound = s.accounts[account].parameters[1];
            currentBalance = s.accounts[account].balance;
        }
    }

    function _getParams(
        address account,
        uint48 subId
    ) internal view returns (uint64[] memory) {
        uint64[] memory params = new uint64[](NUMBER_OF_PARAMS);
        AppStorage storage s = _s();
        for (uint8 i = 0; i < NUMBER_OF_PARAMS; i++) {
            if (s.accounts[account].accountType == AccountType.Super) {
                params[i] = s.supers[account].subs[subId].parameters[i];
            } else {
                params[i] = s.accounts[account].parameters[i];
            }
        }

        return params;
    }

    function _getRound(
        address account,
        uint48 subId
    ) private view returns (uint64) {
        AppStorage storage s = _s();
        if (s.accounts[account].accountType == AccountType.Super) {
            return s.supers[account].subs[subId].parameters[1];
        } else {
            return s.accounts[account].parameters[1];
        }
    }

    function _setPrediction(
        address account,
        uint48 subId,
        uint64 value
    ) private {
        AppStorage storage s = _s();
        if (s.accounts[account].accountType == AccountType.Super) {
            s.supers[account].subs[subId].parameters[0] = value;
        } else {
            s.accounts[account].parameters[0] = value;
        }
    }

    function _setRound(address account, uint48 subId, uint64 value) private {
        AppStorage storage s = _s();
        if (s.accounts[account].accountType == AccountType.Super) {
            s.supers[account].subs[subId].parameters[1] = value;
        } else {
            s.accounts[account].parameters[1] = value;
        }
    }

    // ====== PREDICTION-SPECIFIC GETTERS/SETTERS ======

    function setEngine(address engine_) external onlyRouterOwner {
        require(engine_ != address(0), "Zero engine address");
        AppStorage storage s = _s();
        s.engine = engine_;
    }

    function setMaxRounds(uint64 maxRounds_) external {
        AppStorage storage s = _s();
        require(
            msg.sender == s.engine ||
                msg.sender == IOwnable(address(this)).owner(),
            "Not owner or engine"
        );
        s.maxRounds = maxRounds_;
    }

    function prediction(
        address account,
        uint48 subId
    ) external view onlyValidSub(account, subId) returns (uint64) {
        return IParametricToken(address(this)).parameterOf(account, subId, 0);
    }

    function round(
        address account,
        uint48 subId
    ) external view onlyValidSub(account, subId) returns (uint64) {
        return IParametricToken(address(this)).parameterOf(account, subId, 1);
    }

    function engine() external view returns (address) {
        return _s().engine;
    }

    function maxRounds() external view returns (uint64) {
        return _s().maxRounds;
    }
}
