// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MintableERC20Mock.sol";
import "../interfaces/IAaveLendingPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AaveLendingPoolMock is IAaveLendingPool {
    using SafeERC20 for IERC20;

    // from token to its aToken
    mapping(address => address) public aTokens;

    event Deposit(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint16 indexed referral
    );
    event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount);
    event Debug(address asset, uint256 amount, address onBehalfOf, uint16 referralCode);

    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external {
        emit Debug(asset, amount, onBehalfOf, referralCode);
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        address aToken = aTokens[asset];
        // mint twice amount as a reward
        MintableERC20Mock(aToken).mint(onBehalfOf, amount * 2);

        emit Deposit(asset, msg.sender, onBehalfOf, amount, referralCode);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        address aToken = aTokens[asset];
        require(MintableERC20Mock(aToken).balanceOf(msg.sender) >= amount, "Can't withdraw more than balance");

        IERC20(asset).safeTransfer(to, amount);
        MintableERC20Mock(aToken).burn(msg.sender, amount);

        emit Withdraw(asset, msg.sender, to, amount);

        return amount;
    }
}
