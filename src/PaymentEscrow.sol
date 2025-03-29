// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {TokenCollector} from "./collectors/TokenCollector.sol";

/// @title PaymentEscrow
/// @notice Facilitate payments through an escrow.
/// @dev By escrowing payment, this contract can mimic the 2-step payment pattern of "authorization" and "capture".
/// @dev Authorization is defined as placing a hold on a payer's funds temporarily.
/// @dev Capture is defined as distributing payment to the end recipient.
/// @dev An Operator plays the primary role of moving payments between both parties.
/// @author Coinbase
contract PaymentEscrow {
    /// @notice Payment details, contains all information required to authorize and capture a unique payment
    struct PaymentDetails {
        /// @dev Entity responsible for driving payment flow
        address operator;
        /// @dev The payer's address authorizing the payment
        address payer;
        /// @dev Address that receives the payment (minus fees)
        address receiver;
        /// @dev The token contract address
        address token;
        /// @dev The amount of tokens that can be authorized
        uint256 maxAmount;
        /// @dev Timestamp when the payer's pre-approval can no longer authorize payment
        uint48 preApprovalExpiry;
        /// @dev Timestamp when an authorization can no longer be captured and the payer can reclaim from escrow
        uint48 authorizationExpiry;
        /// @dev Timestamp when a successful payment can no longer be refunded
        uint48 refundExpiry;
        /// @dev Minimum fee percentage in basis points
        uint16 minFeeBps;
        /// @dev Maximum fee percentage in basis points
        uint16 maxFeeBps;
        /// @dev Address that receives the fee portion of payments, if 0 then operator can set at capture
        address feeReceiver;
        /// @dev A source of entropy to ensure unique hashes across different payment details
        uint256 salt;
    }

    /// @notice State for tracking payments through lifecycle
    struct PaymentState {
        /// @dev True if payment has been authorized or charged
        bool hasCollected;
        /// @dev Amount of tokens currently on hold in escrow that can be captured
        uint120 capturable;
        /// @dev Amount of tokens previously captured that can be refunded
        uint120 refundable;
    }

    /// @notice State per unique payment
    mapping(bytes32 paymentDetailsHash => PaymentState state) _paymentState;

    /// @notice Emitted when a payment is charged and immediately captured
    event PaymentCharged(
        bytes32 indexed paymentDetailsHash,
        address operator,
        address payer,
        address receiver,
        address token,
        uint256 amount,
        address tokenCollector
    );

    /// @notice Emitted when authorized (escrowed) amount is increased
    event PaymentAuthorized(
        bytes32 indexed paymentDetailsHash,
        address operator,
        address payer,
        address receiver,
        address token,
        uint256 amount,
        address tokenCollector
    );

    /// @notice Emitted when payment is captured from escrow
    event PaymentCaptured(bytes32 indexed paymentDetailsHash, uint256 amount);

    /// @notice Emitted when an authorized payment is voided, returning any escrowed funds to the payer
    event PaymentVoided(bytes32 indexed paymentDetailsHash, uint256 amount, address sender);

    /// @notice Emitted when an authorized payment is reclaimed, returning any escrowed funds to the payer
    event PaymentReclaimed(bytes32 indexed paymentDetailsHash, uint256 amount);

    /// @notice Emitted when a captured payment is refunded
    event PaymentRefunded(bytes32 indexed paymentDetailsHash, uint256 amount, address tokenCollector, address sender);

    /// @notice Sender for a function call does not follow access control requirements
    error InvalidSender(address sender);

    /// @notice Token pull failed
    error TokenCollectionFailed();

    /// @notice Payment has already been authorized
    error PaymentAlreadyCollected(bytes32 paymentDetailsHash);

    /// @notice Payment authorization is insufficient for a requested capture
    error InsufficientAuthorization(bytes32 paymentDetailsHash, uint256 authorizedAmount, uint256 requestedAmount);

    /// @notice Requested authorization amount exceeds `PaymentDetails.maxAmount`
    error ExceedsMaxAmount(uint256 amount, uint256 maxAmount);

    /// @notice Authorization attempted after pre-approval expiry
    error AfterPreApprovalExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Expiry timestamps violate preApproval <= authorization <= refund
    error InvalidExpiries(uint48 preApproval, uint48 authorization, uint48 refund);

    /// @notice Capture attempted at or after authorization expiry
    error AfterAuthorizationExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Reclaim attempted before authorization expiry
    error BeforeAuthorizationExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Refund attempted at or after refund expiry
    error AfterRefundExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Refund attempt exceeds captured amount
    error RefundExceedsCapture(uint256 refund, uint256 captured);

    /// @notice Fee bips overflows 10_000 maximum
    error FeeBpsOverflow(uint16 feeBps);

    /// @notice Fee recipient is zero address
    error ZeroFeeRecipient();

    /// @notice Amount is zero
    error ZeroAmount();

    /// @notice Amount overflows allowed storage size of uint120
    error AmountOverflow(uint256 amount, uint256 limit);

    /// @notice Authorization is zero
    error ZeroAuthorization(bytes32 paymentDetailsHash);

    /// @notice Fee bps range invalid due to min > max
    error InvalidFeeBpsRange(uint16 minFeeBps, uint16 maxFeeBps);

    /// @notice Fee bps outside of allowed range
    error FeeBpsOutOfRange(uint16 feeBps, uint16 minFeeBps, uint16 maxFeeBps);

    /// @notice Fee recipient cannot be changed
    error InvalidFeeRecipient(address attempted, address expected);

    /// @notice Token collector is not valid for the operation
    error InvalidCollectorForOperation();

    bytes32 public constant PAYMENT_DETAILS_TYPEHASH = keccak256(
        "PaymentDetails(address operator,address payer,address receiver,address token,uint256 maxAmount,uint48 preApprovalExpiry,uint48 authorizationExpiry,uint48 refundExpiry,uint16 minFeeBps,uint16 maxFeeBps,address feeReceiver,uint256 salt)"
    );

    /// @notice Ensures amount is non-zero and does not overflow storage
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        if (amount > type(uint120).max) revert AmountOverflow(amount, type(uint120).max);
        _;
    }

    /// @notice Transfers funds from payer to receiver in one step
    /// @dev If amount is less than the authorized amount, only amount is taken from payer
    /// @dev Reverts if the authorization has been voided or expired
    /// @param paymentDetails PaymentDetails struct
    /// @param amount Amount to charge and capture
    /// @param tokenCollector Address of the token collector
    /// @param collectorData Data to pass to the token collector
    /// @param feeBps Fee percentage to apply (must be within min/max range)
    /// @param feeReceiver Address to receive fees (can only be set if original feeReceiver was 0)
    function charge(
        PaymentDetails calldata paymentDetails,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData,
        uint16 feeBps,
        address feeReceiver
    ) external validAmount(amount) {
        // check sender is operator
        if (msg.sender != paymentDetails.operator) revert InvalidSender(msg.sender);

        // check payment not already collected
        bytes32 paymentDetailsHash = getHash(paymentDetails);
        if (_paymentState[paymentDetailsHash].hasCollected) revert PaymentAlreadyCollected(paymentDetailsHash);

        // validate payment details
        _validatePayment(paymentDetails, amount);

        // validate fee parameters
        _validateFee(paymentDetails, feeBps, feeReceiver);

        // update captured amount for refund accounting
        _paymentState[paymentDetailsHash].refundable = uint120(amount);
        emit PaymentCharged(
            paymentDetailsHash,
            paymentDetails.operator,
            paymentDetails.payer,
            paymentDetails.receiver,
            paymentDetails.token,
            amount,
            tokenCollector
        );

        // transfer tokens into escrow
        _collectTokens(paymentDetails, amount, tokenCollector, collectorData, TokenCollector.CollectorType.Payment);

        // distribute tokens to capture address and fee recipient
        _distributeTokens(paymentDetails.token, paymentDetails.receiver, amount, feeBps, feeReceiver);
    }

    /// @notice Transfers funds from payer to escrow
    /// @param paymentDetails PaymentDetails struct
    /// @param amount Amount to authorize
    /// @param collectorData Data to pass to the token collector
    function authorize(
        PaymentDetails calldata paymentDetails,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external validAmount(amount) {
        // check sender is operator
        if (msg.sender != paymentDetails.operator) revert InvalidSender(msg.sender);

        // check payment not already collected
        bytes32 paymentDetailsHash = getHash(paymentDetails);
        if (_paymentState[paymentDetailsHash].hasCollected) revert PaymentAlreadyCollected(paymentDetailsHash);

        // validate payment details
        _validatePayment(paymentDetails, amount);

        // set payment state
        _paymentState[paymentDetailsHash] =
            PaymentState({hasCollected: true, capturable: uint120(amount), refundable: 0});
        emit PaymentAuthorized(
            paymentDetailsHash,
            paymentDetails.operator,
            paymentDetails.payer,
            paymentDetails.receiver,
            paymentDetails.token,
            amount,
            tokenCollector
        );

        // transfer tokens into escrow
        _collectTokens(paymentDetails, amount, tokenCollector, collectorData, TokenCollector.CollectorType.Payment);
    }

    /// @notice Transfer previously-escrowed funds to receiver
    /// @dev Can be called multiple times up to cumulative authorized amount
    /// @dev Can only be called by the operator
    /// @param paymentDetails PaymentDetails struct
    /// @param amount Amount to capture
    /// @param feeBps Fee percentage to apply (must be within min/max range)
    /// @param feeReceiver Address to receive fees (can only be set if original feeReceiver was 0)
    function capture(PaymentDetails calldata paymentDetails, uint256 amount, uint16 feeBps, address feeReceiver)
        external
        validAmount(amount)
    {
        // check sender is operator
        if (msg.sender != paymentDetails.operator) {
            revert InvalidSender(msg.sender);
        }

        // check before authorization expiry
        if (block.timestamp >= paymentDetails.authorizationExpiry) {
            revert AfterAuthorizationExpiry(uint48(block.timestamp), paymentDetails.authorizationExpiry);
        }

        // check sufficient escrow to capture
        bytes32 paymentDetailsHash = getHash(paymentDetails);
        PaymentState memory state = _paymentState[paymentDetailsHash];
        if (state.capturable < amount) revert InsufficientAuthorization(paymentDetailsHash, state.capturable, amount);

        // validate fee parameters
        _validateFee(paymentDetails, feeBps, feeReceiver);

        // update state
        state.capturable -= uint120(amount);
        state.refundable += uint120(amount);
        _paymentState[paymentDetailsHash] = state;
        emit PaymentCaptured(paymentDetailsHash, amount);

        // distribute tokens including fees
        _distributeTokens(paymentDetails.token, paymentDetails.receiver, amount, feeBps, feeReceiver);
    }

    /// @notice Permanently voids a payment authorization
    /// @dev Returns any escrowed funds to payer
    /// @dev Can only be called by the operator or receiver
    /// @param paymentDetails PaymentDetails struct
    function void(PaymentDetails calldata paymentDetails) external {
        // check sender is operator or receiver
        if (msg.sender != paymentDetails.operator && msg.sender != paymentDetails.receiver) {
            revert InvalidSender(msg.sender);
        }

        // check authorization non-zero
        bytes32 paymentDetailsHash = getHash(paymentDetails);
        uint256 authorizedAmount = _paymentState[paymentDetailsHash].capturable;
        if (authorizedAmount == 0) revert ZeroAuthorization(paymentDetailsHash);

        // clear capturable state
        _paymentState[paymentDetailsHash].capturable = 0;
        emit PaymentVoided(paymentDetailsHash, authorizedAmount, msg.sender);

        // transfer tokens to payer
        SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.payer, authorizedAmount);
    }

    /// @notice Returns any escrowed funds to payer
    /// @dev Can only be called by the payer and only after the authorization expiry
    /// @param paymentDetails PaymentDetails struct
    function reclaim(PaymentDetails calldata paymentDetails) external {
        // check sender is payer
        if (msg.sender != paymentDetails.payer) {
            revert InvalidSender(msg.sender);
        }

        // check not before authorization expiry
        if (block.timestamp < paymentDetails.authorizationExpiry) {
            revert BeforeAuthorizationExpiry(uint48(block.timestamp), paymentDetails.authorizationExpiry);
        }

        // check authorization non-zero
        bytes32 paymentDetailsHash = getHash(paymentDetails);
        uint256 authorizedAmount = _paymentState[paymentDetailsHash].capturable;
        if (authorizedAmount == 0) revert ZeroAuthorization(paymentDetailsHash);

        // clear capturable state
        _paymentState[paymentDetailsHash].capturable = 0;
        emit PaymentReclaimed(paymentDetailsHash, authorizedAmount);

        // transfer tokens to payer
        SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.payer, authorizedAmount);
    }

    /// @notice Return previously-captured tokens to payer
    /// @dev Can be called by operator or receiver
    /// @dev Funds are transferred from the caller or from the escrow if token collector retrieves external liquidity
    /// @param paymentDetails PaymentDetails struct
    /// @param amount Amount to refund
    /// @param tokenCollector Address of the token collector
    /// @param collectorData Data to pass to the token collector
    function refund(
        PaymentDetails calldata paymentDetails,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external validAmount(amount) {
        // check sender is operator or original payment receiver
        if (msg.sender != paymentDetails.operator && msg.sender != paymentDetails.receiver) {
            revert InvalidSender(msg.sender);
        }

        // check refund has not expired
        if (block.timestamp >= paymentDetails.refundExpiry) {
            revert AfterRefundExpiry(uint48(block.timestamp), paymentDetails.refundExpiry);
        }

        // limit refund amount to previously captured
        bytes32 paymentDetailsHash = getHash(paymentDetails);
        uint120 captured = _paymentState[paymentDetailsHash].refundable;
        if (captured < amount) revert RefundExceedsCapture(amount, captured);

        // update capturable amount
        _paymentState[paymentDetailsHash].refundable = captured - uint120(amount);
        emit PaymentRefunded(paymentDetailsHash, amount, tokenCollector, msg.sender);

        if (tokenCollector != address(0)) {
            // collect tokens into escrow then transfer to original payer
            _collectTokens(paymentDetails, amount, tokenCollector, collectorData, TokenCollector.CollectorType.Refund);
            SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.payer, amount);
        } else {
            // transfer tokens from caller to original payer
            SafeTransferLib.safeTransferFrom(paymentDetails.token, msg.sender, paymentDetails.payer, amount);
        }
    }

    /// @notice Check if a payment has been authorized
    /// @param paymentDetailsHash Hash of the payment details
    /// @return True if the payment has been authorized
    function hasCollected(bytes32 paymentDetailsHash) external view returns (bool) {
        return _paymentState[paymentDetailsHash].hasCollected;
    }

    /// @notice Get the amount of tokens currently authorized (held in escrow)
    /// @param paymentDetailsHash Hash of the payment details
    /// @return Amount of tokens authorized
    function getCapturableAmount(bytes32 paymentDetailsHash) external view returns (uint120) {
        return _paymentState[paymentDetailsHash].capturable;
    }

    /// @notice Get the amount of tokens that have been captured
    /// @param paymentDetailsHash Hash of the payment details
    /// @return Amount of tokens captured
    function getRefundableAmount(bytes32 paymentDetailsHash) external view returns (uint120) {
        return _paymentState[paymentDetailsHash].refundable;
    }

    /// @notice Get hash of PaymentDetails struct
    /// @param paymentDetails PaymentDetails struct
    /// @return hash Hash of payment details for the current chain and contract address
    function getHash(PaymentDetails calldata paymentDetails) public view returns (bytes32) {
        bytes32 detailsHash = keccak256(
            abi.encode(
                PAYMENT_DETAILS_TYPEHASH,
                paymentDetails.operator,
                paymentDetails.payer,
                paymentDetails.receiver,
                paymentDetails.token,
                paymentDetails.maxAmount,
                paymentDetails.preApprovalExpiry,
                paymentDetails.authorizationExpiry,
                paymentDetails.refundExpiry,
                paymentDetails.minFeeBps,
                paymentDetails.maxFeeBps,
                paymentDetails.feeReceiver,
                paymentDetails.salt
            )
        );
        return keccak256(abi.encode(block.chainid, address(this), detailsHash));
    }

    /// @notice Transfer tokens into this contract
    function _collectTokens(
        PaymentDetails calldata paymentDetails,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData,
        TokenCollector.CollectorType collectorType
    ) internal {
        if (TokenCollector(tokenCollector).getCollectorType() != collectorType) {
            revert InvalidCollectorForOperation();
        }
        uint256 escrowBalanceBefore = IERC20(paymentDetails.token).balanceOf(address(this));
        TokenCollector(tokenCollector).collectTokens(paymentDetails, amount, collectorData);
        uint256 escrowBalanceAfter = IERC20(paymentDetails.token).balanceOf(address(this));
        if (escrowBalanceAfter - escrowBalanceBefore != amount) revert TokenCollectionFailed();
    }

    /// @notice Sends tokens to receiver and/or feeReceiver
    /// @param token Token to transfer
    /// @param receiver Address to receive payment
    /// @param feeReceiver Address to receive fees
    /// @param feeBps Fee percentage in basis points
    /// @param amount Total amount to split between payment and fees
    function _distributeTokens(address token, address receiver, uint256 amount, uint16 feeBps, address feeReceiver)
        internal
    {
        uint256 feeAmount = uint256(amount) * feeBps / 10_000;
        if (feeAmount > 0) SafeTransferLib.safeTransfer(token, feeReceiver, feeAmount);
        if (amount - feeAmount > 0) SafeTransferLib.safeTransfer(token, receiver, amount - feeAmount);
    }

    /// @notice Validates required properties of a payment
    function _validatePayment(PaymentDetails calldata paymentDetails, uint256 amount) internal view {
        // check amount does not exceed maximum
        if (amount > paymentDetails.maxAmount) revert ExceedsMaxAmount(amount, paymentDetails.maxAmount);

        // check timestamp before pre-approval expiry
        if (block.timestamp >= paymentDetails.preApprovalExpiry) {
            revert AfterPreApprovalExpiry(uint48(block.timestamp), uint48(paymentDetails.preApprovalExpiry));
        }

        // check expiry timestamps properly ordered
        if (
            paymentDetails.preApprovalExpiry > paymentDetails.authorizationExpiry
                || paymentDetails.authorizationExpiry > paymentDetails.refundExpiry
        ) {
            revert InvalidExpiries(
                paymentDetails.preApprovalExpiry, paymentDetails.authorizationExpiry, paymentDetails.refundExpiry
            );
        }

        // check fee bps do not exceed maximum value
        if (paymentDetails.maxFeeBps > 10_000) revert FeeBpsOverflow(paymentDetails.maxFeeBps);

        // check min fee bps does not exceed max
        if (paymentDetails.minFeeBps > paymentDetails.maxFeeBps) {
            revert InvalidFeeBpsRange(paymentDetails.minFeeBps, paymentDetails.maxFeeBps);
        }
    }

    /// @notice Validates attempted fee adheres to constraints set by payment details.
    function _validateFee(PaymentDetails calldata paymentDetails, uint16 feeBps, address feeReceiver) internal pure {
        // check fee bps within [min, max]
        if (feeBps < paymentDetails.minFeeBps || feeBps > paymentDetails.maxFeeBps) {
            revert FeeBpsOutOfRange(feeBps, paymentDetails.minFeeBps, paymentDetails.maxFeeBps);
        }

        // check fee recipient only zero address if zero fee bps
        if (feeBps > 0 && feeReceiver == address(0)) revert ZeroFeeRecipient();

        // check fee recipient matches payment details if non-zero
        if (paymentDetails.feeReceiver != address(0) && paymentDetails.feeReceiver != feeReceiver) {
            revert InvalidFeeRecipient(feeReceiver, paymentDetails.feeReceiver);
        }
    }
}
