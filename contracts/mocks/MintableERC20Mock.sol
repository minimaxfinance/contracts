// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MintableERC20Mock is ERC20 {
    uint public constant MAX_SUPPLY = 10000000 * 1e18;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 value) public {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public {
        _burn(from, value);
    }

    function getMaxSupply() external pure returns (uint) {
        return MAX_SUPPLY;
    }
}
