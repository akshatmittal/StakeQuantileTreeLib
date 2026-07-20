// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {MAX_PRICE} from "../../contracts/Constants.sol";
import {StakeQuantileTreeLib} from "../../contracts/StakeQuantileTreeLib.sol";

/// @notice Verification-only external surface and state instrumentation for StakeQuantileTreeLib.
contract StakeQuantileTreeHarness {
    uint256 private constant RADIX_LEVELS = 4;

    mapping(uint256 key => uint256 packed) private _tree;
    uint256 private _trackedTotal;

    function addRaw(uint16 code, uint256 amount) external {
        if (amount > type(uint128).max || amount > type(uint128).max - _trackedTotal) {
            revert StakeQuantileTreeLib.StakeQuantileTreeLib__SumOverflow();
        }
        StakeQuantileTreeLib.addRaw(_tree, code, amount);
        _trackedTotal += amount;
    }

    /// @dev Exposes the library without the tracked-total caller invariant for rollback proofs.
    function addRawUnchecked(uint16 code, uint256 amount) external {
        StakeQuantileTreeLib.addRaw(_tree, code, amount);
    }

    function trackedTotal() external view returns (uint256) {
        return _trackedTotal;
    }

    function rawTotal() external view returns (uint256) {
        return StakeQuantileTreeLib.rawTotal(_tree);
    }

    function rawQuantile(uint256 rank, uint256 total) external view returns (uint16) {
        return StakeQuantileTreeLib.rawQuantile(_tree, rank, total);
    }

    function rawLowerMedian() external view returns (uint16 code, uint256 support) {
        return StakeQuantileTreeLib.rawLowerMedian(_tree);
    }

    function packedWord(uint256 key) external view returns (uint256) {
        return _tree[key];
    }

    function packedPairTotal(uint256 key) external view returns (uint256) {
        uint256 word = _tree[key];
        return (word & type(uint128).max) + (word >> 128);
    }

    function childStake(uint256 level, uint256 prefix, uint256 child) external view returns (uint256) {
        if (!validNode(level, prefix, child)) {
            revert StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidCode();
        }
        uint256 word = _tree[rawKey(level, prefix, child)];
        return (word >> ((child & 1) * 128)) & type(uint128).max;
    }

    function crossingChild(uint256 level, uint256 prefix, uint256 rank)
        external
        view
        returns (uint256 nextPrefix, uint256 nextRank)
    {
        return StakeQuantileTreeLib._crossingChild(_tree, level, prefix, rank);
    }

    function nodeTotal(uint256 level, uint256 prefix) external view returns (uint256 total) {
        for (uint256 pair; pair < 8; pair++) {
            uint256 word = _tree[rawKey(level, prefix, pair << 1)];
            total += (word & type(uint128).max) + (word >> 128);
        }
    }

    function nodeStakeBefore(uint256 level, uint256 prefix, uint256 child) external view returns (uint256 total) {
        for (uint256 pair; pair < child / 2; pair++) {
            uint256 word = _tree[rawKey(level, prefix, pair << 1)];
            total += (word & type(uint128).max) + (word >> 128);
        }
        if (child & 1 != 0) {
            total += _tree[rawKey(level, prefix, child)] & type(uint128).max;
        }
    }

    function rawKey(uint256 level, uint256 prefix, uint256 child) public pure returns (uint256) {
        return (level << 16) | (prefix << 3) | (child >> 1);
    }

    function pathPrefix(uint16 code, uint256 level) public pure returns (uint256) {
        if (level >= RADIX_LEVELS) {
            revert StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidCode();
        }
        return level == 0 ? 0 : uint256(code) >> (16 - level * 4);
    }

    function pathChild(uint16 code, uint256 level) public pure returns (uint256) {
        if (level >= RADIX_LEVELS) {
            revert StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidCode();
        }
        return (uint256(code) >> (12 - level * 4)) & 0xF;
    }

    function pathKey(uint16 code, uint256 level) external pure returns (uint256) {
        return rawKey(level, pathPrefix(code, level), pathChild(code, level));
    }

    function validNode(uint256 level, uint256 prefix, uint256 child) public pure returns (bool) {
        return level < RADIX_LEVELS && child < 16 && prefix < (uint256(1) << (level * 4));
    }

    function isOnPath(uint16 code, uint256 level, uint256 prefix, uint256 child) external pure returns (bool) {
        if (!validNode(level, prefix, child)) {
            return false;
        }
        uint256 expectedPrefix = level == 0 ? 0 : uint256(code) >> (16 - level * 4);
        uint256 expectedChild = (uint256(code) >> (12 - level * 4)) & 0xF;
        return prefix == expectedPrefix && child == expectedChild;
    }

    function lowerMedianRank(uint256 total) external pure returns (uint256) {
        return StakeQuantileTreeLib.lowerMedianRank(total);
    }

    function weightCode(uint256 weight) external pure returns (uint16) {
        return StakeQuantileTreeLib.weightCode(weight);
    }

    function weightLow(uint16 code) external pure returns (uint256) {
        return StakeQuantileTreeLib.weightLow(code);
    }

    function weightHigh(uint16 code) external pure returns (uint256) {
        return StakeQuantileTreeLib.weightHigh(code);
    }

    function weightRepresentative(uint16 code) external pure returns (uint256) {
        return StakeQuantileTreeLib.weightRepresentative(code);
    }

    function priceCode(uint256 price) external pure returns (uint16) {
        return StakeQuantileTreeLib.priceCode(price);
    }

    function priceLow(uint16 code) external pure returns (uint256) {
        return StakeQuantileTreeLib.priceLow(code);
    }

    function priceHigh(uint16 code) external pure returns (uint256) {
        return StakeQuantileTreeLib.priceHigh(code);
    }

    function priceRepresentative(uint16 code) external pure returns (uint256) {
        return StakeQuantileTreeLib.priceRepresentative(code);
    }

    function priceCodeHasIntegerBucket(uint16 code) external pure returns (bool) {
        uint256 exponent = uint256(code) >> 8;
        uint256 fraction = uint256(code) & 0xFF;
        return exponent >= 8 || fraction % (uint256(1) << (8 - exponent)) == 0;
    }

    function maxPrice() external pure returns (uint256) {
        return MAX_PRICE;
    }
}
