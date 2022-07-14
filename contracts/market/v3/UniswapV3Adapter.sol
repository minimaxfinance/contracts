// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "../../interfaces/IUniswapRouter.sol";

interface IUniswapV3Estimator {
    function estimate(
        address factory,
        address token0,
        address token1,
        int256 amountIn
    ) external view returns (uint256);
}

interface IUniswapV3Factory {
    function getPool(
        address,
        address,
        uint24
    ) external view returns (address);
}

interface IUniswapV3Pool {
    function liquidity() external view returns (uint128);
}

contract UniswapV3Adapter {
    IUniswapV3Estimator public immutable estimator;
    IUniswapRouter public immutable router;
    IUniswapV3Factory public immutable factory;

    constructor(IUniswapV3Estimator _estimator, IUniswapRouter _router) {
        estimator = _estimator;
        router = _router;
        factory = IUniswapV3Factory(_router.factory());
    }

    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts) {
        require(path.length >= 2, "short path");
        address factory = router.factory();

        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (address pool, ) = _maxLiquidityPool(path[i], path[i + 1]);
            amounts[i + 1] = estimator.estimate(pool, path[i], path[i + 1], int256(amounts[i]));
        }
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        IERC20Upgradeable(path[0]).transferFrom(address(msg.sender), address(this), amountIn);
        IERC20Upgradeable(path[0]).approve(address(router), amountIn);
        uint256 out = router.exactInput(
            IUniswapRouter.ExactInputParams({
                path: _buildPath(path),
                recipient: to,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin
            })
        );

        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = out;
    }

    function _buildPath(address[] memory path) private view returns (bytes memory) {
        bytes memory output;
        for (uint i; i < path.length - 1; i++) {
            // for each pair in path find pool with maximum liquidity
            (, uint24 fee) = _maxLiquidityPool(path[i], path[i + 1]);
            output = abi.encodePacked(output, path[i], fee);
        }
        return abi.encodePacked(output, path[path.length - 1]);
    }

    function _maxLiquidityPool(address token0, address token1) private view returns (address pool, uint24 fee) {
        // Uniswap V3 fee tiers: 0.01%, 0.05%, 0.30%, 1%. https://docs.uniswap.org/protocol/concepts/V3-overview/fees
        uint16[4] memory fees = [100, 500, 3000, 10000];

        uint128 maxLiquidity = 0;
        for (uint24 i = 0; i < fees.length; i++) {
            address candidate = factory.getPool(token0, token1, fees[i]);
            if (address(candidate) == address(0)) {
                continue;
            }

            uint128 liquidity = IUniswapV3Pool(candidate).liquidity();
            if (liquidity > maxLiquidity) {
                maxLiquidity = liquidity;
                pool = candidate;
                fee = fees[i];
            }
        }
    }
}
