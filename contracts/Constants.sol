// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

uint256 constant D18 = 1e18; // D18{1}
uint256 constant D27 = 1e27; // D27{1}

// D18{1} 9.43%, retained from the retired one-week half-life for week-scale smoothing.
uint256 constant REWARD_ROUND_FRACTION = 0.0943e18;
uint256 constant MAX_SLASHING_FRACTION = 0.5e18; // D18{1} 50% maximum single-round slash fraction
uint256 constant ROUND_LENGTH = 1 days; // {s}
uint256 constant MAX_RELEASE_GRACE_PERIOD = type(uint64).max; // {s}
uint256 constant MAX_UNSTAKING_DELAY = type(uint64).max; // {s}

// {stToken} Global stake-liability ceiling. It also bounds every per-round tree sum below uint128.
uint256 constant MAX_STAKE = 1e36;
uint256 constant MAX_PRICE = 1e45; // D27{UoA/tok}

uint256 constant WEIGHT_BUCKET_WIDTH = 1e14; // D18{1} one basis point
uint256 constant MAX_SUBMITTED_BASKET_MULTIPLIER = 2 * D18; // D18{1} 2x
uint256 constant MAX_TARGET_BASKET_SIZE = 256; // {count}

address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
