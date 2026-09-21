// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IFacilitatorRegistry} from "./interfaces/IFacilitatorRegistry.sol";

contract FacilitatorRegistry is AccessControl, IFacilitatorRegistry {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    struct Facilitator {
        bool exists;
        bool enabled;
        uint128 capacity;
        uint128 outstanding;
        uint16 maxLossBps;
        uint32 maxTtl;
        uint16 riskWeightBps;
    }

    mapping(bytes32 => Facilitator) public facilitator;
    bytes32[] public facilitatorIds;

    uint256 public override totalOutstanding;

    error ZeroAddress();
    error FacilitatorExists();
    error FacilitatorMissing();
    error FacilitatorDisabled();
    error CapacityExceeded();
    error OutstandingUnderflow();
    error InvalidCapacity();

    constructor(address admin, address guardian) {
        if (admin == address(0) || guardian == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, guardian);
    }

    function addFacilitator(
        bytes32 facilitatorId,
        uint128 capacity,
        uint16 maxLossBps,
        uint32 maxTtl,
        uint16 riskWeightBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (facilitator[facilitatorId].exists) revert FacilitatorExists();
        if (capacity == 0 || riskWeightBps == 0) revert InvalidCapacity();

        facilitator[facilitatorId] = Facilitator({
            exists: true,
            enabled: true,
            capacity: capacity,
            outstanding: 0,
            maxLossBps: maxLossBps,
            maxTtl: maxTtl,
            riskWeightBps: riskWeightBps
        });
        facilitatorIds.push(facilitatorId);
    }

    function disableFacilitator(bytes32 facilitatorId)
        external
        onlyRole(GUARDIAN_ROLE)
    {
        Facilitator storage f = facilitator[facilitatorId];
        if (!f.exists) revert FacilitatorMissing();
        f.enabled = false;
    }

    function setCapacity(bytes32 facilitatorId, uint128 newCapacity)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        Facilitator storage f = facilitator[facilitatorId];
        if (!f.exists) revert FacilitatorMissing();
        if (newCapacity < f.outstanding) revert CapacityExceeded();
        f.capacity = newCapacity;
    }

    function increaseOutstanding(bytes32 facilitatorId, uint256 amount)
        external
        override
        onlyRole(CONTROLLER_ROLE)
    {
        Facilitator storage f = facilitator[facilitatorId];
        if (!f.exists) revert FacilitatorMissing();
        if (!f.enabled) revert FacilitatorDisabled();

        uint256 next = uint256(f.outstanding) + amount;
        if (next > f.capacity) revert CapacityExceeded();

        f.outstanding = uint128(next);
        totalOutstanding += amount;
    }

    function decreaseOutstanding(bytes32 facilitatorId, uint256 amount)
        external
        override
        onlyRole(CONTROLLER_ROLE)
    {
        Facilitator storage f = facilitator[facilitatorId];
        if (!f.exists) revert FacilitatorMissing();
        if (amount > f.outstanding) revert OutstandingUnderflow();

        f.outstanding -= uint128(amount);
        totalOutstanding -= amount;
    }

    function outstandingOf(bytes32 facilitatorId)
        external
        view
        override
        returns (uint256)
    {
        return facilitator[facilitatorId].outstanding;
    }

    function remainingCapacity(bytes32 facilitatorId)
        external
        view
        override
        returns (uint256)
    {
        Facilitator memory f = facilitator[facilitatorId];
        if (!f.exists || !f.enabled) return 0;
        return uint256(f.capacity) - uint256(f.outstanding);
    }

    function maxTtlOf(bytes32 facilitatorId) external view override returns (uint32) {
        return facilitator[facilitatorId].maxTtl;
    }

    function facilitatorCount() external view returns (uint256) {
        return facilitatorIds.length;
    }
}
