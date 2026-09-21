// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPriceAdapter {
    function getPrice(address asset) external view returns (uint256 priceUsd18, uint48 updatedAt);
}
