methods {
    function trackedTotal() external returns (uint256) envfree;
    function rawTotal() external returns (uint256) envfree;
    function rawQuantile(uint256, uint256) external returns (uint16) envfree;
    function rawLowerMedian() external returns (uint16, uint256) envfree;
    function packedWord(uint256) external returns (uint256) envfree;
    function packedPairTotal(uint256) external returns (uint256) envfree;
    function childStake(uint256, uint256, uint256) external returns (uint256) envfree;
    function crossingChild(uint256, uint256, uint256) external returns (uint256, uint256) envfree;
    function crossingChildInRootWords(uint256) external returns (uint256, uint256) envfree;
    function nodeTotal(uint256, uint256) external returns (uint256) envfree;
    function nodeStakeBefore(uint256, uint256, uint256) external returns (uint256) envfree;
    function rawKey(uint256, uint256, uint256) external returns (uint256) envfree;
    function pathPrefix(uint16, uint256) external returns (uint256) envfree;
    function pathChild(uint16, uint256) external returns (uint256) envfree;
    function pathKey(uint16, uint256) external returns (uint256) envfree;
    function validNode(uint256, uint256, uint256) external returns (bool) envfree;
    function isOnPath(uint16, uint256, uint256, uint256) external returns (bool) envfree;
    function lowerMedianRank(uint256) external returns (uint256) envfree;
    function weightCode(uint256) external returns (uint16) envfree;
    function weightLow(uint16) external returns (uint256) envfree;
    function weightHigh(uint16) external returns (uint256) envfree;
    function weightRepresentative(uint16) external returns (uint256) envfree;
    function priceCode(uint256) external returns (uint16) envfree;
    function priceLow(uint16) external returns (uint256) envfree;
    function priceHigh(uint16) external returns (uint256) envfree;
    function priceRepresentative(uint16) external returns (uint256) envfree;
    function priceCodeHasIntegerBucket(uint16) external returns (bool) envfree;
    function maxPrice() external returns (uint256) envfree;
}

rule packedKeysAreInjectiveAcrossNodes(
    uint256 firstLevel,
    uint256 firstPrefix,
    uint256 firstChild,
    uint256 secondLevel,
    uint256 secondPrefix,
    uint256 secondChild
) {
    require validNode(firstLevel, firstPrefix, firstChild);
    require validNode(secondLevel, secondPrefix, secondChild);
    require rawKey(firstLevel, firstPrefix, firstChild) == rawKey(secondLevel, secondPrefix, secondChild);

    assert firstLevel == secondLevel && firstPrefix == secondPrefix
        && firstChild / 2 == secondChild / 2,
        "only the even/odd lanes of one node may share a packed key";
}

rule zeroAmountIsStorageNoOp(env e, uint16 code) {
    storage before = lastStorage;
    addRaw(e, code, 0);
    assert lastStorage == before, "zero stake must not change any storage";
}

rule pathPackedWordChangesExactly(env e, uint16 code, uint256 amount, uint256 level) {
    require level < 4;
    uint256 key = pathKey(code, level);
    uint256 child = pathChild(code, level);
    mathint before = packedWord(key);

    addRaw(e, code, amount);

    mathint after = packedWord(key);
    if (child % 2 == 0) {
        assert after == before + amount, "an even path lane must increase without changing its sibling";
    } else {
        assert after == before + amount * 340282366920938463463374607431768211456,
            "an odd path lane must increase without changing its sibling";
    }
}

rule offPathPackedWordsRemainUnchanged(env e, uint16 code, uint256 amount, uint256 key) {
    require key != pathKey(code, 0);
    require key != pathKey(code, 1);
    require key != pathKey(code, 2);
    require key != pathKey(code, 3);
    uint256 before = packedWord(key);

    addRaw(e, code, amount);

    assert packedWord(key) == before, "an update must not change words outside its four-word path";
}

// Together with offPathPackedWordsRemainUnchanged, this proves the authoritative root sum increases by amount.
rule successfulUpdateIncreasesRootPairTotal(env e, uint16 code, uint256 amount) {
    uint256 rootKey = pathKey(code, 0);
    mathint before = packedPairTotal(rootKey);

    addRaw(e, code, amount);

    mathint after = packedPairTotal(rootKey);
    assert after == before + amount, "a successful update must increase its root pair total exactly";
}

rule oversizedUpdateRevertsAtomically(env e, uint16 code, uint256 amount) {
    require amount > max_uint128;
    storage before = lastStorage;

    addRawUnchecked@withrevert(e, code, amount);
    bool reverted = lastReverted;

    assert reverted, "an amount wider than a packed lane must revert";
    assert lastStorage == before, "a reverted oversized update must be atomic";
}

