// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum SystemMode {
    NORMAL,
    DEFENSIVE,
    CONTRACTION,
    GLOBAL_SETTLEMENT
}

enum CycleState {
    NONE,
    CREATED,
    MINTED,
    DEPLOYED,
    RETURNED,
    PRINCIPAL_BURNED,
    SETTLED,
    EXPIRED,
    DEFAULTED,
    EMERGENCY_SETTLED
}

enum BridgeState {
    NONE,
    SOURCE_SETTLED,
    IN_FLIGHT,
    DESTINATION_SETTLED,
    FAILED
}

library QETypes {
    struct AssetConfig {
        bool enabled;
        bool endogenous;
        uint16 haircutBps;
        uint16 maxExposureBps;
        uint48 maxOracleAge;
        address priceAdapter;
        address unwindAdapter;
    }

    struct Facilitator {
        bool enabled;
        uint128 capacity;
        uint128 outstanding;
        uint16 maxLossBps;
        uint32 maxTtl;
        uint16 riskWeightBps;
    }

    struct Cycle {
        bytes32 facilitatorId;
        CycleState state;
        uint128 principalMinted;
        uint128 principalBurned;
        uint128 externalValueInUsd18;
        uint128 externalValueOutUsd18;
        int128 realizedPnlUsd18;
        uint48 openedAt;
        uint48 expiresAt;
        bytes32 routeHash;
    }

    struct BridgeClaim {
        BridgeState state;
        uint64 sourceChainId;
        uint64 destinationChainId;
        address asset;
        uint128 nominalAmount;
        uint128 sourceHardValueUsd18;
        uint48 openedAt;
        uint48 expectedFinality;
        bytes32 destinationRef;
    }

    struct RiskSnapshot {
        uint256 hardNavUsd18;
        uint256 redeemableLiabilitiesUsd18;
        uint256 executableDepthUsd18;
        uint256 bridgeCapacityUsd18;
        uint256 lossBudgetUsd18;
        uint256 oracleCapacityUsd18;
        uint256 globalCapacityUsd18;
        uint256 redemptionPressureBps;
        SystemMode mode;
    }

    struct ProfitWaterfallResult {
        uint256 hardCrReserve;
        uint256 stabilityReserve;
        uint256 bridgeReserve;
        uint256 operatingCosts;
        uint256 distributableSurplus;
    }
}
