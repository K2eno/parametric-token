// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**`
 * @title IParametricTokenPermissions
 * @dev Extension of IParametricToken interface to support inbound permissions
 */
interface IParametricPermissions {
    // ====== STRUCTS ======

    struct Permission {
        bool enabled; // Enabled flag
        uint64 min; // Minimum acceptable value (inclusive)
        uint64 max; // Maximum acceptable value (inclusive)
        bool soft; // If true, owner is exempt; if false, applies to all
    }

    struct IndexedPermission {
        uint8 paramIndex; // Parameter index
        uint64 min; // Minimum acceptable value (inclusive)
        uint64 max; // Maximum acceptable value (inclusive)
        bool soft; // If true, owner is exempt; if false, applies to all
    }

    // ====== EVENTS ======

    /**
     * @notice Emitted when a permission is created or updated
     * @param owner The address of the account owner
     * @param subId The sub-account for which the permission is set
     * @param index The index of parameter for which the permission is set
     * @param enabled The enabled flag
     * @param min The minimum for incoming parameter value
     * @param max The maximum for incoming parameter value
     * @param soft `true` to skip checks for transfers from account owner
     */
    event PermissionForSub(
        address indexed owner,
        uint48 indexed subId,
        uint8 indexed index,
        bool enabled,
        uint64 min,
        uint64 max,
        bool soft
    );

    // ====== FUNCTIONS ======

    // Permission setter

    /**
     * @notice Sets or updates a permission for inbound transfers to a sub-account
     * @dev Only callable by the account owner (ownerSubId = 0 for Normal accounts).
     *      If the index corresponds to an immutable parameter: MUST revert.
     *      If enabled == true: MUST revert if min > max, or (max == 0 and soft == true)
     *      If enabled == false: MUST revert if (min, max, soft) are not (0, 0, false)
     * @param ownerSubId The sub-account to apply the permission to
     * @param paramIndex The parameter index (0 to NUMBER_OF_PARAMETERS-1)
     * @param enabled The enabled flag
     * @param min Minimum acceptable value (inclusive)
     * @param max Maximum acceptable value (inclusive)
     * @param soft If true, owner is exempt; if false, applies to all
     * @return true if the permission setting succeeded
     */
    function permitForSub(
        uint48 ownerSubId,
        uint8 paramIndex,
        bool enabled,
        uint64 min,
        uint64 max,
        bool soft
    ) external returns (bool);

    // Getters

    /**
     * @notice Returns the current permission for a specific parameter and sub-account
     * @dev  MUST revert if index corresponds to an immutable parameter
     * @param account The address of the account
     * @param subId The sub-account index
     * @param paramIndex The parameter index (0 to NUMBER_OF_PARAMETERS-1)
     * @return Permission The current permission (min, max, soft).
     *         If no permission is set, returns (0, 0 , false)
     */
    function permissionOf(
        address account,
        uint48 subId,
        uint8 paramIndex
    ) external view returns (Permission memory);

    /**
     * @notice Returns all permissions for a sub-account, sorted by index
     * @dev If no permissions are enabled, returns an empty array.
     *      Only enabled permissions for mutable parameters are returned
     * @param account The address of the account
     * @param subId The sub-account index
     * @return IndexedPermission[] An array of all permissions, sorted ascending by index
     */
    function allPermissionsOf(
        address account,
        uint48 subId
    ) external view returns (IndexedPermission[] memory);
}
