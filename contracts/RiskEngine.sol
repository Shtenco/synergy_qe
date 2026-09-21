// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IHardTreasury} from "./interfaces/IHardTreasury.sol";
import {IRiskEngine} from "./interfaces/IRiskEngine.sol";
import {IStabilityPool} from "./interfaces/IStabilityPool.sol";
import {SystemMode} from "./types/QETypes.sol";

contract RiskEngine is AccessControl, IRiskEngine {
    bytes32 public constant RISK_REPORTER_ROLE = keccak256("RISK_REPORTER_ROLE");

    uint256 internal constant BPS = 10_000;

    IHardTreasury public immutable hardTreasury;
    IStabilityPool public stabilityPool;

    uint16 public hardNavCapacityBps = 2_500;
    uint16 public defensiveMultiplierBps = 5_000;

    uint256 public executableDepthUsd18;
    uint256 public bridgeCapacityUsd18;
    uint256 public lossBudgetUsd18;
    uint16 public maxLossBps;
    uint256 public oracleCapacityUsd18;
    uint256 public globalRiskCapUsd18;
    uint16 public redemptionPressureBps;
    bool public oracleHealthy;

    mapping(bytes32 => uint256) public facilitatorRiskCap;

    error ZeroAddress();
    error InvalidBps();

    constructor(address admin, address hardTreasury_) {
        if (admin == address(0) || hardTreasury_ == address(0)) revert ZeroAddress();
        hardTreasury = IHardTreasury(hardTreasury_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RISK_REPORTER_ROLE, admin);
    }

    function setStabilityPool(address stabilityPool_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (stabilityPool_ == address(0)) revert ZeroAddress();
        stabilityPool = IStabilityPool(stabilityPool_);
    }

    function setFacilitatorRiskCap(bytes32 facilitatorId, uint256 cap)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        facilitatorRiskCap[facilitatorId] = cap;
    }

    function setPolicy(
        uint16 hardNavCapacityBps_,
        uint16 defensiveMultiplierBps_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (
            hardNavCapacityBps_ > BPS ||
            defensiveMultiplierBps_ > BPS
        ) revert InvalidBps();

        hardNavCapacityBps = hardNavCapacityBps_;
        defensiveMultiplierBps = defensiveMultiplierBps_;
    }

    function setRiskInputs(
        uint256 executableDepthUsd18_,
        uint256 bridgeCapacityUsd18_,
        uint256 lossBudgetUsd18_,
        uint16 maxLossBps_,
        uint256 oracleCapacityUsd18_,
        uint256 globalRiskCapUsd18_,
        uint16 redemptionPressureBps_,
        bool oracleHealthy_
    ) external onlyRole(RISK_REPORTER_ROLE) {
        if (
            maxLossBps_ == 0 ||
            maxLossBps_ > BPS ||
            redemptionPressureBps_ > BPS
        ) revert InvalidBps();

        executableDepthUsd18 = executableDepthUsd18_;
        bridgeCapacityUsd18 = bridgeCapacityUsd18_;
        lossBudgetUsd18 = lossBudgetUsd18_;
        maxLossBps = maxLossBps_;
        oracleCapacityUsd18 = oracleCapacityUsd18_;
        globalRiskCapUsd18 = globalRiskCapUsd18_;
        redemptionPressureBps = redemptionPressureBps_;
        oracleHealthy = oracleHealthy_;
    }

    function capacityFor(bytes32 facilitatorId, SystemMode mode)
        external
        view
        override
        returns (uint256)
    {
        if (
            mode == SystemMode.CONTRACTION ||
            mode == SystemMode.GLOBAL_SETTLEMENT ||
            !oracleHealthy
        ) return 0;

        uint256 hardNavCap =
            (hardTreasury.hardNAV() * hardNavCapacityBps) / BPS;

        uint256 effectiveLossBudget = address(stabilityPool) == address(0)
            ? lossBudgetUsd18
            : stabilityPool.availableLossBudgetUsd18();

        uint256 lossBudgetCap =
            maxLossBps == 0
                ? 0
                : (effectiveLossBudget * BPS) / uint256(maxLossBps);

        uint256 cap = _min(
            facilitatorRiskCap[facilitatorId],
            _min(
                hardNavCap,
                _min(
                    executableDepthUsd18,
                    _min(
                        bridgeCapacityUsd18,
                        _min(
                            lossBudgetCap,
                            _min(oracleCapacityUsd18, globalRiskCapUsd18)
                        )
                    )
                )
            )
        );

        cap = (cap * (BPS - redemptionPressureBps)) / BPS;

        if (mode == SystemMode.DEFENSIVE) {
            cap = (cap * defensiveMultiplierBps) / BPS;
        }

        return cap;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
