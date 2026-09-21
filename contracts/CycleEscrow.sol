// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {CycleState, QETypes} from "./types/QETypes.sol";
import {ICycleEscrow} from "./interfaces/ICycleEscrow.sol";

contract CycleEscrow is AccessControl, ICycleEscrow {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant FACILITATOR_ROLE = keccak256("FACILITATOR_ROLE");

    mapping(uint256 => QETypes.Cycle) public cycle;
    uint256 public override totalPrincipalOutstanding;

    error ZeroAddress();
    error CycleExists();
    error CycleMissing();
    error InvalidPrincipal();
    error InvalidState();
    error BurnExceedsPrincipal();

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function createCycle(
        uint256 cycleId,
        bytes32 facilitatorId,
        uint256 principal,
        uint32 ttl,
        bytes32 routeHash
    ) external override onlyRole(CONTROLLER_ROLE) {
        if (cycle[cycleId].state != CycleState.NONE) revert CycleExists();
        if (principal == 0 || principal > type(uint128).max) revert InvalidPrincipal();
        if (ttl == 0) revert InvalidPrincipal();

        cycle[cycleId] = QETypes.Cycle({
            facilitatorId: facilitatorId,
            state: CycleState.MINTED,
            principalMinted: uint128(principal),
            principalBurned: 0,
            externalValueInUsd18: 0,
            externalValueOutUsd18: 0,
            realizedPnlUsd18: 0,
            openedAt: uint48(block.timestamp),
            expiresAt: uint48(block.timestamp + ttl),
            routeHash: routeHash
        });

        totalPrincipalOutstanding += principal;
    }

    function markDeployed(uint256 cycleId) external onlyRole(FACILITATOR_ROLE) {
        QETypes.Cycle storage c = _cycle(cycleId);
        if (c.state != CycleState.MINTED) revert InvalidState();
        if (block.timestamp > c.expiresAt) revert InvalidState();
        c.state = CycleState.DEPLOYED;
    }

    function markReturned(uint256 cycleId, uint256 externalValueOutUsd18)
        external
        onlyRole(FACILITATOR_ROLE)
    {
        QETypes.Cycle storage c = _cycle(cycleId);
        if (c.state != CycleState.DEPLOYED) revert InvalidState();
        if (externalValueOutUsd18 > type(uint128).max) revert InvalidPrincipal();
        c.externalValueOutUsd18 = uint128(externalValueOutUsd18);
        c.state = CycleState.RETURNED;
    }

    function recordPrincipalBurn(uint256 cycleId, uint256 amount)
        external
        override
        onlyRole(CONTROLLER_ROLE)
    {
        QETypes.Cycle storage c = _cycle(cycleId);
        if (
            c.state == CycleState.SETTLED ||
            c.state == CycleState.DEFAULTED ||
            c.state == CycleState.EMERGENCY_SETTLED
        ) revert InvalidState();

        uint256 outstanding =
            uint256(c.principalMinted) - uint256(c.principalBurned);
        if (amount == 0 || amount > outstanding) revert BurnExceedsPrincipal();

        c.principalBurned += uint128(amount);
        totalPrincipalOutstanding -= amount;

        if (c.principalBurned == c.principalMinted) {
            c.state = CycleState.PRINCIPAL_BURNED;
        }
    }

    function markSettled(uint256 cycleId, int256 realizedPnlUsd18)
        external
        onlyRole(CONTROLLER_ROLE)
    {
        QETypes.Cycle storage c = _cycle(cycleId);
        if (
            c.state != CycleState.PRINCIPAL_BURNED ||
            c.principalBurned != c.principalMinted
        ) revert InvalidState();

        if (
            realizedPnlUsd18 > type(int128).max ||
            realizedPnlUsd18 < type(int128).min
        ) revert InvalidPrincipal();

        c.realizedPnlUsd18 = int128(realizedPnlUsd18);
        c.state = CycleState.SETTLED;
    }

    function markExpired(uint256 cycleId) external {
        QETypes.Cycle storage c = _cycle(cycleId);
        if (block.timestamp <= c.expiresAt) revert InvalidState();
        if (
            c.state == CycleState.SETTLED ||
            c.state == CycleState.PRINCIPAL_BURNED ||
            c.state == CycleState.DEFAULTED ||
            c.state == CycleState.EMERGENCY_SETTLED
        ) revert InvalidState();
        c.state = CycleState.EXPIRED;
    }

    function principalOutstanding(uint256 cycleId)
        external
        view
        override
        returns (uint256)
    {
        QETypes.Cycle storage c = cycle[cycleId];
        if (c.state == CycleState.NONE) return 0;
        return uint256(c.principalMinted) - uint256(c.principalBurned);
    }

    function stateOf(uint256 cycleId)
        external
        view
        override
        returns (CycleState)
    {
        return cycle[cycleId].state;
    }

    function routeHashOf(uint256 cycleId) external view returns (bytes32) {
        return cycle[cycleId].routeHash;
    }

    function facilitatorOf(uint256 cycleId) external view override returns (bytes32) {
        return cycle[cycleId].facilitatorId;
    }

    function expiresAtOf(uint256 cycleId) external view returns (uint48) {
        return cycle[cycleId].expiresAt;
    }

    function _cycle(uint256 cycleId)
        internal
        view
        returns (QETypes.Cycle storage c)
    {
        c = cycle[cycleId];
        if (c.state == CycleState.NONE) revert CycleMissing();
    }
}
