// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../MinimaxMain.sol";

contract MinimaxMainUpgradedMock is MinimaxMain {
    string private upgradedField;

    function setUpgradedField(string memory newValue) external onlyOwner {
        upgradedField = newValue;
    }

    function getUpgradedField() external view returns (string memory) {
        return upgradedField;
    }
}
