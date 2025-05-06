// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuthCaptureEscrow} from "../../../src/AuthCaptureEscrow.sol";
import {MerchantRewards} from "../../../src/rewards/MerchantRewards.sol";

import {AuthCaptureEscrowBase} from "../../base/AuthCaptureEscrowBase.sol";

contract MerchantRewardsTest is AuthCaptureEscrowBase {
    MerchantRewards public merchantRewards;

    uint16 maxBps = 10_000;
    uint16 rewardBps = 100;

    function setUp() public override {
        super.setUp();
        merchantRewards = new MerchantRewards(address(authCaptureEscrow), address(operator), rewardBps);
        mockERC3009Token.mint(address(merchantRewards), type(uint120).max);
        mockERC3009Token.mint(address(payerEOA), type(uint120).max);
    }

    function test_reward(uint120 authorizedAmount) public {
        vm.assume(authorizedAmount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);
        paymentInfo.minFeeBps = 0;
        paymentInfo.feeReceiver = address(0);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.startPrank(paymentInfo.operator);
        authCaptureEscrow.charge(
            paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature, 0, address(0)
        );
        merchantRewards.reward(paymentInfo);
        vm.stopPrank();

        assertEq(
            mockERC3009Token.balanceOf(receiver), authorizedAmount + merchantRewards.getRewardAmount(authorizedAmount)
        );
    }
}
