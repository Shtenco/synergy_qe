// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStabilityPool} from "../interfaces/IStabilityPool.sol";

contract MockStabilityPool is IStabilityPool {
    uint256 public available;
    uint256 public override reservedLossAsset;

    function setAvailable(uint256 value) external {
        available = value;
    }

    function availableLossBudgetUsd18() external view override returns (uint256) {
        return available;
    }
}
