// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOracleRouter} from "./interfaces/IOracleRouter.sol";
import {IHardTreasury} from "./interfaces/IHardTreasury.sol";
import {IStabilityPool} from "./interfaces/IStabilityPool.sol";

contract StabilityPool is AccessControl, IStabilityPool {
    using SafeERC20 for IERC20;

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");

    IERC20 public immutable lossAsset;
    IOracleRouter public immutable oracleRouter;
    IHardTreasury public immutable hardTreasury;

    uint256 public override reservedLossAsset;

    error ZeroAddress();
    error EndogenousLossAsset();
    error InsufficientFreeBalance();
    error InsufficientReservedBalance();
    error ZeroAmount();

    constructor(
        address admin,
        address guardian,
        address lossAsset_,
        address oracleRouter_,
        address hardTreasury_
    ) {
        if (
            admin == address(0) ||
            guardian == address(0) ||
            lossAsset_ == address(0) ||
            oracleRouter_ == address(0) ||
            hardTreasury_ == address(0)
        ) revert ZeroAddress();

        hardTreasury = IHardTreasury(hardTreasury_);
        if (hardTreasury.isEndogenous(lossAsset_)) revert EndogenousLossAsset();

        lossAsset = IERC20(lossAsset_);
        oracleRouter = IOracleRouter(oracleRouter_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, guardian);
        _grantRole(SETTLEMENT_ROLE, admin);
    }

    function fund(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        lossAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function reserveLossBudget(uint256 amount)
        external
        onlyRole(SETTLEMENT_ROLE)
    {
        if (amount == 0) revert ZeroAmount();

        uint256 balance = lossAsset.balanceOf(address(this));
        if (reservedLossAsset + amount > balance) {
            revert InsufficientFreeBalance();
        }

        reservedLossAsset += amount;
    }

    function releaseLossBudget(uint256 amount)
        external
        onlyRole(SETTLEMENT_ROLE)
    {
        if (amount == 0) revert ZeroAmount();
        if (amount > reservedLossAsset) revert InsufficientReservedBalance();
        reservedLossAsset -= amount;
    }

    function absorbLoss(address recipient, uint256 amount)
        external
        onlyRole(SETTLEMENT_ROLE)
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > reservedLossAsset) revert InsufficientReservedBalance();

        reservedLossAsset -= amount;
        lossAsset.safeTransfer(recipient, amount);
    }

    function withdrawExcess(address recipient, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 balance = lossAsset.balanceOf(address(this));
        uint256 free = balance > reservedLossAsset
            ? balance - reservedLossAsset
            : 0;

        if (amount > free) revert InsufficientFreeBalance();
        lossAsset.safeTransfer(recipient, amount);
    }

    function availableLossBudgetUsd18()
        external
        view
        override
        returns (uint256)
    {
        uint256 balance = lossAsset.balanceOf(address(this));
        if (reservedLossAsset >= balance) return 0;

        return oracleRouter.conservativeValue(
            address(lossAsset),
            balance - reservedLossAsset
        );
    }
}
