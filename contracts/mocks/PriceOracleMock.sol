// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IPriceOracle.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract PriceOracleMock is IPriceOracle, OwnableUpgradeable {
    int256 priceValue;

    function initialize() external initializer {
        __Ownable_init();
    }

    function setLatestAnswer(int256 _priceValue) external {
        priceValue = _priceValue;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestAnswer() external view override returns (int256) {
        return priceValue;
    }

    function setLatestAnswerRandom() external {
        priceValue = int256(random(10, 30) * 1e8);
    }

    function random(uint lb, uint rb) internal view returns (uint) {
        uint randomnumber = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % (rb - lb);
        randomnumber = randomnumber + uint(lb);
        return randomnumber;
    }
}
