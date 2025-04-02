// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

contract MockTarget {
    event Called(address sender, uint256 value, bytes data);

    fallback() external payable {
        emit Called(msg.sender, msg.value, msg.data);
    }
}
