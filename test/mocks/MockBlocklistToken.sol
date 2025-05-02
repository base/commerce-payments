// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {MockERC3009Token} from "./MockERC3009Token.sol";

contract MockBlocklistToken is MockERC3009Token {
    mapping(address => bool) public isBlocked;

    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        MockERC3009Token(name_, symbol_, decimals_)
    {}

    function block(address account) external {
        isBlocked[account] = true;
    }

    function unblock(address account) external {
        isBlocked[account] = false;
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        require(!isBlocked[from], "MockBlocklistToken: sender is blocked");
        require(!isBlocked[to], "MockBlocklistToken: recipient is blocked");
    }
}