rule overflowingRootLaneRevertsAtomically(env e, uint16 code, uint256 amount) {
    uint256 rootChild = require_uint256(code / 4096);
    require childStake(0, 0, rootChild) > 0;
    require amount == max_uint128;
    storage before = lastStorage;

    addRawUnchecked@withrevert(e, code, amount);
    bool reverted = lastReverted;

    assert reverted, "an overflowing root lane must revert";
    assert lastStorage == before, "an overflowing update must be atomic";
}

// key is universally quantified, so equality here is extensional equality of the packed mapping.
rule splitUpdateEqualsCombinedUpdate(env e, uint16 code, uint128 first, uint128 second, uint256 key) {
    require first + second <= max_uint128;
    storage initial = lastStorage;

    addRaw(e, code, first) at initial;
    addRaw(e, code, second);
    uint256 splitWord = packedWord(key);
    uint256 splitTotal = trackedTotal();

    addRaw(e, code, require_uint256(first + second)) at initial;
    uint256 combinedWord = packedWord(key);
    uint256 combinedTotal = trackedTotal();

    assert splitWord == combinedWord, "splitting an update must not change any packed tree word";
    assert splitTotal == combinedTotal, "splitting an update must not change tracked support";
}

// The first path is arbitrary; swapping the universally quantified codes covers the second path as well.
// offPathPackedWordsRemainUnchanged covers every word outside both paths.
rule updatesCommuteOnPath(
    env e,
    uint16 firstCode,
    uint16 secondCode,
    uint128 first,
    uint128 second,
    uint256 level
) {
    require first + second <= max_uint128;
    require level < 4;
    uint256 key = pathKey(firstCode, level);
    storage initial = lastStorage;

    addRawUnchecked(e, firstCode, first) at initial;
    addRawUnchecked(e, secondCode, second);
    uint256 forwardWord = packedWord(key);

    addRawUnchecked(e, secondCode, second) at initial;
    addRawUnchecked(e, firstCode, first);
    uint256 reverseWord = packedWord(key);

    assert forwardWord == reverseWord, "insertion order must not change a word on either update path";
}

rule trackedTotalUpdatesCommute(env e, uint16 firstCode, uint16 secondCode, uint128 first, uint128 second) {
    require first + second <= max_uint128;
    storage initial = lastStorage;

    addRaw(e, firstCode, first) at initial;
    addRaw(e, secondCode, second);
    uint256 forwardTotal = trackedTotal();

    addRaw(e, secondCode, second) at initial;
    addRaw(e, firstCode, first);
    uint256 reverseTotal = trackedTotal();

    assert forwardTotal == reverseTotal, "insertion order must not change tracked support";
}

// rawLowerMedian uses the word-backed helper for its root step, then the same storage-backed loop as rawQuantile.
rule rootWordCrossingMatchesStorage(uint256 rank) {
    uint256 total = rawTotal();
    require 0 < rank && rank <= total;

    uint256 wordPrefix;
    uint256 wordRank;
    (wordPrefix, wordRank) = crossingChildInRootWords(rank);

    uint256 storagePrefix;
    uint256 storageRank;
    (storagePrefix, storageRank) = crossingChild(0, 0, rank);

    assert wordPrefix == storagePrefix && wordRank == storageRank,
        "word-backed and storage-backed root crossing must agree";
}

// Lexicographic monotonicity of one radix step composes across all four rawQuantile levels.
rule crossingChildIsMonotone(
    uint256 level,
    uint256 prefix,
    uint256 lowerRank,
    uint256 higherRank
) {
    require validNode(level, prefix, 0);
    uint256 total = nodeTotal(level, prefix);
    require 0 < lowerRank && lowerRank <= higherRank && higherRank <= total;

    uint256 lowerPrefix;
    uint256 lowerResidual;
    (lowerPrefix, lowerResidual) = crossingChild(level, prefix, lowerRank);

    uint256 higherPrefix;
    uint256 higherResidual;
    (higherPrefix, higherResidual) = crossingChild(level, prefix, higherRank);

    assert lowerPrefix < higherPrefix || (lowerPrefix == higherPrefix && lowerResidual <= higherResidual),
        "a radix step must preserve rank order lexicographically";
}

rule crossingChildSelectsFirstRankCrossing(uint256 rank) {
    require 0 < rank && rank <= nodeTotal(0, 0);

    uint256 nextPrefix;
    uint256 nextRank;
    (nextPrefix, nextRank) = crossingChild(0, 0, rank);
    uint256 child = require_uint256(nextPrefix % 16);
    mathint before = nodeStakeBefore(0, 0, child);
    mathint stake = childStake(0, 0, child);

    assert nextPrefix == child, "the selected child must extend the root prefix";
    assert before < rank && rank <= before + stake, "the selected child must be the first rank crossing";
    assert nextRank == rank - before, "the residual rank must be relative to the selected child";
}

