// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {QEToken} from "../../contracts/token/QEToken.sol";
import {FacilitatorRegistry} from "../../contracts/FacilitatorRegistry.sol";
import {CycleEscrow} from "../../contracts/CycleEscrow.sol";
import {RiskEngine} from "../../contracts/RiskEngine.sol";
import {QEController} from "../../contracts/QEController.sol";
import {MockHardTreasury} from "../../contracts/mocks/MockHardTreasury.sol";

contract QEInvariantHandler is Test {
    QEController public immutable controller;
    CycleEscrow public immutable escrow;

    bytes32 internal constant ARB = keccak256("ARBITRAGE");
    uint256[] internal cycleIds;
    uint256 internal nonce;

    constructor(QEController controller_, CycleEscrow escrow_) {
        controller = controller_;
        escrow = escrow_;
    }

    function mint(uint96 rawAmount) external {
        uint256 amount = bound(uint256(rawAmount), 1e15, 20e18);
        bytes32 routeHash = keccak256(abi.encode("route", nonce++));

        try controller.openTemporaryCycle(
            ARB,
            amount,
            routeHash,
            address(this)
        ) returns (uint256 cycleId) {
            cycleIds.push(cycleId);
        } catch {}
    }

    function burn(uint256 seed, uint96 rawAmount) external {
        uint256 len = cycleIds.length;
        if (len == 0) return;

        uint256 cycleId = cycleIds[seed % len];
        uint256 outstanding = escrow.principalOutstanding(cycleId);
        if (outstanding == 0) return;

        uint256 amount = bound(uint256(rawAmount), 1, outstanding);
        try controller.burnTemporaryPrincipal(
            cycleId,
            address(this),
            amount
        ) {} catch {}
    }

    function cycleCount() external view returns (uint256) {
        return cycleIds.length;
    }
}

contract QECoreInvariants is StdInvariant, Test {
    QEToken internal token;
    FacilitatorRegistry internal registry;
    CycleEscrow internal escrow;
    RiskEngine internal risk;
    QEController internal controller;
    MockHardTreasury internal treasury;
    QEInvariantHandler internal handler;

    bytes32 internal constant ARB = keccak256("ARBITRAGE");

    function setUp() public {
        token = new QEToken("QE Dollar", "QED", address(this));
        registry = new FacilitatorRegistry(address(this), address(this));
        escrow = new CycleEscrow(address(this));
        treasury = new MockHardTreasury();
        treasury.setHardNAV(10_000e18);

        risk = new RiskEngine(address(this), address(treasury));
        registry.addFacilitator(ARB, 500e18, 100, 900, 10_000);
        risk.setFacilitatorRiskCap(ARB, 500e18);
        risk.setRiskInputs(
            500e18,
            500e18,
            500e18,
            10_000,
            500e18,
            500e18,
            0,
            true
        );

        controller = new QEController(
            address(this),
            address(this),
            address(token),
            address(registry),
            address(escrow),
            address(risk)
        );

        token.grantRole(token.QE_CONTROLLER_ROLE(), address(controller));
        registry.grantRole(registry.CONTROLLER_ROLE(), address(controller));
        escrow.grantRole(escrow.CONTROLLER_ROLE(), address(controller));
        controller.setGlobalCapacity(500e18);

        handler = new QEInvariantHandler(controller, escrow);
        controller.grantRole(controller.SETTLEMENT_ROLE(), address(handler));

        targetContract(address(handler));
    }

    function invariant_FourWayTemporaryDebtEquality() public view {
        uint256 temporarySupply = token.temporarySupply();
        uint256 controllerDebt = controller.totalOutstanding();
        uint256 facilitatorDebt = registry.totalOutstanding();
        uint256 cycleDebt = escrow.totalPrincipalOutstanding();

        assertEq(temporarySupply, controllerDebt);
        assertEq(controllerDebt, facilitatorDebt);
        assertEq(facilitatorDebt, cycleDebt);
        assertTrue(controller.accountingInvariantHolds());
    }

    function invariant_OutstandingNeverExceedsGlobalCapacity() public view {
        assertLe(controller.totalOutstanding(), controller.globalCapacity());
    }

    function invariant_FacilitatorNeverExceedsBucketCapacity() public view {
        (
            bool exists,
            bool enabled,
            uint128 capacity,
            uint128 outstanding,
            uint16 maxLossBps,
            uint32 maxTtl,
            uint16 riskWeightBps
        ) = registry.facilitator(ARB);

        assertTrue(exists);
        assertTrue(enabled);
        assertGt(maxLossBps, 0);
        assertGt(maxTtl, 0);
        assertGt(riskWeightBps, 0);
        assertLe(uint256(outstanding), uint256(capacity));
    }
}
