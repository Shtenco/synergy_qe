// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOracleRouter {
    function conservativeValue(address asset, uint256 amount) external view returns (uint256 valueUsd18);
}
