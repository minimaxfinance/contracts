// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IBEP20.sol";

interface ISmartChefInitializable {
    // Deposit '_amount' of stakedToken tokens
    function deposit(uint256 _amount) external;

    // Withdraw '_amount' of stakedToken and all pending rewardToken tokens
    function withdraw(uint256 _amount) external;
}

contract SmartChefInitializable is ISmartChefInitializable {
    // The reward token
    IBEP20 public rewardToken;

    // The staked token
    IBEP20 public stakedToken;

    function deposit(uint256 _amount) external {}

    function withdraw(uint256 _amount) external {}
}
