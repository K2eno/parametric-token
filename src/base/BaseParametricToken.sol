// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "../interfaces/IParametricToken.sol";

abstract contract BaseParametricToken is Ownable, IParametricToken {
    // ====== CONSTANTS ======

    bytes4 public constant INTERFACE_ID_PARAMETRIC = type(IParametricToken)
        .interfaceId;

    // ====== STRUCTS ======

    struct AccountBase {
        AccountType accountType;
        uint256 balance;
    }

    struct SubAccountBase {
        uint256 balance;
    }

    struct SuperAccountBase {
        SubAccountBase[] subs;
        uint48 subsCount;
    }

    struct Allowance {
        uint256 total;
        uint256 sub;
        uint48 subId;
        bool oneOff;
    }

    // ====== STATE ======

    string internal _name;
    string internal _symbol;
    uint256 internal _totalSupply;

    mapping(address => AccountBase) internal _accounts;
    mapping(address => SuperAccountBase) internal _supers;
    mapping(address => mapping(address => Allowance)) internal _allowances;

    address internal _engine;

    // ====== MODIFIERS ======

    modifier onlyEngine() {
        require(msg.sender == _engine, "Not engine");
        _;
    }

    modifier onlyNormal(address account) {
        require(
            _accounts[account].accountType == AccountType.Normal,
            "Not normal"
        );
        _;
    }

    modifier onlySuper(address account) {
        require(
            _accounts[account].accountType == AccountType.Super,
            "Not super"
        );
        _;
    }

    modifier onlyValidSub(address account, uint48 subId) {
        if (subId > 0) {
            require(
                _accounts[account].accountType == AccountType.Super,
                "Not a super account"
            );
            require(
                subId < _supers[account].subsCount,
                "Sub-account doesn't exist"
            );
        }
        _;
    }

    // ====== CONSTRUCTOR ======

    constructor(
        string memory name_,
        string memory symbol_
    ) Ownable(msg.sender) {
        _name = name_;
        _symbol = symbol_;
    }

    // ====== CONTRACT MANAGEMENT ======

    function setEngine(address engine_) external onlyOwner {
        require(engine_ != address(0), "Zero engine address");
        _engine = engine_;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual returns (bool) {
        return interfaceId == INTERFACE_ID_PARAMETRIC;
    }

    // ====== ERC-20 FUNCTIONS ======

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external pure virtual returns (uint8) {
        return 18;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _accounts[account].balance;
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowances[owner][spender].total;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        address owner = msg.sender;
        Allowance storage al = _allowances[owner][spender];
        al.total = amount;
        if (al.sub > amount) al.sub = amount;
        if (amount == 0) al.oneOff = false;
        emit Approval(owner, spender, amount);
        return true;
    }

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

    // ====== PARAMETRIC FUNCTIONS ======

    // Super account management
    function convertToSuper(
        address account
    ) external onlyNormal(account) returns (bool) {
        require(msg.sender == account, "Only owner can convert");
        AccountBase storage acc = _accounts[account];
        acc.accountType = AccountType.Super;

        _supers[account].subs.push(SubAccountBase({balance: acc.balance}));
        _supers[account].subsCount = 1;

        // Clear parameters (derived contract handles this via hook)
        _resetAccountParameters(account);

        emit AccountConvertedToSuper(account);
        emit SubAccountCreated(account, 0);
        return true;
    }

    function createSubAccount(
        address account
    ) external onlySuper(account) returns (uint48) {
        require(msg.sender == account, "Only owner can create");
        SuperAccountBase storage acc = _supers[account];
        acc.subs.push(SubAccountBase({balance: 0}));
        acc.subsCount = uint48(acc.subs.length);
        uint48 newSubId = acc.subsCount - 1;

        // Derived contract resets parameters for new sub-account via hook
        _resetSubAccountParameters(account, newSubId);
        emit SubAccountCreated(account, newSubId);
        return newSubId;
    }

    function accountType(address account) external view returns (AccountType) {
        return _accounts[account].accountType;
    }

    function subsCountOf(address account) external view returns (uint48) {
        if (_accounts[account].accountType == AccountType.Super) {
            return _supers[account].subsCount;
        }
        return 0;
    }

    // Parametric allowances
    function approveForSub(
        uint48 ownerSubId,
        address spender,
        uint256 amount,
        bool oneOff
    ) external returns (bool) {
        address owner = msg.sender;
        require(
            _accounts[owner].accountType == AccountType.Super,
            "Not super account"
        );
        require(
            ownerSubId < _supers[owner].subsCount,
            "Sub-account doesn't exist"
        );
        if (oneOff)
            require(amount > 0, "OneOff requires positive sub allowance");

        Allowance storage al = _allowances[owner][spender];
        al.subId = ownerSubId;
        al.oneOff = oneOff;
        uint256 general = al.total - al.sub;
        if (amount < al.sub) al.total = general + amount;
        al.sub = amount;
        if (amount > al.total) al.total = amount;

        emit ApprovalForSub(owner, ownerSubId, spender, amount, oneOff);
        return true;
    }

    function allowanceForSub(
        address owner,
        uint48 subId,
        address spender
    ) external view returns (uint256, bool) {
        Allowance storage al = _allowances[owner][spender];
        if (al.subId == subId) return (al.sub, al.oneOff);
        return (al.total - al.sub, false);
    }

    // Parametric transfers
    function parametricTransfer(
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    )
        public
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
        public
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

    function parametricBalanceOf(
        address account,
        uint48 subId
    ) external view onlyValidSub(account, subId) returns (uint256) {
        if (_accounts[account].accountType == AccountType.Normal)
            return _accounts[account].balance;
        return _supers[account].subs[subId].balance;
    }

    // ====== INTERNAL HELPERS (allowance) ======

    function _sufficientAllowanceForSub(
        address owner,
        address spender,
        uint48 fromSubId,
        uint256 amount
    ) private view returns (bool) {
        Allowance storage al = _allowances[owner][spender];
        if (fromSubId == al.subId) {
            return al.sub >= amount;
        } else {
            return al.total - al.sub >= amount;
        }
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 value
    ) internal {
        if (_accounts[owner].accountType == AccountType.Super) {
            _spendParametricAllowance(owner, spender, 0, value);
        } else {
            uint256 current = _allowances[owner][spender].total;
            if (current != type(uint256).max) {
                require(current >= value, "Insufficient allowance");
                _allowances[owner][spender].total = current - value;
            }
        }
    }

    function _spendParametricAllowance(
        address owner,
        address spender,
        uint48 fromSubId,
        uint256 amount
    ) private {
        Allowance storage al = _allowances[owner][spender];
        if (fromSubId == al.subId) {
            require(al.sub >= amount, "Insufficient sub-allowance");
            al.sub -= amount;
            al.total -= amount;
            if (al.oneOff) {
                uint256 remaining = al.sub;
                al.total -= remaining;
                al.sub = 0;
                al.oneOff = false;
            }
        } else {
            uint256 general = al.total - al.sub;
            require(general >= amount, "Insufficient allowance");
            al.total -= amount;
        }
    }

    // ====== CORE TRANSFER LOGIC ======

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

        // Self-transfer short-circuit
        if (from == to && fromSubId == toSubId) {
            // Emit events with current parameters (no change)
            _emitParametricTransferEvent(
                from,
                fromSubId,
                to,
                toSubId,
                amount,
                amount,
                true
            );
            emit Transfer(from, to, amount);
            return true;
        }

        // Delegate parameter updates and compute credit amount
        uint256 creditAmount = _updateTransferParametersAndComputeCredit(
            from,
            fromSubId,
            to,
            toSubId,
            amount
        );

        // Deduct from sender (always amount)
        uint256 fromBalance;
        if (_accounts[from].accountType == AccountType.Super) {
            fromBalance = _supers[from].subs[fromSubId].balance;
            require(fromBalance >= amount, "Insufficient balance");
            _supers[from].subs[fromSubId].balance = fromBalance - amount;
        } else {
            fromBalance = _accounts[from].balance;
            require(fromBalance >= amount, "Insufficient balance");
        }
        _accounts[from].balance = fromBalance - amount;

        // Add credit to receiver
        if (_accounts[to].accountType == AccountType.Super) {
            _supers[to].subs[toSubId].balance += creditAmount;
        }
        _accounts[to].balance += creditAmount;

        // Emit events
        _emitParametricTransferEvent(
            from,
            fromSubId,
            to,
            toSubId,
            amount,
            creditAmount,
            false
        );
        emit Transfer(from, to, creditAmount); // ERC-20 uses creditAmount

        return true;
    }

    // ====== MINT & BURN SKELETONS ======

    function _mintInternal(
        address to,
        uint256 amount,
        bytes memory mintData
    ) internal {
        require(to != address(0), "Mint to zero");
        require(amount > 0, "Void amount");

        // Delegate parameter computation, returns creditAmount (amount added)
        uint256 creditAmount = _applyMintParametersAndComputeCredit(
            to,
            amount,
            mintData
        );

        // Update balance
        if (_accounts[to].accountType == AccountType.Super) {
            _supers[to].subs[0].balance += creditAmount;
        }
        _accounts[to].balance += creditAmount;

        _totalSupply += creditAmount;

        _emitParametricTransferEvent(
            address(0),
            0,
            to,
            0,
            amount,
            creditAmount,
            false
        );
        emit Transfer(address(0), to, creditAmount);
    }

    function _burnInternal(
        address from,
        uint48 subId,
        uint256 amount
    ) internal {
        require(from != address(0), "Burn from zero");
        require(amount > 0, "Void amount");

        // Delegate parameter updates (resets if balance becomes zero)
        _applyBurnParameters(from, subId, amount);

        // Deduct from sender
        uint256 fromBalance;
        if (_accounts[from].accountType == AccountType.Super) {
            SuperAccountBase storage superAcc = _supers[from];
            require(subId < superAcc.subsCount, "Sub-account doesn't exist");
            fromBalance = superAcc.subs[subId].balance;
            require(fromBalance >= amount, "Insufficient balance");
            superAcc.subs[subId].balance = fromBalance - amount;
        } else {
            require(subId == 0, "Normal account cannot have subId > 0");
            fromBalance = _accounts[from].balance;
            require(fromBalance >= amount, "Insufficient balance");
        }
        _accounts[from].balance = fromBalance - amount;

        _totalSupply -= amount;

        _emitParametricTransferEvent(
            from,
            subId,
            address(0),
            0,
            amount,
            0,
            false
        );
        emit Transfer(from, address(0), amount);
    }

    // ====== VIRTUAL HOOKS ======

    /// @notice Hook to update parameters during a transfer.
    /// @return creditAmount The actual amount to credit to the receiver (may differ from `amount` for NZS).
    function _updateTransferParametersAndComputeCredit(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    ) internal virtual returns (uint256 creditAmount);

    /// @notice Hook to apply parameters during mint.
    /// @param mintData Token-specific data (e.g., predictionPrice, round, anchor).
    /// @return creditAmount The actual amount added to the receiver (may differ from `amount` for NZS).
    function _applyMintParametersAndComputeCredit(
        address to,
        uint256 amount,
        bytes memory mintData
    ) internal virtual returns (uint256 creditAmount);

    /// @notice Hook to apply burn logic (update/reset parameters).
    function _applyBurnParameters(
        address from,
        uint48 subId,
        uint256 amount
    ) internal virtual;

    /// @notice Hook to reset parameters when an account is converted to Super or a sub-account is created.
    function _resetAccountParameters(address account) internal virtual;
    function _resetSubAccountParameters(
        address account,
        uint48 subId
    ) internal virtual;

    /// @notice Hook to emit the parametric transfer event.
    /// @param isSelfTransfer True if it's a self-transfer (no parameter changes).
    function _emitParametricTransferEvent(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 debitAmount,
        uint256 creditAmount,
        bool isSelfTransfer
    ) internal virtual;
}
