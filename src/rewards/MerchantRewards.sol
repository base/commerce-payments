// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AuthCaptureEscrow} from "../AuthCaptureEscrow.sol";

contract MerchantRewards {
    using SafeERC20 for IERC20;

    uint16 internal constant _MAX_BPS = 10_000;

    AuthCaptureEscrow public immutable authCaptureEscrow;

    address public immutable operator;

    uint16 public immutable rewardBps;

    mapping(bytes32 paymentInfoHash => bool hasRewarded) public hasRewarded;

    event PaymentRewarded(bytes32 paymentInfoHash, address rewardee, address token, uint256 rewardAmount);

    constructor(address _authCaptureEscrow, address _operator, uint16 _rewardBps) {
        authCaptureEscrow = AuthCaptureEscrow(_authCaptureEscrow);
        operator = _operator;
        rewardBps = _rewardBps;
    }

    function reward(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        // Check sender is operator
        if (msg.sender != operator) revert();

        // Check payment has not been rewarded
        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);
        if (hasRewarded[paymentInfoHash]) revert();

        // Check payment has non-refunded capture
        (,, uint120 refundableAmount) = authCaptureEscrow.paymentState(paymentInfoHash);
        uint256 rewardAmount = getRewardAmount(refundableAmount);
        if (rewardAmount == 0) return;

        // Mark payment as rewarded
        hasRewarded[paymentInfoHash] = true;
        emit PaymentRewarded(paymentInfoHash, paymentInfo.receiver, paymentInfo.token, rewardAmount);

        // Transfer reward amount to merchant
        IERC20(paymentInfo.token).safeTransfer(paymentInfo.receiver, rewardAmount);
    }

    function getRewardAmount(uint120 paymentAmount) public view returns (uint256) {
        return (uint256(paymentAmount) * rewardBps) / _MAX_BPS;
    }
}
