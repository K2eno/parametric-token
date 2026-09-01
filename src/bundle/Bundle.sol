// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/spec/IParametricToken.sol";
import "../interfaces/spec/IParametricTokenNzs.sol";
import "../interfaces/IBundleToken.sol";
import "../libraries/Lib.sol";
import "./Storage.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract Bundle is Storage {
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

    // ====== PARAMS QUERIES ======

    function paramConfig()
        external
        view
        returns (IParametricToken.ParamConfig[] memory)
    {
        return _s().paramConfig;
    }

    // ====== BUNDLE-SPECIFIC FUNCTIONS ======

    function mint(
        address to,
        uint256 amount,
        uint64 inputAnchor
    ) external onlyEngine {
        require(to != address(0), "Mint to zero");
        require(amount > 0, "Void amount");
        require(inputAnchor > 0, "Zero anchor");
        bytes memory mintData = abi.encode(inputAnchor);
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

        uint256 oldBalance = _getBalance(to, 0);

        // Delegate parameter computation, returns newBalance
        uint256 newBalance = _applyMintParametersAndComputeNewBalance(
            to,
            amount,
            mintData
        );

        // Update balance for receiver
        if (s.accounts[to].accountType == AccountType.Super) {
            s.supers[to].subs[0].balance = newBalance;
        }
        s.accounts[to].balance += newBalance;
        s.accounts[to].balance -= oldBalance;
        s.totalSupply += newBalance;
        s.totalSupply -= oldBalance;

        uint64[] memory mintParams = _decodeMintDataToArray(mintData);
        uint64[] memory resultingParams = _getParams(to, 0);
        uint256 nonNegativeCreditAmount =
            newBalance > oldBalance ? newBalance - oldBalance : 0;

        _emitParametricTransferEvent(
            address(0),
            0,
            to,
            0,
            amount,
            int(newBalance) - int(oldBalance),
            mintParams,
            resultingParams,
            false
        );
        emit IERC20.Transfer(address(0), to, nonNegativeCreditAmount);
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
                int(amount),
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

        uint256 oldBalance = _getBalance(to, toSubId);

        // Update parameters and compute new balance
        uint256 newBalance = _updateTransferParametersAndComputeNewBalance(
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

        // Update balance for receiver
        if (s.accounts[to].accountType == AccountType.Super) {
            s.supers[to].subs[toSubId].balance = newBalance;
        }
        s.accounts[to].balance += newBalance;
        s.accounts[to].balance -= oldBalance;
        s.totalSupply += newBalance;
        s.totalSupply -= oldBalance;

        uint64[] memory resultingParams = _getParams(to, toSubId);
        uint256 nonNegativeCreditAmount =
            newBalance > oldBalance ? newBalance - oldBalance : 0;

        _emitParametricTransferEvent(
            from,
            fromSubId,
            to,
            toSubId,
            amount,
            int(newBalance) - int(oldBalance),
            incomingParams,
            resultingParams,
            false
        );
        emit IERC20.Transfer(from, to, nonNegativeCreditAmount);

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
    ) internal virtual {}

    function _decodeMintDataToArray(
        bytes memory mintData
    ) internal pure returns (uint64[] memory) {
        (uint64 inputAnchor) = abi.decode(mintData, (uint64));
        uint64[] memory params = new uint64[](1);
        params[0] = inputAnchor;
        return params;
    }

    function _updateTransferParametersAndComputeNewBalance(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    ) internal returns (uint256) {
        (uint64 fromAnchor, uint256 fromBalance) = _getAnchorAndBalance(
            from,
            fromSubId
        );
        (uint64 toAnchor, uint256 toBalance) = _getAnchorAndBalance(
            to,
            toSubId
        );

        (uint64 newAnchor, uint256 newBalance) = Lib.combine(
            fromAnchor,
            amount,
            toAnchor,
            toBalance
        );

        _setAnchor(to, toSubId, newAnchor);

        if (fromBalance == amount) {
            _setAnchor(from, fromSubId, 0);
        }

        return newBalance;
    }

    function _applyMintParametersAndComputeNewBalance(
        address to,
        uint256 amount,
        bytes memory mintData
    ) internal returns (uint256) {
        (uint64 inputAnchor) = abi.decode(mintData, (uint64));

        // Get current state (sub‑account 0)
        (uint64 currentAnchor, uint256 currentBalance) = _getAnchorAndBalance(
            to,
            0
        );

        (uint64 newAnchor, uint256 newBalance) = Lib.combine(
            inputAnchor,
            amount,
            currentAnchor,
            currentBalance
        );

        _setAnchor(to, 0, newAnchor);

        return newBalance;
    }

    function _applyBurnParameters(
        address from,
        uint48 subId,
        uint256 amount
    ) internal {
        uint256 currentBalance = _getBalance(from, subId);
        if (currentBalance == amount) {
            _setAnchor(from, subId, 0);
        }
    }

    function _emitParametricTransferEvent(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 debitAmount,
        int256 creditAmount,
        uint64[] memory incomingParams,
        uint64[] memory resultingParams,
        bool
    ) internal {
        emit IParametricTokenNzs.ParametricTransferNzs(
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

    function _getAnchorAndBalance(
        address account,
        uint48 subId
    ) private view returns (uint64 currentAnchor, uint256 currentBalance) {
        AppStorage storage s = _s();
        if (s.accounts[account].accountType == AccountType.Super) {
            currentAnchor = s.supers[account].subs[subId].parameters[0];
            currentBalance = s.supers[account].subs[subId].balance;
        } else {
            currentAnchor = s.accounts[account].parameters[0];
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

    function _setAnchor(address account, uint48 subId, uint64 value) private {
        AppStorage storage s = _s();
        if (s.accounts[account].accountType == AccountType.Super) {
            s.supers[account].subs[subId].parameters[0] = value;
        } else {
            s.accounts[account].parameters[0] = value;
        }
    }

    // ====== PREDICTION-SPECIFIC GETTERS/SETTERS ======

    function setEngine(address engine_) external onlyRouterOwner {
        require(engine_ != address(0), "Zero engine address");
        AppStorage storage s = _s();
        s.engine = engine_;
    }

    function isNonZeroSum() external pure returns (bool) {
        return true;
    }

    function anchor(
        address account,
        uint48 subId
    ) external view onlyValidSub(account, subId) returns (uint64) {
        return IParametricToken(address(this)).parameterOf(account, subId, 0);
    }

    function engine() external view returns (address) {
        return _s().engine;
    }
}
