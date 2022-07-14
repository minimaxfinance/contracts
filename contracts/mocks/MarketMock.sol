// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../market/IMarket.sol";
import "hardhat/console.sol";

contract MarketMock is IMarket {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes public constant HINTS = "hints example";

    uint private estimatePrice;

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address destination,
        bytes memory hints
    ) external returns (uint256) {
        require(keccak256(hints) == keccak256(HINTS), "wrong hints");
        uint amountOut = 1 ether;
        IERC20Upgradeable(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20Upgradeable(tokenOut).safeTransfer(destination, amountOut);
        return amountOut;
    }

    function estimateOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut, bytes memory hints) {
        return ((amountIn * estimatePrice) / 10**8, HINTS);
    }

    function setEstimatePrice(uint value) public {
        estimatePrice = value;
    }

    function estimateBurn(address lpToken, uint amountIn) external view returns (uint, uint) {
        return (0, 0);
    }
}
