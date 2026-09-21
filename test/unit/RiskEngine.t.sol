// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RiskEngine} from "../../contracts/RiskEngine.sol";
import {MockHardTreasury} from "../../contracts/mocks/MockHardTreasury.sol";
import {SystemMode} from "../../contracts/types/QETypes.sol";

contract RiskEngineTest is Test {
    RiskEngine internal risk;
    MockHardTreasury internal treasury;
    bytes32 internal constant ARB = keccak256("ARBITRAGE");

    function setUp() public {
        treasury = new MockHardTreasury();
        treasury.setHardNAV(1_000e18);

        risk = new RiskEngine(address(this), address(treasury));
        risk.setFacilitatorRiskCap(ARB, 500e18);
        risk.setRiskInputs(
            400e18, // executable depth
            300e18, // bridge capacity
            20e18,  // loss budget
            10_000, // max loss bps denominator => loss cap 20e18 here
            350e18, // oracle capacity
            250e18, // global risk cap
            0,
            true
        );
    }

    function test_CapacityIsMinimumOfIndependentLimits() public view {
        // HardNAV share default 25% => 250e18; loss budget cap = 20e18.
        assertEq(risk.capacityFor(ARB, SystemMode.NORMAL), 20e18);
    }

    function test_HigherRedemptionPressureCannotIncreaseCapacity() public {
        uint256 beforeCap = risk.capacityFor(ARB, SystemMode.NORMAL);

        risk.setRiskInputs(
            400e18, 300e18, 20e18, 10_000, 350e18, 250e18, 5_000, true
        );

        uint256 afterCap = risk.capacityFor(ARB, SystemMode.NORMAL);
        assertLe(afterCap, beforeCap);
    }

    function test_DefensiveModeCannotIncreaseCapacity() public view {
        uint256 normal = risk.capacityFor(ARB, SystemMode.NORMAL);
        uint256 defensive = risk.capacityFor(ARB, SystemMode.DEFENSIVE);
        assertLe(defensive, normal);
    }

    function test_ContractionCapacityIsZero() public view {
        assertEq(risk.capacityFor(ARB, SystemMode.CONTRACTION), 0);
        assertEq(risk.capacityFor(ARB, SystemMode.GLOBAL_SETTLEMENT), 0);
    }

    function test_UnhealthyOracleMakesCapacityZero() public {
        risk.setRiskInputs(
            400e18, 300e18, 20e18, 10_000, 350e18, 250e18, 0, false
        );
        assertEq(risk.capacityFor(ARB, SystemMode.NORMAL), 0);
    }

    function test_LowerHardNAVCannotIncreaseCapacity() public {
        uint256 beforeCap = risk.capacityFor(ARB, SystemMode.NORMAL);
        treasury.setHardNAV(10e18);
        uint256 afterCap = risk.capacityFor(ARB, SystemMode.NORMAL);
        assertLe(afterCap, beforeCap);
    }
}
