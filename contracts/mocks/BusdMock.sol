// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../helpers/BEP20.sol";

contract BusdMock is BEP20("Busd", "Busd") {
    uint public constant MAX_SUPPLY = 10000000 * 1e18;

    // @dev Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) external {
        require(totalSupply() + _amount <= MAX_SUPPLY, "MAX_SUPPLY");
        _mint(_to, _amount);
    }

    function getMaxSupply() external pure returns (uint) {
        return MAX_SUPPLY;
    }
}
