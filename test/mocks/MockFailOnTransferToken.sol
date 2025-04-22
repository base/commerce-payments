// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MockERC3009Token} from "./MockERC3009Token.sol";

contract MockFailOnTransferToken is MockERC3009Token {
    // Returns false unless called by the pre-approval token collector.
    // Allows simulation of SafeTransferLib revert during transfer from the token store.
    address public preApprovalTokenCollector;

    constructor(address preApprovalTokenCollector_) MockERC3009Token("FalseOnTransfer", "FOT", 18) {
        preApprovalTokenCollector = preApprovalTokenCollector_;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (msg.sender == preApprovalTokenCollector) {
            _transfer(msg.sender, to, amount);
            return true;
        }
        return false;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (msg.sender == preApprovalTokenCollector) {
            _transfer(from, to, amount);
            return true;
        }
        return false;
    }
}
