// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuthCaptureEscrow} from "../../../src/AuthCaptureEscrow.sol";
import {BuyerRewards} from "../../../src/rewards/BuyerRewards.sol";

import {AuthCaptureEscrowBase} from "../../base/AuthCaptureEscrowBase.sol";

contract BuyerRewardsTest is AuthCaptureEscrowBase {
    BuyerRewards public buyerRewards;

    uint16 maxBps = 10_000;
    uint16 rewardBps = 100;

    function setUp() public override {
        super.setUp();
        buyerRewards = new BuyerRewards(address(authCaptureEscrow), address(operator), rewardBps);
        mockERC3009Token.mint(address(buyerRewards), type(uint120).max);
        mockERC3009Token.mint(address(payerEOA), type(uint120).max);
    }

    function test_reward_delayed(uint120 authorizedAmount, uint40 unlockDelay) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(unlockDelay > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);
        paymentInfo.minFeeBps = 0;
        paymentInfo.feeReceiver = address(0);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.startPrank(paymentInfo.operator);
        authCaptureEscrow.charge(
            paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature, 0, address(0)
        );
        buyerRewards.scheduleReward(paymentInfo, uint48(block.timestamp) + unlockDelay);

        vm.warp(uint48(block.timestamp) + unlockDelay);
        uint256 balanceBefore = mockERC3009Token.balanceOf(payerEOA);
        buyerRewards.claimReward(paymentInfo);
        uint256 balanceAfter = mockERC3009Token.balanceOf(payerEOA);

        vm.stopPrank();

        assertEq(balanceAfter, balanceBefore + buyerRewards.getRewardAmount(authorizedAmount));
    }
}
