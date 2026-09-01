// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/spec/IParametricToken.sol";
import "../interfaces/spec/IParametricPermissions.sol";

contract Storage {
    // ====== CONSTANTS ======

    uint8 internal constant NUMBER_OF_PARAMS = 2;
    uint256 internal constant STORAGE_SLOT =
        0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

    enum AccountType {
        Normal,
        Super
    }

    // ====== STRUCTS ======

    struct Account {
        AccountType accountType;
        uint256 balance;
        uint64[NUMBER_OF_PARAMS] parameters;
    }

    struct SubAccount {
        uint256 balance;
        uint64[NUMBER_OF_PARAMS] parameters;
    }

    struct SuperAccount {
        SubAccount[] subs;
        uint48 subsCount;
    }

    struct Allowance {
        uint256 total;
        uint256 sub;
        uint48 subId;
        bool oneOff;
        uint64 committedUntil;
    }

    // ====== APP STORAGE ======

    struct AppStorage {
        string name;
        string symbol;
        uint256 totalSupply;
        IParametricToken.ParamConfig[] paramConfig;
        mapping(address => Account) accounts;
        mapping(address => SuperAccount) supers;
        mapping(address => mapping(address => Allowance)) allowances;
        mapping(address => mapping(uint48 => mapping(uint8 => IParametricPermissions.Permission))) permissions;
        // Prediction-specific
        address engine;
        uint64 maxRounds;
    }

    // ====== STORAGE SLOT ======

    function _s() internal pure returns (AppStorage storage s) {
        assembly {
            s.slot := STORAGE_SLOT
        }
    }
}
