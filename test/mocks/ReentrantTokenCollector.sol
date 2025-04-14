// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {TokenCollector} from "../../src/collectors/TokenCollector.sol";
import {Test} from "forge-std/Test.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PaymentEscrow} from "../../src/PaymentEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ReentrantTokenCollector is Test, TokenCollector {
    constructor(address _paymentEscrow) TokenCollector(_paymentEscrow) {}

    bool called = false;

    function _collectTokens(PaymentEscrow.PaymentInfo calldata paymentInfo, uint256, bytes calldata)
        internal
        override
    {
        address tokenStore = paymentEscrow.getTokenStore(paymentInfo.operator);

        if (!called) {
            called = true;
            PaymentEscrow.PaymentInfo memory paymentInfo2 = paymentInfo; // calldata is read-only
            paymentInfo2.salt += 1; // avoid hash repeat
            vm.startPrank(address(paymentInfo.operator));
            paymentEscrow.authorize(paymentInfo2, 10 ether, address(this), "");
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
