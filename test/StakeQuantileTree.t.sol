// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {MAX_PRICE} from "@src/Constants.sol";
import {StakeQuantileTreeLib} from "@src/StakeQuantileTreeLib.sol";

contract StakeQuantileTreeHarness {
    mapping(uint256 key => uint256 packed) private _rawTree;

    function addRaw(uint16 code, uint256 amount) external {
        StakeQuantileTreeLib.addRaw(_rawTree, code, amount);
    }

    function rawTotal() external view returns (uint256) {
        return StakeQuantileTreeLib.rawTotal(_rawTree);
    }

    function rawQuantile(uint256 rank, uint256 total) external view returns (uint16) {
        return StakeQuantileTreeLib.rawQuantile(_rawTree, rank, total);
    }

    function rawLowerMedian() external view returns (uint16 code, uint256 support) {
        return StakeQuantileTreeLib.rawLowerMedian(_rawTree);
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
}

contract StakeQuantileTreeTest is Test {
    uint256 private constant D18 = 1e18;
    uint256 private constant MAX_TREE_STAKE = 1e36;

    StakeQuantileTreeHarness private tree;

    function setUp() external {
        tree = new StakeQuantileTreeHarness();
    }

    function test_rawTotalCoversAbsentAndPriceOnlyStyleObservations() external {
        assertEq(tree.rawTotal(), 0, "absent tree total nonzero");
        (uint16 emptyCode, uint256 emptySupport) = tree.rawLowerMedian();
        assertEq(emptyCode, 0, "empty tree median code nonzero");
        assertEq(emptySupport, 0, "empty tree median support nonzero");

        tree.addRaw(0x1234, 17);
        tree.addRaw(0xFEDC, 23);
        assertEq(tree.rawTotal(), 40, "root total drifted");
    }

    function test_combinedLowerMedianMatchesExplicitHighReadPaths() external {
        uint16[8] memory codes = [uint16(0), 1, 0x000f, 0x00ff, 0x08ff, 0x0fff, 0x8fff, 0xffff];
        uint256 total;
        for (uint256 i; i < codes.length; i++) {
            // The loop is bounded to eight entries.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 amount = i + 1;
            tree.addRaw(codes[i], amount);
            total += amount;
        }

        uint256 rank = tree.lowerMedianRank(total);
        (uint16 code, uint256 support) = tree.rawLowerMedian();
        assertEq(support, total, "combined median support changed");
        assertEq(code, tree.rawQuantile(rank, total), "combined median crossing changed");
    }

    function test_emptyAndInvalidRanksRevert() external {
        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidRank.selector);
        tree.rawQuantile(1, 0);

        tree.addRaw(0x1234, 1);
        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidRank.selector);
        tree.rawQuantile(0, 1);
        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidRank.selector);
        tree.rawQuantile(2, 1);
    }

    function test_singletonFirstAndLastCodes() external {
        tree.addRaw(0, 17);
        assertEq(tree.rawQuantile(1, 17), 0);

        tree.addRaw(type(uint16).max, 23);
        assertEq(tree.rawQuantile(18, 40), type(uint16).max);
        assertEq(tree.rawQuantile(40, 40), type(uint16).max);
    }

    function test_exactHalfCrossingAndOneWeiRankChanges() external {
        tree.addRaw(0x1000, 5);
        tree.addRaw(0x2000, 5);
        assertEq(tree.rawQuantile(5, 10), 0x1000);
        assertEq(tree.rawQuantile(6, 10), 0x2000);

        tree.addRaw(0x1000, 1);
        assertEq(tree.rawQuantile(6, 11), 0x1000);
        assertEq(tree.rawQuantile(7, 11), 0x2000);
    }

    function test_splitIdentityAndInsertionOrderNeutrality() external {
        StakeQuantileTreeHarness split = new StakeQuantileTreeHarness();
        StakeQuantileTreeHarness unsplit = new StakeQuantileTreeHarness();
        uint16 codeA = 0x0123;
        uint16 codeB = 0xFEDC;

        unsplit.addRaw(codeA, 101);
        unsplit.addRaw(codeB, 99);
        for (uint256 i; i < 101; i++) {
            split.addRaw(codeA, 1);
        }
        for (uint256 i; i < 99; i++) {
            split.addRaw(codeB, 1);
        }

        assertEq(split.rawTotal(), unsplit.rawTotal(), "identity splitting changed total");
        for (uint256 rank = 1; rank <= 200; rank++) {
            assertEq(split.rawQuantile(rank, 200), unsplit.rawQuantile(rank, 200));
        }

        StakeQuantileTreeHarness reverse = new StakeQuantileTreeHarness();
        reverse.addRaw(codeB, 99);
        reverse.addRaw(codeA, 101);
        assertEq(reverse.rawQuantile(100, 200), unsplit.rawQuantile(100, 200));
    }

    function test_lowerMedianRankBoundaries() external {
        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidRank.selector);
        tree.lowerMedianRank(0);

        assertEq(tree.lowerMedianRank(1), 1);
        assertEq(tree.lowerMedianRank(2), 1);
        assertEq(tree.lowerMedianRank(3), 2);
        assertEq(tree.lowerMedianRank(MAX_TREE_STAKE), MAX_TREE_STAKE / 2);
    }

    function test_maximumOneE36SumsFitUint128() external {
        tree.addRaw(0xABCD, MAX_TREE_STAKE);
        assertEq(tree.rawTotal(), MAX_TREE_STAKE);
        assertEq(tree.rawQuantile(1, MAX_TREE_STAKE), 0xABCD);
        assertEq(tree.rawQuantile(MAX_TREE_STAKE, MAX_TREE_STAKE), 0xABCD);

        StakeQuantileTreeHarness overflow = new StakeQuantileTreeHarness();
        overflow.addRaw(0xABCD, type(uint128).max);
        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__SumOverflow.selector);
        overflow.addRaw(0xABCD, 1);
    }

    function test_oversizedAmountUsesCustomErrorAndLeavesTreeUnchanged() external {
        tree.addRaw(0x1234, 1);

        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__SumOverflow.selector);
        tree.addRaw(0x1234, type(uint256).max);

        assertEq(tree.rawTotal(), 1, "reverted update changed support");
        assertEq(tree.rawQuantile(1, 1), 0x1234, "reverted update changed quantile");
    }

    function test_rootTotalOverflowUsesCustomErrorAcrossDistinctChildren() external {
        tree.addRaw(0x0000, type(uint128).max);
        tree.addRaw(0x1000, 1);

        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__SumOverflow.selector);
        tree.rawTotal();
        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__SumOverflow.selector);
        tree.rawLowerMedian();
    }

    function test_exactUint128AggregateAcrossRootChildrenSucceeds() external {
        uint256 left = type(uint128).max / 2;
        uint256 right = type(uint128).max - left;
        tree.addRaw(0x0000, left);
        tree.addRaw(0xFFFF, right);

        assertEq(tree.rawTotal(), type(uint128).max);
        assertEq(tree.rawQuantile(1, type(uint128).max), 0x0000);
        assertEq(tree.rawQuantile(type(uint128).max, type(uint128).max), 0xFFFF);
        (uint16 median, uint256 support) = tree.rawLowerMedian();
        assertEq(median, 0xFFFF);
        assertEq(support, type(uint128).max);
    }

    function test_zeroAmountIsNoOpEvenWhenAmountLaneIsFull() external {
        tree.addRaw(0xBEEF, type(uint128).max);
        tree.addRaw(0xBEEF, 0);

        assertEq(tree.rawTotal(), type(uint128).max);
        assertEq(tree.rawQuantile(type(uint128).max, type(uint128).max), 0xBEEF);
    }

    function test_packedLaneAndPrefixIsolationAtEveryLevel() external {
        uint16[8] memory codes = [uint16(0x0000), 0x0001, 0x000F, 0x0010, 0x00F0, 0x0100, 0x1000, 0xFFFF];
        uint256 total;
        for (uint256 i; i < codes.length; i++) {
            tree.addRaw(codes[i], i + 1);
            total += i + 1;
        }

        uint256 rank = 1;
        for (uint256 i; i < codes.length; i++) {
            uint256 end = rank + i;
            for (; rank <= end; rank++) {
                assertEq(tree.rawQuantile(rank, total), codes[i]);
            }
        }
    }

    function test_weightEncodingBoundariesAndRepresentatives() external {
        assertEq(tree.weightCode(1), 0);
        assertEq(tree.weightCode(1e14), 0);
        assertEq(tree.weightCode(1e14 + 1), 1);
        assertEq(tree.weightCode(D18), 9_999);

        assertEq(tree.weightLow(0), 1);
        assertEq(tree.weightHigh(0), 1e14);
        assertEq(tree.weightLow(9_999), 999_900_000_000_000_001);
        assertEq(tree.weightHigh(9_999), D18);

        for (uint16 code = 0; code < 10_000; code++) {
            uint256 low = tree.weightLow(code);
            uint256 high = tree.weightHigh(code);
            uint256 representative = tree.weightRepresentative(code);
            assertLe(low, representative);
            assertLe(representative, high);
        }

        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidAmount.selector);
        tree.weightCode(0);
        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidCode.selector);
        tree.weightLow(10_000);
    }

    function test_priceEncodingMinimumPowersBoundariesAndTerminalClamp() external {
        assertEq(tree.priceCode(1), 0);
        assertEq(tree.priceCode(2), 256);

        for (uint256 exponent = 2; exponent <= 20; exponent++) {
            uint256 base = uint256(1) << exponent;
            // forge-lint: disable-next-line(unsafe-typecast)
            assertEq(tree.priceCode(base), uint16(exponent * 256));
            uint256 previousBase = base >> 1;
            uint256 previousFraction = (base - 1 - previousBase) * 256 / previousBase;
            // forge-lint: disable-next-line(unsafe-typecast)
            assertEq(tree.priceCode(base - 1), uint16((exponent - 1) * 256 + previousFraction));
        }

        uint16 terminalCode = tree.priceCode(MAX_PRICE);
        assertLe(tree.priceLow(terminalCode), MAX_PRICE);
        assertEq(tree.priceHigh(terminalCode), MAX_PRICE);
        assertLe(tree.priceRepresentative(terminalCode), MAX_PRICE);
        assertEq(tree.priceLow(type(uint16).max), MAX_PRICE);
        assertEq(tree.priceHigh(type(uint16).max), MAX_PRICE);

        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidPrice.selector);
        tree.priceCode(0);
        vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidPrice.selector);
        tree.priceCode(MAX_PRICE + 1);
    }

    function test_priceDecodersRejectEmptyIntegerBuckets() external {
        uint16[5] memory emptyCodes = [uint16(1), 127, 255, 257, 2047];
        for (uint256 i; i < emptyCodes.length; i++) {
            vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidCode.selector);
            tree.priceLow(emptyCodes[i]);
            vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidCode.selector);
            tree.priceHigh(emptyCodes[i]);
            vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidCode.selector);
            tree.priceRepresentative(emptyCodes[i]);
        }
    }

    function test_allPriceCodesAreOrderedOrExplicitlyRejected() external {
        for (uint256 rawCode; rawCode <= type(uint16).max; rawCode++) {
            uint256 exponent = rawCode >> 8;
            uint256 fraction = rawCode & 0xFF;
            bool hasIntegerBucket = exponent >= 8 || fraction % (uint256(1) << (8 - exponent)) == 0;
            // forge-lint: disable-next-line(unsafe-typecast)
            uint16 code = uint16(rawCode);

            if (!hasIntegerBucket) {
                vm.expectRevert(StakeQuantileTreeLib.StakeQuantileTreeLib__InvalidCode.selector);
                tree.priceRepresentative(code);
                continue;
            }

            uint256 low = tree.priceLow(code);
            uint256 high = tree.priceHigh(code);
            uint256 representative = tree.priceRepresentative(code);
            assertLe(low, high);
            assertLe(low, representative);
            assertLe(representative, high);
            assertLe(high, MAX_PRICE);
        }
    }

    function testFuzz_priceEncodingContainsOriginal(uint256 seed) external view {
        uint256 price = bound(seed, 1, MAX_PRICE);
        uint16 code = tree.priceCode(price);
        assertLe(tree.priceLow(code), price);
        assertLe(price, tree.priceHigh(code));
        assertLe(tree.priceRepresentative(code), MAX_PRICE);
    }

    function testFuzz_weightEncodingContainsOriginal(uint256 seed) external view {
        uint256 weight = bound(seed, 1, D18);
        uint16 code = tree.weightCode(weight);
        assertLe(tree.weightLow(code), weight);
        assertLe(weight, tree.weightHigh(code));
    }

    function testFuzz_priceGeneratedBucketRoundTrips(uint256 seed) external view {
        uint256 price = bound(seed, 1, MAX_PRICE);
        uint16 code = tree.priceCode(price);
        assertEq(tree.priceCode(tree.priceLow(code)), code);
        assertEq(tree.priceCode(tree.priceHigh(code)), code);
    }

    function testFuzz_rawQuantileMatchesArbitraryRank(
        uint16[8] calldata codes,
        uint128[8] calldata stakeSeeds,
        uint256 rankSeed
    ) external {
        uint16[8] memory sortedCodes;
        uint256[8] memory sortedStakes;
        uint256 total;

        for (uint256 i; i < 8; i++) {
            uint256 stake = bound(uint256(stakeSeeds[i]), 1, type(uint128).max / 8);
            tree.addRaw(codes[i], stake);
            total += stake;
            sortedCodes[i] = codes[i];
            sortedStakes[i] = stake;

            uint256 j = i;
            while (j != 0 && sortedCodes[j] < sortedCodes[j - 1]) {
                (sortedCodes[j], sortedCodes[j - 1]) = (sortedCodes[j - 1], sortedCodes[j]);
                (sortedStakes[j], sortedStakes[j - 1]) = (sortedStakes[j - 1], sortedStakes[j]);
                j--;
            }
        }

        uint256 rank = bound(rankSeed, 1, total);
        uint256 cumulative;
        uint16 expected;
        for (uint256 i; i < 8; i++) {
            cumulative += sortedStakes[i];
            if (rank <= cumulative) {
                expected = sortedCodes[i];
                break;
            }
        }

        assertEq(tree.rawTotal(), total);
        assertEq(tree.rawQuantile(rank, total), expected);
    }

    function testFuzz_rawQuantileMatchesSortedWeightedList(uint16[8] calldata codes, uint32[8] calldata stakeSeeds)
        external
    {
        uint16[8] memory sortedCodes;
        uint256[8] memory sortedStakes;
        uint256 total;

        for (uint256 i; i < 8; i++) {
            uint256 stake = bound(uint256(stakeSeeds[i]), 1, 1e18);
            tree.addRaw(codes[i], stake);
            total += stake;

            sortedCodes[i] = codes[i];
            sortedStakes[i] = stake;
            uint256 j = i;
            while (j != 0 && sortedCodes[j] < sortedCodes[j - 1]) {
                (sortedCodes[j], sortedCodes[j - 1]) = (sortedCodes[j - 1], sortedCodes[j]);
                (sortedStakes[j], sortedStakes[j - 1]) = (sortedStakes[j - 1], sortedStakes[j]);
                j--;
            }
        }

        assertEq(tree.rawTotal(), total, "fuzzed root total drifted");
        uint256 rank = tree.lowerMedianRank(total);
        uint256 cumulative;
        uint16 expected;
        for (uint256 i; i < 8; i++) {
            cumulative += sortedStakes[i];
            if (cumulative >= rank) {
                expected = sortedCodes[i];
                break;
            }
        }

        assertEq(tree.rawQuantile(rank, total), expected);
        (uint16 combinedCode, uint256 combinedSupport) = tree.rawLowerMedian();
        assertEq(combinedSupport, total, "combined fuzzed support changed");
        assertEq(combinedCode, expected, "combined fuzzed median changed");
    }
}
