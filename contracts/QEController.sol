// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IQEToken} from "./interfaces/IQEToken.sol";
import {IFacilitatorRegistry} from "./interfaces/IFacilitatorRegistry.sol";
import {ICycleEscrow} from "./interfaces/ICycleEscrow.sol";
import {IRiskEngine} from "./interfaces/IRiskEngine.sol";
import {IQEController} from "./interfaces/IQEController.sol";
import {SystemMode} from "./types/QETypes.sol";

contract QEController is AccessControl, IQEController {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");

    IQEToken public immutable token;
    IFacilitatorRegistry public immutable facilitatorRegistry;
    ICycleEscrow public immutable cycleEscrow;
    IRiskEngine public immutable riskEngine;

    uint256 public globalCapacity;
    uint256 public override totalOutstanding;
    uint256 public nextCycleId = 1;
    SystemMode public override mode;

    error ZeroAddress();
    error ZeroAmount();
    error MintDisabled();
    error GlobalCapacityExceeded();
    error RiskCapacityExceeded();
    error InvalidModeTransition();
    error AccountingMismatch();

    constructor(
        address admin,
        address guardian,
        address token_,
        address facilitatorRegistry_,
        address cycleEscrow_,
        address riskEngine_
    ) {
        if (
            admin == address(0) ||
            guardian == address(0) ||
            token_ == address(0) ||
            facilitatorRegistry_ == address(0) ||
            cycleEscrow_ == address(0) ||
            riskEngine_ == address(0)
        ) revert ZeroAddress();

        token = IQEToken(token_);
        facilitatorRegistry = IFacilitatorRegistry(facilitatorRegistry_);
        cycleEscrow = ICycleEscrow(cycleEscrow_);
        riskEngine = IRiskEngine(riskEngine_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, guardian);
        _grantRole(SETTLEMENT_ROLE, admin);

        mode = SystemMode.NORMAL;
    }

    function setGlobalCapacity(uint256 newCapacity)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newCapacity < totalOutstanding) revert GlobalCapacityExceeded();
        globalCapacity = newCapacity;
    }

    function setMode(SystemMode newMode)
        external
        onlyRole(GUARDIAN_ROLE)
    {
        if (uint8(newMode) < uint8(mode)) revert InvalidModeTransition();
        mode = newMode;
    }

    function openTemporaryCycle(
        bytes32 facilitatorId,
        uint256 requestedAmount,
        bytes32 routeHash,
        address receiver
    ) external override returns (uint256 cycleId) {
        if (requestedAmount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (
            mode == SystemMode.CONTRACTION ||
            mode == SystemMode.GLOBAL_SETTLEMENT
        ) revert MintDisabled();

        if (totalOutstanding + requestedAmount > globalCapacity) {
            revert GlobalCapacityExceeded();
        }

        uint256 riskCapacity = riskEngine.capacityFor(facilitatorId, mode);
        uint256 facilitatorOutstanding =
            facilitatorRegistry.outstandingOf(facilitatorId);

        if (facilitatorOutstanding + requestedAmount > riskCapacity) {
            revert RiskCapacityExceeded();
        }

        uint32 ttl = facilitatorRegistry.maxTtlOf(facilitatorId);
        cycleId = nextCycleId++;

        facilitatorRegistry.increaseOutstanding(facilitatorId, requestedAmount);
        cycleEscrow.createCycle(
            cycleId,
            facilitatorId,
            requestedAmount,
            ttl,
            routeHash
        );
        token.qeMint(receiver, requestedAmount);
        totalOutstanding += requestedAmount;

        _assertAccounting();
    }

    function burnTemporaryPrincipal(
        uint256 cycleId,
        address from,
        uint256 amount
    ) external override onlyRole(SETTLEMENT_ROLE) {
        if (from == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        bytes32 facilitatorId = cycleEscrow.facilitatorOf(cycleId);

        token.burnFromController(from, amount);
        cycleEscrow.recordPrincipalBurn(cycleId, amount);
        facilitatorRegistry.decreaseOutstanding(facilitatorId, amount);
        totalOutstanding -= amount;

        _assertAccounting();
    }

    function accountingInvariantHolds() external view returns (bool) {
        return
            token.temporarySupply() == totalOutstanding &&
            facilitatorRegistry.totalOutstanding() == totalOutstanding &&
            cycleEscrow.totalPrincipalOutstanding() == totalOutstanding;
    }

    function _assertAccounting() internal view {
        if (
            token.temporarySupply() != totalOutstanding ||
            facilitatorRegistry.totalOutstanding() != totalOutstanding ||
            cycleEscrow.totalPrincipalOutstanding() != totalOutstanding
        ) revert AccountingMismatch();
    }
}
