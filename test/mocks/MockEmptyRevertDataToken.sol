// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {MockERC3009Token} from "./MockERC3009Token.sol";

contract MockEmptyRevertDataToken is MockERC3009Token {
    address public preApprovalTokenCollector;

    // Selectively succeed for test setup
    constructor(address preApprovalTokenCollector_) MockERC3009Token("Invalid Data Token", "IDT", 18) {
        preApprovalTokenCollector = preApprovalTokenCollector_;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (msg.sender == preApprovalTokenCollector) {
            _transfer(from, to, amount);
            return true;
        }
        // Revert with no data
        assembly {
            revert(0, 0)
        }
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (msg.sender == preApprovalTokenCollector) {
            _transfer(msg.sender, to, amount);
            return true;
        }
        // Revert with no data
        assembly {
            revert(0, 0)
        }
    }
}
