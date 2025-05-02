// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {TokenCollector} from "../../src/collectors/TokenCollector.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AuthCaptureEscrow} from "../../src/AuthCaptureEscrow.sol";

contract ReentrantTokenCollector is Test, TokenCollector {
    constructor(address _escrow) TokenCollector(_escrow) {}

    bool called = false;

    function _collectTokens(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256,
        bytes calldata
    ) internal override {
        if (!called) {
            called = true;
            AuthCaptureEscrow.PaymentInfo memory paymentInfo2 = paymentInfo; // calldata is read-only
            paymentInfo2.salt += 1; // avoid hash repeat
            vm.startPrank(address(paymentInfo.operator));
            authCaptureEscrow.authorize(paymentInfo2, 10 ether, address(this), "");
            vm.stopPrank();
        } else {
            called = false;
            IERC20(paymentInfo.token).transfer(tokenStore, paymentInfo.maxAmount);
        }
    }

    function collectorType() external pure override returns (TokenCollector.CollectorType) {
        return TokenCollector.CollectorType.Payment;
    }
}
