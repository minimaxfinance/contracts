// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IERC20Decimals.sol";
import "./market/IMarket.sol";

interface _IAuriLens {
    function getRewardSpeeds(address comptroller, address auToken)
        external
        view
        returns (
            uint256 plyRewardSupplySpeed,
            uint256 plyRewardBorrowSpeed,
            uint256 auroraRewardSupplySpeed,
            uint256 auroraRewardBorrowSpeed
        );
}

interface _IAurigamiPool {
    function decimals() external;

    function totalBorrows() external view returns (uint256);

    function getCash() external view returns (uint256);

    function underlying() external view returns (address);

    function supplyRatePerTimestamp() external view returns (uint256);
}

contract AurigamiAPYCalculator {
    uint256 public constant SECONDS_PER_YEAR = 86400 * 365;
    address public constant AURI_LENS = 0xFfdFfBDB966Cb84B50e62d70105f2Dbf2e0A1e70;
    address public constant COMPTROLLER = 0x817af6cfAF35BdC1A634d6cC94eE9e4c68369Aeb;
    address public constant PLY_TOKEN = 0x09C9D464b58d96837f8d8b6f4d9fE4aD408d3A4f;
    address public constant REF_TOKEN = 0xB12BFcA5A55806AaF64E99521918A4bf0fC40802;

    struct State {
        address underlyingToken;
        uint256 totalDeposited;
        uint256 totalDepositedMultiplier;
        uint256 rewardSupplySpeed;
        uint256 rewardSupplySpeedMultiplier;
        uint256 priceA;
        uint256 priceAMultiplier;
        uint256 priceB;
        uint256 priceBMultiplier;
    }

    function calculateApy(IMarket market, address pool)
        external
        view
        returns (
            uint256 rewardApy,
            uint256 rewardApyMultiplier,
            uint256 underlyingSupplyRate
        )
    {
        State memory state;
        state.underlyingToken = _IAurigamiPool(pool).underlying();
        state.totalDeposited = _IAurigamiPool(pool).totalBorrows() + _IAurigamiPool(pool).getCash();
        state.totalDepositedMultiplier = 10**IERC20Decimals(state.underlyingToken).decimals();

        (state.rewardSupplySpeed, , , ) = _IAuriLens(AURI_LENS).getRewardSpeeds(COMPTROLLER, pool);
        state.rewardSupplySpeedMultiplier = 10**IERC20Decimals(PLY_TOKEN).decimals();

        (state.priceA, state.priceAMultiplier) = getTokenRelation(market, REF_TOKEN, state.underlyingToken);
        (state.priceB, state.priceBMultiplier) = getTokenRelation(market, REF_TOKEN, PLY_TOKEN);

        rewardApyMultiplier = 1000000;
        rewardApy =
            (((rewardApyMultiplier *
                state.rewardSupplySpeed *
                state.totalDepositedMultiplier *
                SECONDS_PER_YEAR *
                state.priceA) / state.priceB) * state.priceBMultiplier) /
            state.priceAMultiplier /
            state.rewardSupplySpeedMultiplier /
            state.totalDeposited;

        // underlyingSupplyRate is always scaled by 1e18 (from contract sources)
        underlyingSupplyRate = _IAurigamiPool(pool).supplyRatePerTimestamp();
    }

    function getTokenRelation(
        IMarket market,
        address tokenA,
        address tokenB
    ) public view returns (uint256, uint256) {
        uint256 tokenAMultiplier = 10**IERC20Decimals(tokenA).decimals();
        uint256 tokenBMultiplier = 10**IERC20Decimals(tokenB).decimals();
        (uint256 tokenBEstimation, ) = market.estimateOut(tokenA, tokenB, tokenAMultiplier);

        uint256 desiredMultiplier = 10**6; // reduce multiplier to 6 decimals to avoid overflow
        tokenBEstimation = (tokenBEstimation * desiredMultiplier) / tokenBMultiplier;
        return (tokenBEstimation, desiredMultiplier);
    }
}