rule lowerMedianRankIsCeilingHalf(uint256 total) {
    require total > 0;
    mathint rank = lowerMedianRank(total);

    assert rank > 0 && rank <= total, "median rank must be a valid one-indexed rank";
    assert 2 * rank >= total, "median rank must reach half of support";
    assert 2 * (rank - 1) < total, "the preceding rank must be below half of support";
}

rule weightEncodingContainsInput(uint256 weight) {
    require 0 < weight && weight <= 1000000000000000000;
    uint16 code = weightCode(weight);
    uint256 low = weightLow(code);
    uint256 high = weightHigh(code);
    uint256 representative = weightRepresentative(code);

    assert code < 10000, "accepted weights must produce valid bucket codes";
    assert low <= weight && weight <= high, "a weight must be inside its encoded bucket";
    assert low <= representative && representative <= high,
        "the representative must be inside its bucket";
}

rule weightCodesAreMonotone(uint256 lower, uint256 higher) {
    require 0 < lower && lower <= higher && higher <= 1000000000000000000;
    assert weightCode(lower) <= weightCode(higher), "weight encoding must be monotone";
}

rule invalidWeightCodesRevert(uint16 code) {
    require code >= 10000;

    weightLow@withrevert(code);
    bool lowReverted = lastReverted;
    weightHigh@withrevert(code);
    bool highReverted = lastReverted;
    weightRepresentative@withrevert(code);
    bool representativeReverted = lastReverted;

    assert lowReverted && highReverted && representativeReverted,
        "all weight decoders must reject out-of-domain codes";
}

rule priceEncodingContainsInput(uint256 price) {
    uint256 maximum = maxPrice();
    require 0 < price && price <= maximum;
    uint16 code = priceCode(price);
    uint256 low = priceLow(code);
    uint256 high = priceHigh(code);
    uint256 representative = priceRepresentative(code);

    assert low <= price && price <= high, "a price must be inside its encoded bucket";
    assert low <= representative && representative <= high,
        "the representative must be inside its bucket";
}

rule priceGeneratedBucketLowRoundTrips(uint256 price) {
    uint256 maximum = maxPrice();
    require 0 < price && price <= maximum;
    uint16 code = priceCode(price);
    uint256 low = priceLow(code);

    assert priceCode(low) == code, "a generated bucket's low endpoint must round-trip";
}

rule priceGeneratedBucketHighRoundTrips(uint256 price) {
    uint256 maximum = maxPrice();
    require 0 < price && price <= maximum;
    uint16 code = priceCode(price);
    uint256 high = priceHigh(code);

    assert priceCode(high) == code, "a generated bucket's high endpoint must round-trip";
}

rule priceCodesAreMonotone(uint256 lower, uint256 higher) {
    uint256 maximum = maxPrice();
    require 0 < lower && lower <= higher && higher <= maximum;
    assert priceCode(lower) <= priceCode(higher), "price encoding must be monotone";
}

rule successfulPriceBucketsAreOrdered(uint16 code) {
    uint256 low = priceLow(code);
    uint256 high = priceHigh(code);
    uint256 representative = priceRepresentative(code);

    assert low <= high, "every accepted price code must describe a nonempty interval";
    assert low <= representative && representative <= high,
        "every accepted price representative must be inside its interval";
    assert high <= maxPrice(), "decoded prices must respect the global ceiling";
}

rule emptyIntegerPriceBucketsRevert(uint16 code) {
    require !priceCodeHasIntegerBucket(code);

    priceLow@withrevert(code);
    bool lowReverted = lastReverted;
    priceHigh@withrevert(code);
    bool highReverted = lastReverted;
    priceRepresentative@withrevert(code);
    bool representativeReverted = lastReverted;

    assert lowReverted && highReverted && representativeReverted,
        "price codes with no integer preimage must be rejected";
}

rule terminalPriceCodesClamp(uint16 code) {
    require code / 256 > 149;
    assert priceLow(code) == maxPrice() && priceHigh(code) == maxPrice()
        && priceRepresentative(code) == maxPrice(),
        "codes beyond the terminal exponent must clamp to MAX_PRICE";
}

rule invalidPricesRevert(uint256 price) {
    uint256 maximum = maxPrice();
    require price == 0 || price > maximum;

    priceCode@withrevert(price);
    assert lastReverted, "out-of-domain prices must revert";
}
