// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFacilitatorRegistry {
    function totalOutstanding() external view returns (uint256);
    function outstandingOf(bytes32 facilitatorId) external view returns (uint256);
    function remainingCapacity(bytes32 facilitatorId) external view returns (uint256);
    function increaseOutstanding(bytes32 facilitatorId, uint256 amount) external;
    function decreaseOutstanding(bytes32 facilitatorId, uint256 amount) external;
}
