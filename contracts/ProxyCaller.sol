// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ProxyCaller {
    address private _owner;

    constructor() {
        _owner = msg.sender;
    }

    function exec(address callee, bytes calldata data) external returns (bool success, bytes memory) {
        require(msg.sender == _owner, "O");
        return callee.call(data);
    }
}
