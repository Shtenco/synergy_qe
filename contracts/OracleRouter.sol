// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPriceAdapter} from "./interfaces/IPriceAdapter.sol";
import {IUnwindAdapter} from "./interfaces/IUnwindAdapter.sol";
import {IOracleRouter} from "./interfaces/IOracleRouter.sol";

contract OracleRouter is AccessControl, IOracleRouter {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    uint256 internal constant BPS = 10_000;

    struct OracleConfig {
        bool enabled;
        uint8 decimals;
        address independentOracle;
        address externalTwap;
        address unwindAdapter;
        uint48 maxAge;
        uint16 maxDivergenceBps;
    }

    mapping(address => OracleConfig) public config;

    error ZeroAddress();
    error InvalidDecimals();
    error InvalidBps();

    constructor(address admin, address guardian) {
        if (admin == address(0) || guardian == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, guardian);
    }

    function registerAsset(
        address asset,
        uint8 decimals_,
        address independentOracle,
        address externalTwap,
        address unwindAdapter,
        uint48 maxAge,
        uint16 maxDivergenceBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (
            asset == address(0) ||
            independentOracle == address(0) ||
            externalTwap == address(0) ||
            unwindAdapter == address(0)
        ) revert ZeroAddress();
        if (decimals_ > 18) revert InvalidDecimals();
        if (maxDivergenceBps > BPS) revert InvalidBps();

        config[asset] = OracleConfig({
            enabled: true,
            decimals: decimals_,
            independentOracle: independentOracle,
            externalTwap: externalTwap,
            unwindAdapter: unwindAdapter,
            maxAge: maxAge,
            maxDivergenceBps: maxDivergenceBps
        });
    }

    function disableAsset(address asset) external onlyRole(GUARDIAN_ROLE) {
        config[asset].enabled = false;
    }

    function conservativeValue(address asset, uint256 amount)
        external
        view
        returns (uint256 valueUsd18)
    {
        OracleConfig memory c = config[asset];
        if (!c.enabled || amount == 0) return 0;

        (uint256 oraclePrice, uint48 oracleUpdated) =
            IPriceAdapter(c.independentOracle).getPrice(asset);
        (uint256 twapPrice, uint48 twapUpdated) =
            IPriceAdapter(c.externalTwap).getPrice(asset);

        if (oraclePrice == 0 || twapPrice == 0) return 0;
        if (_isStale(oracleUpdated, c.maxAge) || _isStale(twapUpdated, c.maxAge)) return 0;
        if (_divergenceBps(oraclePrice, twapPrice) > c.maxDivergenceBps) return 0;

        uint256 scale = 10 ** uint256(c.decimals);
        uint256 oracleValue = (amount * oraclePrice) / scale;
        uint256 twapValue = (amount * twapPrice) / scale;
        uint256 unwindValue =
            IUnwindAdapter(c.unwindAdapter).quoteValue(asset, amount);

        if (unwindValue == 0) return 0;
        return _min(_min(oracleValue, twapValue), unwindValue);
    }

    function _isStale(uint48 updatedAt, uint48 maxAge) internal view returns (bool) {
        if (updatedAt == 0 || updatedAt > block.timestamp) return true;
        return block.timestamp - uint256(updatedAt) > uint256(maxAge);
    }

    function _divergenceBps(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 high = a > b ? a : b;
        uint256 low = a > b ? b : a;
        if (low == 0) return type(uint256).max;
        return ((high - low) * BPS) / low;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
