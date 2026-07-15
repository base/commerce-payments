// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {MagicSpend} from "magicspend/MagicSpend.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

import {AuthCaptureEscrow} from "../../../src/AuthCaptureEscrow.sol";

import {ERC20UnsafeTransferTokenCollector} from "../../../test/mocks/ERC20UnsafeTransferTokenCollector.sol";
import {AuthCaptureEscrowSmartWalletBase} from "../../base/AuthCaptureEscrowSmartWalletBase.sol";

contract AuthorizeTest is AuthCaptureEscrowSmartWalletBase {
    function test_reverts_whenValueIsZero() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: 1}); // Any non-zero value

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(AuthCaptureEscrow.ZeroAmount.selector);
        authCaptureEscrow.authorize(paymentInfo, 0, address(erc3009PaymentCollector), signature);
    }

    function test_reverts_whenAmountOverflows(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint120).max);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: 1});

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(AuthCaptureEscrow.AmountOverflow.selector, overflowValue, type(uint120).max)
        );
        authCaptureEscrow.authorize(paymentInfo, overflowValue, address(erc3009PaymentCollector), signature);
    }

    function test_reverts_whenCallerIsNotOperator(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != operator);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(AuthCaptureEscrow.InvalidSender.selector, invalidSender, paymentInfo.operator)
        );
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);
    }

    function test_reverts_whenValueExceedsAuthorized(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        uint256 confirmAmount = authorizedAmount + 1; // Always exceeds authorized

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(AuthCaptureEscrow.ExceedsMaxAmount.selector, confirmAmount, authorizedAmount)
        );
        authCaptureEscrow.authorize(paymentInfo, confirmAmount, address(erc3009PaymentCollector), signature);
    }

    function test_reverts_exactlyAtPreApprovalExpiry(uint120 amount) public {
        vm.assume(amount > 0);

        uint48 preApprovalExpiry = uint48(block.timestamp + 1 days);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});
        paymentInfo.preApprovalExpiry = preApprovalExpiry;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // Set time to exactly at the authorize deadline
        vm.warp(preApprovalExpiry);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthCaptureEscrow.AfterPreApprovalExpiry.selector, preApprovalExpiry, preApprovalExpiry
            )
        );
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);
    }

    function test_reverts_afterPreApprovalExpiry(uint120 amount) public {
        vm.assume(amount > 0);

        uint48 preApprovalExpiry = uint48(block.timestamp + 1 days);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});
        paymentInfo.preApprovalExpiry = preApprovalExpiry;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // Set time to after the authorize deadline
        vm.warp(preApprovalExpiry + 1);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthCaptureEscrow.AfterPreApprovalExpiry.selector, preApprovalExpiry + 1, preApprovalExpiry
            )
        );
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);
    }

    function test_reverts_whenPreApprovalExpiryAfterAuthorizationExpiry(
        uint120 amount,
        uint48 preApprovalExpiry,
        uint48 authorizationExpiry,
        uint48 refundExpiry
    ) public {
        vm.assume(amount > 0);
        vm.assume(preApprovalExpiry > block.timestamp);
        vm.assume(preApprovalExpiry > authorizationExpiry);
        vm.assume(authorizationExpiry <= refundExpiry);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        // Set authorize deadline after capture deadline
        paymentInfo.preApprovalExpiry = preApprovalExpiry;
        paymentInfo.authorizationExpiry = authorizationExpiry;
        paymentInfo.refundExpiry = refundExpiry;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthCaptureEscrow.InvalidExpiries.selector, preApprovalExpiry, authorizationExpiry, refundExpiry
            )
        );
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);
    }

    function test_reverts_whenAuthorizationExpiryAfterRefundExpiry(
        uint120 amount,
        uint48 preApprovalExpiry,
        uint48 authorizationExpiry,
        uint48 refundExpiry
    ) public {
        vm.assume(amount > 0);
        vm.assume(preApprovalExpiry > block.timestamp);
        vm.assume(preApprovalExpiry <= authorizationExpiry);
        vm.assume(authorizationExpiry > refundExpiry);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        // Set authorize deadline after capture deadline
        paymentInfo.preApprovalExpiry = preApprovalExpiry;
        paymentInfo.authorizationExpiry = authorizationExpiry;
        paymentInfo.refundExpiry = refundExpiry;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthCaptureEscrow.InvalidExpiries.selector, preApprovalExpiry, authorizationExpiry, refundExpiry
            )
        );
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);
    }

    function test_reverts_whenFeeBpsTooHigh(uint120 amount) public {
        vm.assume(amount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        // Set fee bps > 100%
        paymentInfo.maxFeeBps = 10_001;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(AuthCaptureEscrow.FeeBpsOverflow.selector, 10_001));
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);
    }

    function test_reverts_whenFeeBpsRangeInvalid(uint120 amount, uint16 minFeeBps, uint16 maxFeeBps) public {
        vm.assume(amount > 0);
        vm.assume(maxFeeBps < 10_000);
        vm.assume(minFeeBps <= 10_000);
        vm.assume(minFeeBps > maxFeeBps);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});
        paymentInfo.minFeeBps = minFeeBps;
        paymentInfo.maxFeeBps = maxFeeBps;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(AuthCaptureEscrow.InvalidFeeBpsRange.selector, minFeeBps, maxFeeBps));
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);
    }

    function test_reverts_whenAlreadyAuthorized(uint120 amount) public {
        vm.assume(amount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First authorization
        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        // Try to authorize again with same payment info
        mockERC3009Token.mint(payerEOA, amount);
        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);
        vm.expectRevert(abi.encodeWithSelector(AuthCaptureEscrow.PaymentAlreadyCollected.selector, paymentInfoHash));
        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);
    }

    function test_reverts_whenUsingIncorrectTokenCollectorForOperation(uint120 amount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(amount > 0 && amount <= payerBalance);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(AuthCaptureEscrow.InvalidCollectorForOperation.selector));
        authCaptureEscrow.authorize(paymentInfo, amount, address(operatorRefundCollector), signature);
    }

    function test_reverts_ifHookDoesNotTransferCorrectAmount(uint120 amount) public {
        vm.assume(amount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount, address(mockERC20Token));

        // approve hook to transfer tokens
        vm.prank(payerEOA);
        mockERC20Token.approve(address(erc20UnsafeTransferPaymentCollector), amount);

        // Pre-approve in hook
        vm.prank(payerEOA);
        ERC20UnsafeTransferTokenCollector(address(erc20UnsafeTransferPaymentCollector)).preApprove(paymentInfo);

        // mint tokens to payer
        mockERC20Token.mint(payerEOA, amount);

        // Try to authorize - should fail on token transfer
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(AuthCaptureEscrow.TokenCollectionFailed.selector));
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc20UnsafeTransferPaymentCollector), "");
    }

    function test_succeeds_whenValueEqualsAuthorized(uint120 amount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(amount > 0 && amount <= payerBalance);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);

        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        address operatorTokenStore = authCaptureEscrow.getTokenStore(operator);
        assertEq(mockERC3009Token.balanceOf(operatorTokenStore), amount);
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore - amount);
    }

    function test_succeeds_usingPermit2PaymentCollector(uint120 amount) public {
        vm.assume(amount > 0);

        // Deploy a regular ERC20 without ERC3009
        MockERC20 plainToken = new MockERC20("Plain Token", "PLAIN", 18);

        // payer needs to approve Permit2 to spend their tokens
        vm.startPrank(payerEOA);
        plainToken.approve(permit2, type(uint256).max);
        vm.stopPrank();

        // Mint enough tokens to the payer
        plainToken.mint(payerEOA, amount);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: amount, token: address(plainToken)});

        // Generate Permit2 signature using the same deadline as paymentInfo
        bytes memory signature = _signPermit2Transfer({
            token: address(plainToken),
            amount: amount,
            deadline: paymentInfo.preApprovalExpiry,
            nonce: uint256(_getHashPayerAgnostic(paymentInfo)),
            privateKey: payer_EOA_PK
        });

        // Should succeed via Permit2 authorization
        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, amount, address(permit2PaymentCollector), signature);

        // Verify the transfer worked
        address operatorTokenStore = authCaptureEscrow.getTokenStore(operator);
        assertEq(plainToken.balanceOf(operatorTokenStore), amount);
        assertEq(plainToken.balanceOf(payerEOA), 0);
    }

    function test_succeeds_usingSpendPermissionPaymentCollector(uint120 maxAmount, uint120 amount) public {
        // Assume reasonable values
        vm.assume(maxAmount >= amount && amount > 0);
        mockERC3009Token.mint(address(smartWalletDeployed), amount);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({
            payer: address(smartWalletDeployed),
            maxAmount: maxAmount,
            token: address(mockERC3009Token)
        });

        // Create and sign the spend permission
        SpendPermissionManager.SpendPermission memory permission = _createSpendPermission(paymentInfo);

        bytes memory signature = _signSpendPermission(
            permission,
            DEPLOYED_WALLET_OWNER_PK,
            0 // owner index
        );

        // Record balances before
        uint256 walletBalanceBefore = mockERC3009Token.balanceOf(address(smartWalletDeployed));

        // Submit authorization
        vm.prank(operator);
        authCaptureEscrow.authorize(
            paymentInfo, amount, address(spendPermissionPaymentCollector), abi.encode(signature, "")
        ); // Empty collectorData for regular spend

        // Get token store address after creation
        address operatorTokenStore = authCaptureEscrow.getTokenStore(operator);

        // Verify balances
        assertEq(
            mockERC3009Token.balanceOf(address(smartWalletDeployed)),
            walletBalanceBefore - amount,
            "Wallet balance should decrease by amount"
        );
        assertEq(
            mockERC3009Token.balanceOf(operatorTokenStore), amount, "Token store balance should increase by amount"
        );
    }

    function test_succeeds_usingSpendPermissionPaymentCollector_withMagicSpend(uint120 amount) public {
        // Assume reasonable values and fund MagicSpend
        vm.assume(amount > 0);
        mockERC3009Token.mint(address(magicSpend), amount);

        // Create payment info with SpendPermissionWithMagicSpend auth type
        AuthCaptureEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo(address(smartWalletDeployed), amount, address(mockERC3009Token));

        // Create the spend permission
        SpendPermissionManager.SpendPermission memory permission = _createSpendPermission(paymentInfo);

        // Create and sign withdraw request
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission);
        withdrawRequest.asset = address(mockERC3009Token);
        withdrawRequest.amount = amount;
        withdrawRequest.signature = _signWithdrawRequest(address(smartWalletDeployed), withdrawRequest);

        bytes memory signature = _signSpendPermission(permission, DEPLOYED_WALLET_OWNER_PK, 0);

        // Record balances before
        uint256 magicSpendBalanceBefore = mockERC3009Token.balanceOf(address(magicSpend));

        // Submit authorization
        vm.prank(operator);
        authCaptureEscrow.authorize(
            paymentInfo,
            amount,
            address(spendPermissionPaymentCollector),
            abi.encode(signature, abi.encode(withdrawRequest))
        );

        // Get token store address after creation
        address operatorTokenStore = authCaptureEscrow.getTokenStore(operator);

        // Verify balances - funds should move from MagicSpend to escrow
        assertEq(
            mockERC3009Token.balanceOf(address(magicSpend)),
            magicSpendBalanceBefore - amount,
            "MagicSpend balance should decrease by amount"
        );
        assertEq(
            mockERC3009Token.balanceOf(operatorTokenStore), amount, "Token store balance should increase by amount"
        );
    }

    function test_authorize_succeeds_whenValueLessThanAuthorized(uint120 authorizedAmount, uint120 confirmAmount)
        public
    {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        vm.assume(confirmAmount > 0 && confirmAmount < authorizedAmount);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);

        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, confirmAmount, address(erc3009PaymentCollector), signature);
        address operatorTokenStore = authCaptureEscrow.getTokenStore(operator);
        assertEq(mockERC3009Token.balanceOf(operatorTokenStore), confirmAmount);
        assertEq(
            mockERC3009Token.balanceOf(payerEOA),
            payerBalanceBefore - authorizedAmount + (authorizedAmount - confirmAmount)
        );
    }

    function test_succeeds_whenFeeRecipientZeroAndFeeBpsZero(uint120 amount) public {
        vm.assume(amount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        // Set both fee recipient and fee bps to zero - this should be valid
        paymentInfo.feeReceiver = address(0);
        paymentInfo.minFeeBps = 0;
        paymentInfo.maxFeeBps = 0;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        mockERC3009Token.mint(payerEOA, amount);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);

        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        // Verify balances - full amount should go to escrow since fees are 0
        address operatorTokenStore = authCaptureEscrow.getTokenStore(operator);

        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore - amount);
        assertEq(mockERC3009Token.balanceOf(operatorTokenStore), amount);
    }

    function test_emitsCorrectEvents(uint120 authorizedAmount, uint120 valueToConfirm) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(valueToConfirm > 0 && valueToConfirm <= authorizedAmount);

        mockERC3009Token.mint(payerEOA, authorizedAmount);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // Record expected event
        vm.expectEmit(true, false, false, true);
        emit AuthCaptureEscrow.PaymentAuthorized(
            paymentInfoHash, paymentInfo, valueToConfirm, address(erc3009PaymentCollector)
        );

        // Execute confirmation
        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, valueToConfirm, address(erc3009PaymentCollector), signature);
    }
}
