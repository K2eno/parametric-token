// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/spec/IParametricPermissions.sol";
import "./Storage.sol";

contract Permissions is Storage {
    // ====== FUNCTIONS ======

    function permitForSub(
        uint48 ownerSubId,
        uint8 paramIndex,
        bool enabled,
        uint64 min,
        uint64 max,
        bool soft
    ) external returns (bool) {
        address owner = msg.sender;
        AppStorage storage s = _s();
        require(paramIndex < NUMBER_OF_PARAMS, "Invalid param index");
        require(
            s.paramConfig[paramIndex].isMutable,
            "Cannot set permission on immutable param"
        );

        if (enabled) {
            require(min <= max, "min > max");
            require(!(max == 0 && soft == true), "Invalid soft with max=0");
        } else {
            require(
                min == 0 && max == 0 && soft == false,
                "Invalid disabled permission"
            );
        }

        IParametricPermissions.Permission storage p = s.permissions[owner][
            ownerSubId
        ][paramIndex];
        p.enabled = enabled;
        p.min = min;
        p.max = max;
        p.soft = soft;

        emit IParametricPermissions.PermissionForSub(
            owner,
            ownerSubId,
            paramIndex,
            enabled,
            min,
            max,
            soft
        );
        return true;
    }

    function permissionOf(
        address account,
        uint48 subId,
        uint8 paramIndex
    ) external view returns (IParametricPermissions.Permission memory) {
        AppStorage storage s = _s();
        require(paramIndex < NUMBER_OF_PARAMS, "Invalid param index");
        require(
            s.paramConfig[paramIndex].isMutable,
            "Immutable param has no permission"
        );

        return s.permissions[account][subId][paramIndex];
    }

    function allPermissionsOf(
        address account,
        uint48 subId
    )
        external
        view
        returns (IParametricPermissions.IndexedPermission[] memory)
    {
        AppStorage storage s = _s();
        IParametricPermissions.IndexedPermission[]
            memory result = new IParametricPermissions.IndexedPermission[](
                NUMBER_OF_PARAMS
            );
        uint8 count = 0;

        for (uint8 i = 0; i < NUMBER_OF_PARAMS; i++) {
            if (
                s.paramConfig[i].isMutable &&
                s.permissions[account][subId][i].enabled
            ) {
                IParametricPermissions.Permission storage p = s.permissions[
                    account
                ][subId][i];
                result[count] = IParametricPermissions.IndexedPermission({
                    paramIndex: i,
                    min: p.min,
                    max: p.max,
                    soft: p.soft
                });
                count++;
            }
        }

        // Truncate array to only enabled
        assembly {
            mstore(result, count)
        }

        return result;
    }
}
