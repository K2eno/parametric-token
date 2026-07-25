// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/ITenureToken.sol";

contract TenureToken is Ownable, ITenureToken {
    // Parameter constants
    uint8 public constant NUMBER_OF_PARAMETERS = 1;

    // ParamConfig
    struct ParamConfig {
        bytes32 name;
        uint8 decimals;
        bool isMutable;
    }
    ParamConfig[NUMBER_OF_PARAMETERS] private _paramConfig;

    // Account & Sub‑account storage
    struct Account {
        AccountType accountType;
        uint256 balance;
        uint64[NUMBER_OF_PARAMETERS] parameters;
    }
    struct SubAccount {
        uint256 balance;
        uint64[NUMBER_OF_PARAMETERS] parameters;
    }
    struct SuperAccount {
        SubAccount[] subs;
        uint48 subsCount;
    }

    // ERC20 state
    string private _name;
    string private _symbol;
    uint256 private _totalSupply;

    mapping(address => Account) private _accounts;
    mapping(address => SuperAccount) private _supers;
    uint64[NUMBER_OF_PARAMETERS] private _parametersInit; // default zero

    // Allowance storage
    struct Allowance {
        uint256 total;
        uint256 sub;
        uint48 subId;
        bool oneOff;
    }
    mapping(address => mapping(address => Allowance)) private _allowances;

    // Engine
    address private _engine;

    // Modifiers
    modifier onlyEngine() {
        require(msg.sender == _engine, "InverseToken: not engine");
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

    // Constructor
    constructor(string memory name, string memory symbol) Ownable(msg.sender) {
        _name = name;
        _symbol = symbol;
        _paramConfig[0] = ParamConfig({
            name: "mintTime",
            decimals: 0,
            isMutable: true
        });
    }

    // ERC20 overrides
    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        return _parametricTransfer(msg.sender, 0, to, 0, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        return _parametricTransfer(from, 0, to, 0, amount);
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        address owner = msg.sender;
        Allowance storage al = _allowances[owner][spender];
        al.total = amount;
        if (al.sub > amount) al.sub = amount;
        if (amount == 0) al.oneOff = false;
        emit Approval(owner, spender, amount);
        return true;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _accounts[account].balance;
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender].total;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    // ───── Parametric: account management ─────
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

    function accountType(address account) external view returns (AccountType) {
        return _accounts[account].accountType;
    }

    // ───── Parametric: queries ─────
    function parametricBalanceOf(
        address account,
        uint48 subId
    ) external view onlyValidSub(account, subId) returns (uint256) {
        if (_accounts[account].accountType == AccountType.Normal)
            return _accounts[account].balance;
        return _supers[account].subs[subId].balance;
    }

    function subsCountOf(
        address superAccount
    ) external view onlySuper(superAccount) returns (uint48) {
        return _supers[superAccount].subsCount;
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

    function paramConfig(
        uint8 index
    ) external view returns (bytes32, uint8, bool) {
        return (
            _paramConfig[index].name,
            _paramConfig[index].decimals,
            _paramConfig[index].isMutable
        );
    }

    function getMintTime(
        address account,
        uint48 subId
    ) public view onlyValidSub(account, subId) returns (uint64) {
        return parameterOf(0, account, subId);
    }

    // ───── Parametric: allowances ─────
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
        al.sub = amount;
        al.oneOff = oneOff;
        if (amount > al.total) al.total = amount;

        emit ApprovalForSub(owner, ownerSubId, spender, amount, oneOff);
        return true;
    }

    function allowanceForSub(
        address account,
        uint48 subId,
        address spender
    ) external view onlyValidSub(account, subId) returns (uint256, bool) {
        Allowance storage al = _allowances[account][spender];
        if (al.subId == subId) return (al.sub, al.oneOff);
        return (al.total - al.sub, false); // oneOff only applies to the exact subId
    }

    // ───── Parametric: transfers ─────
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

    // ───── Internal helpers ─────
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

    function _weightedAverage(
        uint64 param1,
        uint256 amount1,
        uint64 param2,
        uint256 amount2
    ) private pure returns (uint64) {
        require(param1 > 0 && amount1 > 0, "Invalid amounts");
        uint256 product = uint256(param1) * amount1 + uint256(param2) * amount2;
        uint256 sum = amount1 + amount2;
        return uint64(product / sum);
    }

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
        uint64 fromMintTime;
        uint64 toMintTime;
        uint256 fromBalance;
        uint256 toBalance;

        if (_accounts[from].accountType == AccountType.Super) {
            fromMintTime = _supers[from].subs[fromSubId].parameters[0];
            fromBalance = _supers[from].subs[fromSubId].balance;
        } else {
            fromMintTime = _accounts[from].parameters[0];
            fromBalance = _accounts[from].balance;
        }

        if (_accounts[to].accountType == AccountType.Super) {
            toMintTime = _supers[to].subs[toSubId].parameters[0];
            toBalance = _supers[to].subs[toSubId].balance;
        } else {
            toMintTime = _accounts[to].parameters[0];
            toBalance = _accounts[to].balance;
        }

        if (toBalance == 0) {
            toMintTime = fromMintTime;
        } else {
            toMintTime = _weightedAverage(
                fromMintTime,
                amount,
                toMintTime,
                toBalance
            );
        }

        // Update recipient
        if (_accounts[to].accountType == AccountType.Super) {
            _supers[to].subs[toSubId].parameters[0] = toMintTime;
        } else {
            _accounts[to].parameters[0] = toMintTime;
        }

        // Clear sender if balance becomes zero
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

        _updateParametersBeforeExecution(from, fromSubId, to, toSubId, amount);

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

    // Mint & Burn (engine only)
    function mint(address to, uint256 amount) external onlyEngine {
        require(to != address(0), "Invalid account");
        _parametricMint(to, amount);
    }

    function burn(
        address from,
        uint48 subId,
        uint256 amount
    ) external onlyEngine onlyValidSub(from, subId) {
        require(from != address(0), "Invalid account");
        _parametricBurn(from, subId, amount);
    }

    function _parametricMint(address account, uint256 amount) internal {
        require(amount > 0, "Void amount");
        Account storage acc = _accounts[account];
        uint64 mintTime = uint64(block.timestamp);

        if (acc.accountType == AccountType.Super) {
            SuperAccount storage superAcc = _supers[account];
            require(superAcc.subsCount > 0, "No sub-accounts");
            SubAccount storage sub0 = superAcc.subs[0];
            if (sub0.balance == 0) {
                sub0.parameters[0] = mintTime;
            } else {
                sub0.parameters[0] = _weightedAverage(
                    mintTime,
                    amount,
                    sub0.parameters[0],
                    sub0.balance
                );
            }
            sub0.balance += amount;
        } else {
            if (acc.balance == 0) {
                acc.parameters[0] = mintTime;
            } else {
                acc.parameters[0] = _weightedAverage(
                    mintTime,
                    amount,
                    acc.parameters[0],
                    acc.balance
                );
            }
        }

        acc.balance += amount;
        _totalSupply += amount;
        emit ParametricTransfer(address(0), 0, account, 0, amount);
        emit Transfer(address(0), account, amount);
    }

    function _parametricBurn(
        address account,
        uint48 subId,
        uint256 amount
    ) internal {
        require(amount > 0, "Void amount");
        Account storage acc = _accounts[account];

        if (acc.accountType == AccountType.Super) {
            SuperAccount storage superAcc = _supers[account];
            SubAccount storage sub = superAcc.subs[subId];
            require(sub.balance >= amount, "Insufficient balance");
            sub.balance -= amount;
            if (sub.balance == 0) {
                sub.parameters = _parametersInit;
            }
        } else {
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

    // Engine management
    function setEngine(address engine_) external onlyOwner {
        require(engine_ != address(0), "Zero engine address");
        _engine = engine_;
    }

    function engine() external view returns (address) {
        return _engine;
    }
}
