// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MAX_PRICE, WEIGHT_BUCKET_WIDTH} from "./Constants.sol";

/**
 * @title StakeQuantileTreeLib
 * @notice Fixed-depth cumulative radix trees for exact stake-weighted quantiles.
 * @dev A code is four hexadecimal nibbles. Each node packs two uint128 child sums per storage word.
 *      The library is internal-only so callers retain ownership of mappings.
 */
library StakeQuantileTreeLib {
    uint256 internal constant WEIGHT_BUCKET_COUNT = 10_000;
    uint256 internal constant RADIX_LEVELS = 4;
    uint256 internal constant RADIX_MASK = 0xF;
    uint256 internal constant MAX_PRICE_EXPONENT = 149;

    error StakeQuantileTreeLib__InvalidAmount();
    error StakeQuantileTreeLib__InvalidCode();
    error StakeQuantileTreeLib__InvalidPrice();
    error StakeQuantileTreeLib__InvalidRank();
    error StakeQuantileTreeLib__SumOverflow();
    error StakeQuantileTreeLib__NoCrossingChild();

    // ==== Tree updates ====

    /// Adds stake to a raw-only tree. Each child sum is stored as a uint128.
    /// @dev The caller must keep the aggregate tree support within uint128 and exclusively own `tree`.
    function addRaw(mapping(uint256 key => uint256 packed) storage tree, uint16 code, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        if (amount > type(uint128).max) {
            revert StakeQuantileTreeLib__SumOverflow();
        }

        uint256 prefix;
        for (uint256 level; level < RADIX_LEVELS; level++) {
            uint256 child = (uint256(code) >> (12 - level * 4)) & RADIX_MASK;
            uint256 key = _rawKey(level, prefix, child);
            uint256 word = tree[key];
            uint256 shift = (child & 1) * 128;
            uint256 current = (word >> shift) & type(uint128).max;
            uint256 next = current + amount;
            if (next > type(uint128).max) {
                revert StakeQuantileTreeLib__SumOverflow();
            }

            uint256 mask = uint256(type(uint128).max) << shift;
            tree[key] = (word & ~mask) | (next << shift);
            prefix = (prefix << 4) | child;
        }
    }

    /// Returns the authoritative total from the 16 root children.
    function rawTotal(mapping(uint256 key => uint256 packed) storage tree) internal view returns (uint256 total) {
        uint256 sum;
        for (uint256 pair; pair < 8; pair++) {
            uint256 word = tree[pair];
            sum += (word & type(uint128).max) + ((word >> 128) & type(uint128).max);
        }
        if (sum > type(uint128).max) {
            revert StakeQuantileTreeLib__SumOverflow();
        }

        return sum;
    }

    // ==== Exact-rank queries ====

    /// Returns the first code whose cumulative raw stake reaches `rank`.
    /// @dev `rank` is one-indexed and `total` must equal the tree's authoritative support. Callers normally
    ///      pass `lowerMedianRank(total)`.
    function rawQuantile(mapping(uint256 key => uint256 packed) storage tree, uint256 rank, uint256 total)
        internal
        view
        returns (uint16 code)
    {
        if (rank == 0 || rank > total) {
            revert StakeQuantileTreeLib__InvalidRank();
        }

        uint256 prefix;
        for (uint256 level; level < RADIX_LEVELS; level++) {
            (prefix, rank) = _crossingChild(tree, level, prefix, rank);
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(prefix);
    }

    /// Returns the raw lower-median code and authoritative support, reading each root word once.
    /// @dev An empty tree returns `(0, 0)` so callers can preserve zero-price behavior without a second traversal.
    function rawLowerMedian(mapping(uint256 key => uint256 packed) storage tree)
        internal
        view
        returns (uint16 code, uint256 support)
    {
        uint256[8] memory rootWords;
        uint256 sum;
        for (uint256 pair; pair < 8; pair++) {
            uint256 word = tree[pair];
            rootWords[pair] = word;
            sum += (word & type(uint128).max) + ((word >> 128) & type(uint128).max);
        }
        if (sum == 0) {
            return (0, 0);
        }
        if (sum > type(uint128).max) {
            revert StakeQuantileTreeLib__SumOverflow();
        }

        support = sum;
        uint256 rank = lowerMedianRank(support);
        uint256 prefix;
        (prefix, rank) = _crossingChildInWords(rootWords, rank);

        for (uint256 level = 1; level < RADIX_LEVELS; level++) {
            (prefix, rank) = _crossingChild(tree, level, prefix, rank);
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        code = uint16(prefix);
    }

    /// Computes the one-indexed lower-median rank for a non-empty total.
    function lowerMedianRank(uint256 total) internal pure returns (uint256) {
        if (total == 0) {
            revert StakeQuantileTreeLib__InvalidRank();
        }
        return total / 2 + total % 2;
    }

    // ==== Exact value encodings ====

    /// Encodes a positive D18 weight into a one-basis-point bucket.
    function weightCode(uint256 weight) internal pure returns (uint16) {
        if (weight == 0 || weight > 1e18) {
            revert StakeQuantileTreeLib__InvalidAmount();
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16((weight - 1) / WEIGHT_BUCKET_WIDTH);
    }

    function weightLow(uint16 code) internal pure returns (uint256) {
        _checkWeightCode(code);
        return uint256(code) * WEIGHT_BUCKET_WIDTH + 1;
    }

    function weightHigh(uint16 code) internal pure returns (uint256) {
        _checkWeightCode(code);
        uint256 high = (uint256(code) + 1) * WEIGHT_BUCKET_WIDTH;
        return high < 1e18 ? high : 1e18;
    }

    function weightRepresentative(uint16 code) internal pure returns (uint256) {
        uint256 low = weightLow(code);
        return low + (weightHigh(code) - low) / 2;
    }

    /// Encodes a nonzero price up to MAX_PRICE into an exponent plus an 8-bit fraction.
    function priceCode(uint256 price) internal pure returns (uint16) {
        if (price == 0 || price > MAX_PRICE) {
            revert StakeQuantileTreeLib__InvalidPrice();
        }

        uint256 exponent = Math.log2(price);
        uint256 base = uint256(1) << exponent;
        uint256 fraction = (price - base) * 256 / base;
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(exponent * 256 + fraction);
    }

    function priceLow(uint16 code) internal pure returns (uint256) {
        (uint256 exponent, uint256 fraction) = _priceParts(code);
        if (exponent > MAX_PRICE_EXPONENT) {
            return MAX_PRICE;
        }

        uint256 base = uint256(1) << exponent;
        uint256 low = base + Math.ceilDiv(fraction * base, 256);
        return low > MAX_PRICE ? MAX_PRICE : low;
    }

    function priceHigh(uint16 code) internal pure returns (uint256) {
        (uint256 exponent, uint256 fraction) = _priceParts(code);
        if (exponent > MAX_PRICE_EXPONENT) {
            return MAX_PRICE;
        }

        uint256 base = uint256(1) << exponent;
        uint256 high = base + Math.ceilDiv((fraction + 1) * base, 256) - 1;
        return high > MAX_PRICE ? MAX_PRICE : high;
    }

    function priceRepresentative(uint16 code) internal pure returns (uint256) {
        uint256 low = priceLow(code);
        uint256 high = priceHigh(code);
        return low + (high - low) / 2;
    }

    // ==== Packed storage helpers ====

    function _crossingChild(
        mapping(uint256 key => uint256 packed) storage tree,
        uint256 level,
        uint256 prefix,
        uint256 rank
    ) internal view returns (uint256 nextPrefix, uint256 nextRank) {
        for (uint256 pair; pair < 8; pair++) {
            uint256 word = tree[_rawKey(level, prefix, pair << 1)];
            uint256 evenStake = word & type(uint128).max;
            if (rank <= evenStake) {
                return ((prefix << 4) | (pair << 1), rank);
            }
            rank -= evenStake;

            uint256 oddStake = (word >> 128) & type(uint128).max;
            if (rank <= oddStake) {
                return ((prefix << 4) | (pair << 1) | 1, rank);
            }
            rank -= oddStake;
        }

        revert StakeQuantileTreeLib__NoCrossingChild();
    }

    function _crossingChildInWords(uint256[8] memory words, uint256 rank)
        internal
        pure
        returns (uint256 nextPrefix, uint256 nextRank)
    {
        for (uint256 pair; pair < 8; pair++) {
            uint256 word = words[pair];
            uint256 evenStake = word & type(uint128).max;
            if (rank <= evenStake) {
                return (pair << 1, rank);
            }
            rank -= evenStake;

            uint256 oddStake = (word >> 128) & type(uint128).max;
            if (rank <= oddStake) {
                return ((pair << 1) | 1, rank);
            }
            rank -= oddStake;
        }

        revert StakeQuantileTreeLib__NoCrossingChild();
    }

    function _rawKey(uint256 level, uint256 prefix, uint256 child) private pure returns (uint256) {
        return (level << 16) | (prefix << 3) | (child >> 1);
    }

    function _checkWeightCode(uint16 code) private pure {
        if (code >= WEIGHT_BUCKET_COUNT) {
            revert StakeQuantileTreeLib__InvalidCode();
        }
    }

    function _priceParts(uint16 code) private pure returns (uint256 exponent, uint256 fraction) {
        exponent = uint256(code) >> 8;
        fraction = uint256(code) & 0xFF;
        // At low exponents, most fractional intervals contain no integer price and can never be emitted by priceCode.
        if (exponent < 8 && fraction % (uint256(1) << (8 - exponent)) != 0) {
            revert StakeQuantileTreeLib__InvalidCode();
        }
    }
}
