// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/spec/IParametricToken.sol";
import "./Storage.sol";

contract Core is Storage {
    // ====== MODIFIERS ======

    modifier onlyNormal(address account) {
        AppStorage storage s = _s();
        require(
            s.accounts[account].accountType == AccountType.Normal,
            "Not normal account"
        );
        _;
    }

    modifier onlySuper(address account) {
        AppStorage storage s = _s();
        require(
            s.accounts[account].accountType == AccountType.Super,
            "Not super account"
        );
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

    // ====== ERC-20 FUNCTIONS ======

    function name() external view returns (string memory) {
        return _s().name;
    }

    function symbol() external view returns (string memory) {
        return _s().symbol;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external view returns (uint256) {
        return _s().totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _s().accounts[account].balance;
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        AppStorage storage s = _s();
        return s.allowances[owner][spender].total;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        address owner = msg.sender;
        AppStorage storage s = _s();
        Allowance storage al = s.allowances[owner][spender];
        al.total = amount;
        if (al.sub > amount) al.sub = amount;
        if (amount == 0) {
            al.subId = 0;
            al.oneOff = false;
            al.committedUntil = 0;
        }
        emit IERC20.Approval(owner, spender, amount);
        return true;
    }

    // ====== SUB-ACCOUNT MANAGEMENT ======

    function convertToSuper() external onlyNormal(msg.sender) returns (bool) {
        address account = msg.sender;
        AppStorage storage s = _s();
        Account storage acc = s.accounts[account];
        acc.accountType = AccountType.Super;

        // Create sub-account 0 and copy parameters
        SubAccount memory sub;
        sub.balance = acc.balance;

        // Copy parameters
        for (uint8 i = 0; i < NUMBER_OF_PARAMS; i++) {
            sub.parameters[i] = acc.parameters[i];
        }
        s.supers[account].subs.push(sub);
        s.supers[account].subsCount = 1;

        // Reset normal parameters
        for (uint8 i = 0; i < NUMBER_OF_PARAMS; i++) {
            acc.parameters[i] = 0;
        }

        emit IParametricToken.AccountConvertedToSuper(account);
        emit IParametricToken.SubAccountCreated(account, 0);
        return true;
    }

    function createSubAccount()
        external
        onlySuper(msg.sender)
        returns (uint48)
    {
        address account = msg.sender;
        AppStorage storage s = _s();
        SuperAccount storage superAcc = s.supers[account];
        SubAccount memory newSub;
        newSub.balance = 0;
        for (uint8 i = 0; i < NUMBER_OF_PARAMS; i++) {
            newSub.parameters[i] = 0;
        }
        superAcc.subs.push(newSub);
        superAcc.subsCount = uint48(superAcc.subs.length);
        uint48 newSubId = superAcc.subsCount - 1;

        emit IParametricToken.SubAccountCreated(account, newSubId);
        return newSubId;
    }

    function isSuperAccount(address account) external view returns (bool) {
        return _s().accounts[account].accountType == AccountType.Super;
    }

    function subsCountOf(address account) external view returns (uint48) {
        AppStorage storage s = _s();
        if (s.accounts[account].accountType == AccountType.Super) {
            return s.supers[account].subsCount;
        }
        return 0;
    }

    function parametricBalanceOf(
        address account,
        uint48 subId
    ) external view onlyValidSub(account, subId) returns (uint256) {
        AppStorage storage s = _s();
        if (s.accounts[account].accountType == AccountType.Normal) {
            return s.accounts[account].balance;
        }
        return s.supers[account].subs[subId].balance;
    }

    // ====== PARAMETRIC ALLOWANCES ======

    function approveForSub(
        uint48 ownerSubId,
        address spender,
        uint256 amount,
        bool oneOff,
        uint64 committedUntil
    )
        external
        onlySuper(msg.sender)
        onlyValidSub(msg.sender, ownerSubId)
        returns (bool)
    {
        address owner = msg.sender;
        AppStorage storage s = _s();
        require(s.supers[owner].subsCount > 1, "Single sub-account");

        if (ownerSubId == 0) {
            require(amount == 0, "SubId 0 requires zero amount");
            require(!oneOff, "SubId 0 requires false oneOff");
            require(committedUntil == 0, "SubId 0 doesn't accept commitment");
        } else {
            if (oneOff)
                require(amount > 0, "OneOff requires positive sub allowance");
        }
        if (committedUntil > 0) {
            require(committedUntil > block.timestamp, "Invalid commitment");
        }

        Allowance storage al = s.allowances[owner][spender];

        if (al.committedUntil >= block.timestamp) {
            require(
                ownerSubId == al.subId,
                "Committed allowance can't be changed"
            );
            require(amount > al.sub, "Committed allowance can't be reduced");
        } else {
            al.oneOff = oneOff;
            al.committedUntil = committedUntil;
        }

        al.subId = ownerSubId;
        if (amount < al.sub) al.total = (al.total - al.sub) + amount;
        al.sub = amount;
        if (amount > al.total) al.total = amount;

        emit IParametricToken.ApprovalForSub(
            owner,
            ownerSubId,
            spender,
            amount,
            oneOff,
            committedUntil
        );
        return true;
    }

    function subAllowance(
        address owner,
        address spender
    ) external view returns (uint48, uint256, bool, uint64) {
        Allowance storage al = _s().allowances[owner][spender];
        return (al.subId, al.sub, al.oneOff, al.committedUntil);
    }

    function allowanceOf(
        address owner,
        uint48 subId,
        address spender
    ) external view onlyValidSub(owner, subId) returns (uint256, bool, uint64) {
        Allowance storage al = _s().allowances[owner][spender];
        if (al.subId == subId && subId > 0) {
            return (al.sub, al.oneOff, al.committedUntil);
        }
        return (al.total - al.sub, false, 0);
    }

    // ====== PARAMETER QUERIES ======

    function parameterOf(
        address account,
        uint48 subId,
        uint8 paramIndex
    ) external view onlyValidSub(account, subId) returns (uint64) {
        require(paramIndex < NUMBER_OF_PARAMS, "Invalid param index");
        AppStorage storage s = _s();
        if (s.accounts[account].accountType == AccountType.Super) {
            return s.supers[account].subs[subId].parameters[paramIndex];
        } else {
            return s.accounts[account].parameters[paramIndex];
        }
    }

    function allParametersOf(
        address account,
        uint48 subId
    ) external view onlyValidSub(account, subId) returns (uint64[] memory) {
        uint64[] memory params = new uint64[](NUMBER_OF_PARAMS);
        AppStorage storage s = _s();
        if (s.accounts[account].accountType == AccountType.Super) {
            for (uint8 i = 0; i < NUMBER_OF_PARAMS; i++) {
                params[i] = s.supers[account].subs[subId].parameters[i];
            }
        } else {
            for (uint8 i = 0; i < NUMBER_OF_PARAMS; i++) {
                params[i] = s.accounts[account].parameters[i];
            }
        }
        return params;
    }
}
