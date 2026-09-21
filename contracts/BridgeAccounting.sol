// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {BridgeState, QETypes} from "./types/QETypes.sol";
import {IBridgeAccounting} from "./interfaces/IBridgeAccounting.sol";

contract BridgeAccounting is AccessControl, IBridgeAccounting {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    uint256 internal constant BPS = 10_000;

    mapping(uint256 => QETypes.BridgeClaim) public claim;
    mapping(uint256 => uint128) public destinationHardValueUsd18;

    uint16 public pendingHaircutBps;
    uint48 public maxFinalityAge;

    error ZeroAddress();
    error InvalidBps();
    error ClaimExists();
    error ClaimMissing();
    error InvalidState();
    error ValueTooLarge();

    constructor(
        address admin,
        address guardian,
        uint16 pendingHaircutBps_,
        uint48 maxFinalityAge_
    ) {
        if (admin == address(0) || guardian == address(0)) revert ZeroAddress();
        if (pendingHaircutBps_ > BPS) revert InvalidBps();

        pendingHaircutBps = pendingHaircutBps_;
        maxFinalityAge = maxFinalityAge_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, guardian);
    }

    function openClaim(
        uint256 claimId,
        uint64 sourceChainId,
        uint64 destinationChainId,
        address asset,
        uint256 nominalAmount,
        uint256 sourceHardValueUsd18,
        uint48 expectedFinality
    ) external onlyRole(BRIDGE_ROLE) {
        if (claim[claimId].state != BridgeState.NONE) revert ClaimExists();
        if (asset == address(0)) revert ZeroAddress();
        if (
            nominalAmount > type(uint128).max ||
            sourceHardValueUsd18 > type(uint128).max
        ) revert ValueTooLarge();

        claim[claimId] = QETypes.BridgeClaim({
            state: BridgeState.SOURCE_SETTLED,
            sourceChainId: sourceChainId,
            destinationChainId: destinationChainId,
            asset: asset,
            nominalAmount: uint128(nominalAmount),
            sourceHardValueUsd18: uint128(sourceHardValueUsd18),
            openedAt: uint48(block.timestamp),
            expectedFinality: expectedFinality,
            destinationRef: bytes32(0)
        });
    }

    function markInFlight(uint256 claimId) external onlyRole(BRIDGE_ROLE) {
        QETypes.BridgeClaim storage c = _claim(claimId);
        if (c.state != BridgeState.SOURCE_SETTLED) revert InvalidState();
        c.state = BridgeState.IN_FLIGHT;
    }

    function markDestinationSettled(
        uint256 claimId,
        uint256 destinationHardValue,
        bytes32 destinationRef
    ) external onlyRole(BRIDGE_ROLE) {
        QETypes.BridgeClaim storage c = _claim(claimId);
        if (c.state != BridgeState.IN_FLIGHT) revert InvalidState();
        if (destinationHardValue > type(uint128).max) revert ValueTooLarge();

        destinationHardValueUsd18[claimId] = uint128(destinationHardValue);
        c.destinationRef = destinationRef;
        c.state = BridgeState.DESTINATION_SETTLED;
    }

    function markFailed(uint256 claimId) external onlyRole(BRIDGE_ROLE) {
        QETypes.BridgeClaim storage c = _claim(claimId);
        if (
            c.state != BridgeState.IN_FLIGHT &&
            c.state != BridgeState.SOURCE_SETTLED
        ) revert InvalidState();

        c.state = BridgeState.FAILED;
    }

    function claimHardValue(uint256 claimId)
        external
        view
        override
        returns (uint256)
    {
        QETypes.BridgeClaim storage c = claim[claimId];

        if (c.state == BridgeState.SOURCE_SETTLED) {
            return c.sourceHardValueUsd18;
        }

        if (c.state == BridgeState.IN_FLIGHT) {
            if (block.timestamp > uint256(c.openedAt) + uint256(maxFinalityAge)) {
                return 0;
            }
            return (uint256(c.sourceHardValueUsd18) * pendingHaircutBps) / BPS;
        }

        if (c.state == BridgeState.DESTINATION_SETTLED) {
            return destinationHardValueUsd18[claimId];
        }

        return 0;
    }

    function stateOf(uint256 claimId)
        external
        view
        override
        returns (BridgeState)
    {
        return claim[claimId].state;
    }

    function setPendingHaircut(uint16 newHaircutBps)
        external
        onlyRole(GUARDIAN_ROLE)
    {
        if (newHaircutBps > pendingHaircutBps || newHaircutBps > BPS) {
            revert InvalidBps();
        }
        pendingHaircutBps = newHaircutBps;
    }

    function _claim(uint256 claimId)
        internal
        view
        returns (QETypes.BridgeClaim storage c)
    {
        c = claim[claimId];
        if (c.state == BridgeState.NONE) revert ClaimMissing();
    }
}
