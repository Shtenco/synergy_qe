// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOracleRouter} from "./interfaces/IOracleRouter.sol";
import {IHardTreasury} from "./interfaces/IHardTreasury.sol";

contract HardTreasury is AccessControl, IHardTreasury {
    using SafeERC20 for IERC20;

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant LIABILITY_ROLE = keccak256("LIABILITY_ROLE");
    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");

    uint256 internal constant BPS = 10_000;

    struct AssetConfig {
        bool enabled;
        uint16 haircutBps;
        uint16 maxExposureBps;
    }

    IOracleRouter public immutable oracleRouter;

    mapping(address => AssetConfig) public assetConfig;
    mapping(address => bool) public endogenousAsset;
    mapping(address => uint256) public reservedForSettlement;
    address[] public registeredAssets;

    uint256 public override externalLiabilitiesUsd18;
    uint256 public override expectedExitCostsUsd18;

    error ZeroAddress();
    error InvalidBps();
    error EndogenousAssetForbidden(address asset);
    error AssetNotEnabled(address asset);
    error ReservationExceedsBalance();
    error LiabilityUnderflow();

    constructor(
        address admin,
        address guardian,
        address oracleRouter_,
        address[] memory endogenousAssets
    ) {
        if (admin == address(0) || guardian == address(0) || oracleRouter_ == address(0)) {
            revert ZeroAddress();
        }

        oracleRouter = IOracleRouter(oracleRouter_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, guardian);
        _grantRole(LIABILITY_ROLE, admin);
        _grantRole(SETTLEMENT_ROLE, admin);

        for (uint256 i; i < endogenousAssets.length; ++i) {
            if (endogenousAssets[i] == address(0)) revert ZeroAddress();
            endogenousAsset[endogenousAssets[i]] = true;
        }
    }

    function registerAsset(
        address asset,
        uint16 haircutBps,
        uint16 maxExposureBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (asset == address(0)) revert ZeroAddress();
        if (endogenousAsset[asset]) revert EndogenousAssetForbidden(asset);
        if (haircutBps > BPS || maxExposureBps > BPS) revert InvalidBps();

        if (!assetConfig[asset].enabled) {
            registeredAssets.push(asset);
        }

        assetConfig[asset] = AssetConfig({
            enabled: true,
            haircutBps: haircutBps,
            maxExposureBps: maxExposureBps
        });
    }

    function disableAsset(address asset) external onlyRole(GUARDIAN_ROLE) {
        assetConfig[asset].enabled = false;
    }

    function hardValue(address asset) public view override returns (uint256) {
        AssetConfig memory c = assetConfig[asset];
        if (!c.enabled || endogenousAsset[asset]) return 0;

        uint256 balance = IERC20(asset).balanceOf(address(this));
        uint256 reserved = reservedForSettlement[asset];
        if (reserved >= balance) return 0;

        uint256 available = balance - reserved;
        uint256 executableValue = oracleRouter.conservativeValue(asset, available);
        return (executableValue * c.haircutBps) / BPS;
    }

    function grossHardAssets() public view returns (uint256 total) {
        for (uint256 i; i < registeredAssets.length; ++i) {
            total += hardValue(registeredAssets[i]);
        }
    }

    function hardNAV() public view override returns (uint256) {
        uint256 gross = grossHardAssets();
        uint256 deductions = externalLiabilitiesUsd18 + expectedExitCostsUsd18;
        if (deductions >= gross) return 0;
        return gross - deductions;
    }

    function reserveForSettlement(address asset, uint256 amount)
        external
        onlyRole(SETTLEMENT_ROLE)
    {
        if (!assetConfig[asset].enabled) revert AssetNotEnabled(asset);
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (reservedForSettlement[asset] + amount > balance) {
            revert ReservationExceedsBalance();
        }
        reservedForSettlement[asset] += amount;
    }

    function releaseSettlementReserve(address asset, uint256 amount)
        external
        onlyRole(SETTLEMENT_ROLE)
    {
        uint256 reserved = reservedForSettlement[asset];
        if (amount > reserved) revert ReservationExceedsBalance();
        reservedForSettlement[asset] = reserved - amount;
    }

    function increaseExternalLiability(uint256 amount)
        external
        onlyRole(LIABILITY_ROLE)
    {
        externalLiabilitiesUsd18 += amount;
    }

    function decreaseExternalLiability(uint256 amount)
        external
        onlyRole(LIABILITY_ROLE)
    {
        if (amount > externalLiabilitiesUsd18) revert LiabilityUnderflow();
        externalLiabilitiesUsd18 -= amount;
    }

    function setExpectedExitCosts(uint256 amount)
        external
        onlyRole(SETTLEMENT_ROLE)
    {
        expectedExitCostsUsd18 = amount;
    }

    function transferApprovedAsset(address asset, address to, uint256 amount)
        external
        onlyRole(SETTLEMENT_ROLE)
    {
        if (!assetConfig[asset].enabled) revert AssetNotEnabled(asset);
        if (to == address(0)) revert ZeroAddress();

        uint256 balance = IERC20(asset).balanceOf(address(this));
        uint256 reserved = reservedForSettlement[asset];
        if (amount > balance - reserved) revert ReservationExceedsBalance();

        IERC20(asset).safeTransfer(to, amount);
    }

    function registeredAssetCount() external view returns (uint256) {
        return registeredAssets.length;
    }
}
