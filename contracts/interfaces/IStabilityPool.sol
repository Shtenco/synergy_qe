// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStabilityPool {
    function availableLossBudgetUsd18() external view returns (uint256);
    function reservedLossAsset() external view returns (uint256);
}
