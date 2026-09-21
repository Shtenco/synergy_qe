// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {QEToken} from "../../contracts/token/QEToken.sol";
import {FacilitatorRegistry} from "../../contracts/FacilitatorRegistry.sol";
import {CycleEscrow} from "../../contracts/CycleEscrow.sol";
import {RiskEngine} from "../../contracts/RiskEngine.sol";
import {QEController} from "../../contracts/QEController.sol";
import {MockHardTreasury} from "../../contracts/mocks/MockHardTreasury.sol";
import {SystemMode} from "../../contracts/types/QETypes.sol";

contract QEControllerTest is Test {
    QEToken internal token;
    FacilitatorRegistry internal registry;
    CycleEscrow internal escrow;
    RiskEngine internal risk;
    QEController internal controller;
    MockHardTreasury internal treasury;

    bytes32 internal constant ARB = keccak256("ARBITRAGE");
    address internal alice = address(0xA11CE);

    function setUp() public {
        token = new QEToken("QE Dollar", "QED", address(this));
        registry = new FacilitatorRegistry(address(this), address(this));
        escrow = new CycleEscrow(address(this));
        treasury = new MockHardTreasury();
        treasury.setHardNAV(1_000e18);
        risk = new RiskEngine(address(this), address(treasury));

        registry.addFacilitator(ARB, 200e18, 100, 900, 10_000);
        risk.setFacilitatorRiskCap(ARB, 200e18);
        risk.setRiskInputs(
            200e18,
            200e18,
            200e18,
            10_000,
            200e18,
            200e18,
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
        controller.setGlobalCapacity(150e18);
    }

    function test_OpenCycleMaintainsFourWayDebtEquality() public {
        controller.openTemporaryCycle(ARB, 40e18, keccak256("route-1"), alice);

        assertEq(token.temporarySupply(), 40e18);
        assertEq(controller.totalOutstanding(), 40e18);
        assertEq(registry.totalOutstanding(), 40e18);
        assertEq(escrow.totalPrincipalOutstanding(), 40e18);
    }

    function test_MultipleCyclesAndPartialBurnKeepEquality() public {
        uint256 c1 = controller.openTemporaryCycle(
            ARB, 40e18, keccak256("route-1"), alice
        );
        controller.openTemporaryCycle(
            ARB, 30e18, keccak256("route-2"), alice
        );

        controller.burnTemporaryPrincipal(c1, alice, 15e18);

        assertEq(token.temporarySupply(), 55e18);
        assertEq(controller.totalOutstanding(), 55e18);
        assertEq(registry.totalOutstanding(), 55e18);
        assertEq(escrow.totalPrincipalOutstanding(), 55e18);
    }

    function test_GlobalCapacityBlocksMint() public {
        controller.setGlobalCapacity(10e18);
        vm.expectRevert();
        controller.openTemporaryCycle(ARB, 11e18, keccak256("route"), alice);
    }

    function test_RiskCapacityBlocksMint() public {
        risk.setFacilitatorRiskCap(ARB, 5e18);
        vm.expectRevert();
        controller.openTemporaryCycle(ARB, 6e18, keccak256("route"), alice);
    }

    function test_ContractionBlocksNewMintButAllowsBurn() public {
        uint256 cycleId = controller.openTemporaryCycle(
            ARB, 20e18, keccak256("route"), alice
        );

        controller.setMode(SystemMode.CONTRACTION);

        vm.expectRevert();
        controller.openTemporaryCycle(ARB, 1e18, keccak256("route-2"), alice);

        controller.burnTemporaryPrincipal(cycleId, alice, 20e18);

        assertEq(token.temporarySupply(), 0);
        assertEq(controller.totalOutstanding(), 0);
        assertEq(registry.totalOutstanding(), 0);
        assertEq(escrow.totalPrincipalOutstanding(), 0);
    }
}
