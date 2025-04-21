// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MockERC3009Token} from "./MockERC3009Token.sol";

contract MockRevertOnTransferToken is MockERC3009Token {
    // Reverts unless called by the pre-approval token collector.
    // Allows simulation of revert during transfer from the token store.
    address public preApprovalTokenCollector;

    constructor(address preApprovalTokenCollector_) MockERC3009Token("RevertOnTransfer", "ROT", 18) {
        preApprovalTokenCollector = preApprovalTokenCollector_;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (msg.sender == preApprovalTokenCollector) {
            _transfer(msg.sender, to, amount);
            return true;
        }
        revert();
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (msg.sender == preApprovalTokenCollector) {
            _transfer(from, to, amount);
            return true;
        }
        revert();
    }
}
