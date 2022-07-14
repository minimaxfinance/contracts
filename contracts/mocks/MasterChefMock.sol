// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IMasterChef.sol";

contract MasterChefMock is IMasterChef {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable private token;

    constructor(address _token) {
        token = IERC20Upgradeable(_token);
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => uint256) public balance;
    mapping(address => uint256) public rewards;

    function enterStaking(uint256 _amount) external {
        balance[msg.sender] = balance[msg.sender] + _amount;
        userInfo[0][msg.sender].amount += _amount;

        rewards[msg.sender] = rewards[msg.sender] + 1 ether;

        token.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, 0, _amount);
    }

    function leaveStaking(uint256 _amount) external {
        require(balance[msg.sender] >= _amount, "Can't withdraw more than balance");

        balance[msg.sender] = balance[msg.sender] - _amount;
        userInfo[0][msg.sender].amount -= _amount;

        token.safeTransfer(msg.sender, _amount);
        token.safeTransfer(msg.sender, rewards[msg.sender]);

        rewards[msg.sender] = 0;

        emit Withdraw(msg.sender, 0, _amount);
    }

    function pendingCake(uint256, address) external view returns (uint256) {
        return 0;
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
}
