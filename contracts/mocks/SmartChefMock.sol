// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../interfaces/ISmartChef.sol";

contract SmartChefMock is ISmartChef {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public rewardToken;

    IERC20Upgradeable public stakedToken;

    constructor(address _rewardToken, address _stakedToken) {
        rewardToken = IERC20Upgradeable(_rewardToken);
        stakedToken = IERC20Upgradeable(_stakedToken);
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    mapping(address => UserInfo) public userInfo;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => uint256) public balance;
    mapping(address => uint256) public rewards;

    function deposit(uint256 _amount) external {
        balance[msg.sender] = balance[msg.sender] + _amount;
        rewards[msg.sender] = rewards[msg.sender] + 1 ether;
        userInfo[msg.sender].amount += _amount;

        stakedToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external {
        require(balance[msg.sender] >= _amount, "Can't withdraw more than balance");
        balance[msg.sender] = balance[msg.sender] - _amount;
        userInfo[msg.sender].amount -= _amount;

        stakedToken.safeTransfer(msg.sender, _amount);
        rewardToken.safeTransfer(msg.sender, rewards[msg.sender]);

        rewards[msg.sender] = 0;
        emit Withdraw(msg.sender, _amount);
    }

    function pendingReward(address) external view returns (uint256) {
        return 0;
    }

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
}
