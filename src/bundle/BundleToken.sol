// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IBundleToken.sol";
import "../libraries/Lib.sol";

contract BundleToken is Ownable, IParametricToken {
    // ====== CONSTANTS ======

    uint8 public constant NUMBER_OF_PARAMETERS = 1; // only anchor (mutable)

    // ====== STRUCTS ======

    // ParamConfig
    struct ParamConfig {
        bytes32 name;
        uint8 decimals;
        bool isMutable;
    }

    // Account & Sub‑account storage
    struct Account {
        AccountType accountType;
        uint256 balance;
        uint64[NUMBER_OF_PARAMETERS] parameters; // [0] = anchor
    }
    struct SubAccount {
        uint256 balance;
        uint64[NUMBER_OF_PARAMETERS] parameters;
    }
    struct SuperAccount {
        SubAccount[] subs;
        uint48 subsCount;
    }

    // Allowance storage
    struct Allowance {
        uint256 total;
        uint256 sub;
        uint48 subId;
        bool oneOff;
    }

    // ====== STATE ======

    // ERC20 state
    string private _name;
    string private _symbol;
    uint256 private _totalSupply;

    // Core state
    uint64[NUMBER_OF_PARAMETERS] private _parametersInit; // default zero
    ParamConfig[NUMBER_OF_PARAMETERS] private _paramConfig;

    mapping(address => Account) private _accounts;
    mapping(address => SuperAccount) private _supers;
    mapping(address => mapping(address => Allowance)) private _allowances;

    address private _engine;

    // ====== MODIFIERS ======

    modifier onlyEngine() {
        require(msg.sender == _engine, "BundleToken: not engine");
        _;
    }

    modifier onlyNormal(address account) {
        require(
            _accounts[account].accountType == AccountType.Normal,
            "Not normal account"
        );
        _;
    }

    modifier onlySuper(address account) {
        require(
            _accounts[account].accountType == AccountType.Super,
            "Not super account"
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

        _paramConfig[0] = ParamConfig({
            name: "anchor",
            decimals: 8, // USD price with 8 decimals
            isMutable: true
        });
    }

    // ====== MANAGEMENT FUNCTIONS ======

    function setEngine(address engine) external onlyOwner {
        require(engine != address(0), "Zero engine address");
        _engine = engine;
    }

    // ====== ERC-20 FUNCTIONS ======

    // ERC-20 getters
    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8) {
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

    // ERC-20 approval
    function approve(address spender, uint256 amount) external returns (bool) {
        address owner = msg.sender;
        Allowance storage al = _allowances[owner][spender];
        al.total = amount;
        if (al.sub > amount) al.sub = amount;
        if (amount == 0) al.oneOff = false;
        emit Approval(owner, spender, amount);
        return true;
    }

    // ERC-20 transfers
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

    // Super account: management
    function convertToSuper(
        address account
    ) external onlyNormal(account) returns (bool) {
        require(msg.sender == account, "Only owner can convert");
        Account storage acc = _accounts[account];
        acc.accountType = AccountType.Super;
        _supers[account].subs.push(
            SubAccount({balance: acc.balance, parameters: acc.parameters})
        );
        _supers[account].subsCount = 1;
        acc.parameters = _parametersInit;
        emit AccountConvertedToSuper(account);
        emit SubAccountCreated(account, 0);
        return true;
    }

    function createSubAccount(
        address account
    ) external onlySuper(account) returns (uint48) {
        require(msg.sender == account, "Only owner can create");
        SuperAccount storage acc = _supers[account];
        acc.subs.push(SubAccount({balance: 0, parameters: _parametersInit}));
        acc.subsCount = uint48(acc.subs.length);
        uint48 newSubId = acc.subsCount - 1;
        emit SubAccountCreated(account, newSubId);
        return newSubId;
    }

    // Parametric: allowances
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

    // Parametric: transfers
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

    // Parametric: mint & burn
    function mint(
        address to,
        uint256 amount,
        uint64 anchor_
    ) external onlyEngine {
        require(to != address(0), "Invalid account");
        require(amount > 0, "Void amount");
        require(anchor_ > 0, "Zero anchor");

        _parametricMint(to, amount, anchor_);
    }

    function burn(
        address from,
        uint48 subId,
        uint256 amount
    ) external onlyEngine onlyValidSub(from, subId) {
        require(from != address(0), "Invalid account");
        require(amount > 0, "Void amount");

        _parametricBurn(from, subId, amount);
    }

    // ====== HELPERS ======

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

    function _updateParametersBeforeExecution(
        address from,
        uint48 fromSubId,
        address to,
        uint48 toSubId,
        uint256 amount
    ) private {
        uint64 fromAnchor;
        uint64 toAnchor;
        uint256 fromBalance;
        uint256 toBalance;

        if (_accounts[from].accountType == AccountType.Super) {
            SubAccount storage fromSub = _supers[from].subs[fromSubId];
            fromAnchor = fromSub.parameters[0];
            fromBalance = fromSub.balance;
        } else {
            fromAnchor = _accounts[from].parameters[0];
            fromBalance = _accounts[from].balance;
        }

        if (_accounts[to].accountType == AccountType.Super) {
            SubAccount storage toSub = _supers[to].subs[toSubId];
            toAnchor = toSub.parameters[0];
            toBalance = toSub.balance;
        } else {
            toAnchor = _accounts[to].parameters[0];
            toBalance = _accounts[to].balance;
        }

        // If destination balance is zero, just copy source anchor and set new balance = amount
        if (toBalance == 0) {
            toAnchor = fromAnchor;
            toBalance = amount;
        } else {
            // Combine the existing destination holding with the incoming amount
            // The incoming amount is considered as a holding with the source anchor.
            (uint64 combinedAnchor, uint256 combinedBalance) = Lib.combine(
                fromAnchor,
                amount,
                toAnchor,
                toBalance
            );
            toAnchor = combinedAnchor;
            toBalance = combinedBalance;
        }

        // Store updated values in destination
        if (_accounts[to].accountType == AccountType.Super) {
            _supers[to].subs[toSubId].parameters[0] = toAnchor;
            // balance will be updated after transfer in _parametricTransfer
        } else {
            _accounts[to].parameters[0] = toAnchor;
        }

        // If source balance becomes zero after transfer, reset its parameters
        if (fromBalance == amount) {
            if (_accounts[from].accountType == AccountType.Super) {
                _supers[from].subs[fromSubId].parameters = _parametersInit;
            } else {
                _accounts[from].parameters = _parametersInit;
            }
        }
    }

    // Core transfer logic
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

        // Update parameters (anchor) before balance changes
        _updateParametersBeforeExecution(from, fromSubId, to, toSubId, amount);

        // Perform balance updates
        uint256 fromBalance;
        if (_accounts[from].accountType == AccountType.Super) {
            fromBalance = _supers[from].subs[fromSubId].balance;
            require(fromBalance >= amount, "Insufficient balance");
            _supers[from].subs[fromSubId].balance -= amount;
        } else {
            fromBalance = _accounts[from].balance;
            require(fromBalance >= amount, "Insufficient balance");
        }
        _accounts[from].balance -= amount;

        if (_accounts[to].accountType == AccountType.Super) {
            _supers[to].subs[toSubId].balance += amount;
        }
        _accounts[to].balance += amount;

        emit ParametricTransfer(from, fromSubId, to, toSubId, amount);
        if (from != to) emit Transfer(from, to, amount);
        return true;
    }

    function _parametricMint(
        address to,
        uint256 amount,
        uint64 anchor_
    ) internal {
        Account storage acc = _accounts[to];

        if (acc.accountType == AccountType.Super) {
            SuperAccount storage superAcc = _supers[to];
            SubAccount storage sub0 = superAcc.subs[0];

            uint256 oldSubBalance = sub0.balance;
            uint64 oldAnchor = sub0.parameters[0];

            (uint64 newAnchor, uint256 newSubBalance) = Lib.combine(
                anchor_,
                amount,
                oldAnchor,
                oldSubBalance
            );

            sub0.parameters[0] = newAnchor;
            sub0.balance = newSubBalance;
            acc.balance = acc.balance - oldSubBalance + newSubBalance;
            _totalSupply = _totalSupply - oldSubBalance + newSubBalance;
        } else {
            // Normal account
            uint256 oldBalance = acc.balance;
            uint64 oldAnchor = acc.parameters[0];

            (uint64 newAnchor, uint256 newBalance) = Lib.combine(
                anchor_,
                amount,
                oldAnchor,
                oldBalance
            );

            acc.parameters[0] = newAnchor;
            acc.balance = newBalance;
            _totalSupply = _totalSupply - oldBalance + newBalance;
        }

        emit ParametricTransfer(address(0), 0, to, 0, amount);
        emit Transfer(address(0), to, amount);
    }

    function _parametricBurn(
        address account,
        uint48 subId,
        uint256 amount
    ) internal {
        Account storage acc = _accounts[account];

        if (acc.accountType == AccountType.Super) {
            SuperAccount storage superAcc = _supers[account];
            require(subId < superAcc.subsCount, "Sub-account doesn't exist");
            SubAccount storage sub = superAcc.subs[subId];
            require(sub.balance >= amount, "Insufficient balance");

            sub.balance -= amount;
            acc.balance -= amount;

            if (sub.balance == 0) {
                sub.parameters = _parametersInit;
            }
        } else {
            require(subId == 0, "Normal account cannot have subId > 0");
            require(acc.balance >= amount, "Insufficient balance");

            acc.balance -= amount;

            if (acc.balance == 0) {
                acc.parameters = _parametersInit;
            }
        }

        _totalSupply -= amount;
        emit ParametricTransfer(account, subId, address(0), 0, amount);
        emit Transfer(account, address(0), amount);
    }

    // ====== PARAMETRIC GETTERS ======

    // Super account data
    function accountType(address account) external view returns (AccountType) {
        return _accounts[account].accountType;
    }

    function subsCountOf(address account) external view returns (uint48) {
        if (_accounts[account].accountType == AccountType.Super) {
            return _supers[account].subsCount;
        }
        return 0;
    }

    // Parameters data
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
        if (_accounts[account].accountType != AccountType.Super) {
            return _accounts[account].parameters[paramIndex];
        }
        return _supers[account].subs[subId].parameters[paramIndex];
    }

    function anchor(
        address account,
        uint48 subId
    ) public view onlyValidSub(account, subId) returns (uint64) {
        return parameterOf(0, account, subId);
    }

    // Parametric balance
    function parametricBalanceOf(
        address account,
        uint48 subId
    ) external view onlyValidSub(account, subId) returns (uint256) {
        if (_accounts[account].accountType == AccountType.Normal)
            return _accounts[account].balance;
        return _supers[account].subs[subId].balance;
    }

    // Parametric allowance
    function allowanceForSub(
        address account,
        uint48 subId,
        address spender
    ) external view onlyValidSub(account, subId) returns (uint256, bool) {
        Allowance storage al = _allowances[account][spender];
        if (al.subId == subId) return (al.sub, al.oneOff);
        return (al.total - al.sub, false);
    }
}
