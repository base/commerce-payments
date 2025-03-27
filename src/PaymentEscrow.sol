// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC3009} from "./interfaces/IERC3009.sol";
import {IMulticall3} from "./interfaces/IMulticall3.sol";
import {IPullTokensHook} from "./interfaces/IPullTokensHook.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title PaymentEscrow
/// @notice Facilitate payments through an escrow.
/// @dev By escrowing payment, this contract can mimic the 2-step payment pattern of "authorization" and "capture".
/// @dev Authorization is defined as placing a hold on a buyer's funds temporarily.
/// @dev Capture is defined as distributing payment to the end recipient.
/// @dev An Operator plays the primary role of moving payments between both parties.
/// @author Coinbase
contract PaymentEscrow {
    /// @notice Payment details, contains all information required to authorize and capture a unique payment
    struct PaymentDetails {
        /// @dev Entity responsible for driving payment flow
        address operator;
        /// @dev The buyer's address authorizing the payment
        address payer;
        /// @dev Address that receives the payment (minus fees)
        address receiver;
        /// @dev The ERC-3009 token contract address
        address token;
        /// @dev The amount of tokens that will be transferred from the buyer to the escrow
        uint256 value;
        /// @dev Timestamp when the payer's pre-approval can no longer authorize payment
        uint48 preApprovalExpiry;
        /// @dev Timestamp when an authorization can no longer be captured and the buyer can reclaim from escrow
        uint48 authorizationExpiry;
        /// @dev Minimum fee percentage in basis points
        uint16 minFeeBps;
        /// @dev Maximum fee percentage in basis points
        uint16 maxFeeBps;
        /// @dev Address that receives the fee portion of payments, if 0 then operator can set at capture
        address feeRecipient;
        /// @dev A source of entropy to ensure unique hashes across different payment details
        uint256 salt;
        /// @dev Contract implementing token pull logic
        address pullTokensHook;
    }

    /// @notice State for tracking payments through lifecycle
    struct PaymentState {
        /// @dev True if payment has been authorized or charged
        bool isAuthorized;
        /// @dev Value of tokens currently on hold in escrow that can be captured
        uint120 capturable;
        /// @dev Value of tokens previously captured that can be refunded
        uint120 refundable;
    }

    /// @notice ERC-6492 magic value
    bytes32 public constant ERC6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;

    /// @notice Public Multicall3 contract, used to apply ERC-6492 preparation data
    IMulticall3 public immutable multicall3;

    /// @notice State per unique payment
    mapping(bytes32 paymentDetailsHash => PaymentState state) _paymentState;

    /// @notice Emitted when a payment is charged and immediately captured
    event PaymentCharged(
        bytes32 indexed paymentDetailsHash,
        address operator,
        address buyer,
        address captureAddress,
        address token,
        uint256 value
    );

    /// @notice Emitted when authorized (escrowed) value is increased
    event PaymentAuthorized(
        bytes32 indexed paymentDetailsHash,
        address operator,
        address buyer,
        address captureAddress,
        address token,
        uint256 value
    );

    /// @notice Emitted when payment is captured from escrow
    event PaymentCaptured(bytes32 indexed paymentDetailsHash, uint256 value, address sender);

    /// @notice Emitted when an authorized payment is voided, returning any escrowed funds to the buyer
    event PaymentVoided(bytes32 indexed paymentDetailsHash, uint256 value, address sender);

    /// @notice Emitted when an authorized payment is reclaimed, returning any escrowed funds to the buyer
    event PaymentReclaimed(bytes32 indexed paymentDetailsHash, uint256 value);

    /// @notice Emitted when a captured payment is refunded
    event PaymentRefunded(bytes32 indexed paymentDetailsHash, uint256 value, address sender);

    /// @notice Sender for a function call does not follow access control requirements
    error InvalidSender(address sender);

    /// @notice Token pull failed
    error TokenPullFailed();

    /// @notice Payment has already been authorized
    error PaymentAlreadyAuthorized(bytes32 paymentDetailsHash);

    /// @notice Payment authorization is insufficient for a requested capture
    error InsufficientAuthorization(bytes32 paymentDetailsHash, uint256 authorizedValue, uint256 requestedValue);

    /// @notice Requested authorization value exceeds limit on payment details
    error ValueLimitExceeded(uint256 value);

    /// @notice Authorization attempted after pre-approval expiry
    error AfterPreApprovalExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Pre-approval expiry after authorization expiry
    error InvalidExpiries(uint48 preApproval, uint48 authorization);

    /// @notice Capture attempted after authorization expiry
    error AfterAuthorizationExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Reclaim attempted before authorization expiry
    error BeforeAuthorizationExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Refund attempt exceeds captured value
    error RefundExceedsCapture(uint256 refund, uint256 captured);

    /// @notice Fee bips overflows 10_000 maximum
    error FeeBpsOverflow(uint16 feeBps);

    /// @notice Fee recipient is zero address
    error ZeroFeeRecipient();

    /// @notice Value is zero
    error ZeroValue();

    /// @notice Value overflows allowed storage size of uint120
    error ValueOverflow(uint256 value, uint256 limit);

    /// @notice Authorization is zero
    error ZeroAuthorization(bytes32 paymentDetailsHash);

    /// @notice Fee bps range invalid due to min > max
    error InvalidFeeBpsRange(uint16 minFeeBps, uint16 maxFeeBps);

    /// @notice Fee bps outside of allowed range
    error FeeBpsOutOfRange(uint16 feeBps, uint16 minFeeBps, uint16 maxFeeBps);

    /// @notice Fee recipient cannot be changed
    error InvalidFeeRecipient(address attempted, address expected);

    /// @notice Ensures value is non-zero and does not overflow storage
    modifier validValue(uint256 value) {
        if (value == 0) revert ZeroValue();
        if (value > type(uint120).max) revert ValueOverflow(value, type(uint120).max);
        _;
    }

    /// @notice Initialize contract with ERC6492 Executor
    /// @param _multicall3 Address of the Executor contract
    constructor(address _multicall3) {
        multicall3 = IMulticall3(_multicall3);
    }

    /// @notice Check if a payment has been authorized
    /// @param paymentDetailsHash Hash of the payment details
    /// @return True if the payment has been authorized
    function isAuthorized(bytes32 paymentDetailsHash) external view returns (bool) {
        return _paymentState[paymentDetailsHash].isAuthorized;
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

    /// @notice Transfers funds from buyer to captureAddress in one step
    /// @dev If value is less than the authorized value, difference is returned to buyer
    /// @dev Reverts if the authorization has been voided or expired
    /// @param value Amount to charge and capture
    /// @param paymentDetails PaymentDetails struct
    /// @param feeBps Fee percentage to apply (must be within min/max range)
    /// @param feeRecipient Address to receive fees (can only be set if original feeRecipient was 0)
    /// @param signature Authorization signature from buyer
    function charge(
        uint256 value,
        PaymentDetails calldata paymentDetails,
        bytes calldata signature,
        bytes calldata hookData,
        uint16 feeBps,
        address feeRecipient
    ) external validValue(value) {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // check sender is operator
        if (msg.sender != paymentDetails.operator) revert InvalidSender(msg.sender);

        // validate payment details
        _validatePaymentDetails(paymentDetails, paymentDetailsHash, value);

        // validate fee parameters
        _validateFee(paymentDetails, feeBps, feeRecipient);

        // update captured amount for refund accounting
        _paymentState[paymentDetailsHash].refundable = uint120(value);
        emit PaymentCharged(
            paymentDetailsHash,
            paymentDetails.operator,
            paymentDetails.payer,
            paymentDetails.receiver,
            paymentDetails.token,
            value
        );

        // transfer tokens into escrow
        _pullTokens(paymentDetails, paymentDetailsHash, value, signature, hookData);

        // distribute tokens to capture address and fee recipient
        _distributeTokens(paymentDetails.token, paymentDetails.receiver, feeRecipient, feeBps, value);
    }

    /// @notice Transfers funds from buyer to escrow
    /// @param value Amount to authorize
    /// @param paymentDetails PaymentDetails struct
    /// @param signature Signature of the buyer authorizing the payment
    function authorize(
        uint256 value,
        PaymentDetails calldata paymentDetails,
        bytes calldata signature,
        bytes calldata hookData
    ) external validValue(value) {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // check sender is operator
        if (msg.sender != paymentDetails.operator) revert InvalidSender(msg.sender);

        // validate payment details
        _validatePaymentDetails(paymentDetails, paymentDetailsHash, value);

        // check if payment is already authorized
        if (_paymentState[paymentDetailsHash].isAuthorized) {
            revert PaymentAlreadyAuthorized(paymentDetailsHash);
        }

        // update authorized amount for capture accounting
        _paymentState[paymentDetailsHash].capturable = uint120(value);

        // transfer tokens into escrow
        _pullTokens(paymentDetails, paymentDetailsHash, value, signature, hookData);

        _paymentState[paymentDetailsHash].isAuthorized = true;
        emit PaymentAuthorized(
            paymentDetailsHash,
            paymentDetails.operator,
            paymentDetails.payer,
            paymentDetails.receiver,
            paymentDetails.token,
            value
        );
    }

    /// @notice Transfer previously-escrowed funds to captureAddress
    /// @dev Can be called multiple times up to cumulative authorized amount
    /// @dev Can only be called by the operator
    /// @param value Amount to capture
    /// @param paymentDetails PaymentDetails struct
    /// @param feeBps Fee percentage to apply (must be within min/max range)
    /// @param feeRecipient Address to receive fees (can only be set if original feeRecipient was 0)
    function capture(uint256 value, PaymentDetails calldata paymentDetails, uint16 feeBps, address feeRecipient)
        external
        validValue(value)
    {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // check sender is operator
        if (msg.sender != paymentDetails.operator) {
            revert InvalidSender(msg.sender);
        }

        // check before authorization expiry
        if (block.timestamp >= paymentDetails.authorizationExpiry) {
            revert AfterAuthorizationExpiry(uint48(block.timestamp), paymentDetails.authorizationExpiry);
        }

        // validate fee parameters
        _validateFee(paymentDetails, feeBps, feeRecipient);

        // check sufficient escrow to capture
        PaymentState memory state = _paymentState[paymentDetailsHash];
        if (state.capturable < value) revert InsufficientAuthorization(paymentDetailsHash, state.capturable, value);

        // update state
        state.capturable -= uint120(value);
        state.refundable += uint120(value);
        _paymentState[paymentDetailsHash] = state;
        emit PaymentCaptured(paymentDetailsHash, value, msg.sender);

        // distribute tokens including fees
        _distributeTokens(paymentDetails.token, paymentDetails.receiver, feeRecipient, feeBps, value);
    }

    /// @notice Permanently voids a payment authorization
    /// @dev Returns any escrowed funds to buyer
    /// @dev Can only be called by the operator or captureAddress
    /// @param paymentDetails PaymentDetails struct
    function void(PaymentDetails calldata paymentDetails) external {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // check sender is operator or captureAddress
        if (msg.sender != paymentDetails.operator && msg.sender != paymentDetails.receiver) {
            revert InvalidSender(msg.sender);
        }

        // check authorization non-zero
        uint256 authorizedValue = _paymentState[paymentDetailsHash].capturable;
        if (authorizedValue == 0) revert ZeroAuthorization(paymentDetailsHash);

        // return any escrowed funds
        _paymentState[paymentDetailsHash].capturable = 0;
        emit PaymentVoided(paymentDetailsHash, authorizedValue, msg.sender);
        SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.payer, authorizedValue);
    }

    /// @notice Returns any escrowed funds to buyer
    /// @dev Can only be called by the buyer and only after the authorization expiry
    /// @param paymentDetails PaymentDetails struct
    function reclaim(PaymentDetails calldata paymentDetails) external {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // check sender is buyer
        if (msg.sender != paymentDetails.payer) {
            revert InvalidSender(msg.sender);
        }

        // check not before authorization expiry
        if (block.timestamp < paymentDetails.authorizationExpiry) {
            revert BeforeAuthorizationExpiry(uint48(block.timestamp), paymentDetails.authorizationExpiry);
        }

        // check authorization non-zero
        uint256 authorizedValue = _paymentState[paymentDetailsHash].capturable;
        if (authorizedValue == 0) revert ZeroAuthorization(paymentDetailsHash);

        // return any escrowed funds
        _paymentState[paymentDetailsHash].capturable = 0;
        emit PaymentReclaimed(paymentDetailsHash, authorizedValue);
        SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.payer, authorizedValue);
    }

    /// @notice Return previously-captured tokens to buyer
    /// @dev Can be called by operator or receiver
    /// @dev Funds are transferred from the caller
    /// @param value Amount to refund
    /// @param paymentDetails PaymentDetails struct
    function refund(uint256 value, PaymentDetails calldata paymentDetails) external validValue(value) {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // validate refund
        _refund(value, paymentDetails.operator, paymentDetails.receiver, paymentDetailsHash);

        // return tokens to buyer
        SafeTransferLib.safeTransferFrom(paymentDetails.token, msg.sender, paymentDetails.payer, value);
    }

    /// @notice Return previously-captured tokens to buyer
    /// @dev Can be called by operator or captureAddress
    /// @dev Funds are transferred from the sponsor via ERC-3009 authorization
    /// @dev The value to refund and the value authorized in the ERC-3009 authorization must be identical
    /// @param value Amount to refund
    /// @param paymentDetails PaymentDetails struct
    function refundWithSponsor(
        uint256 value,
        PaymentDetails calldata paymentDetails,
        address sponsor,
        uint48 refundDeadline,
        uint256 refundSalt,
        bytes calldata signature
    ) external validValue(value) {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // validate refund
        _refund(value, paymentDetails.operator, paymentDetails.receiver, paymentDetailsHash);

        // pull the refund amount from the sponsor
        _receiveWithAuthorization({
            token: paymentDetails.token,
            from: sponsor,
            value: value,
            validBefore: refundDeadline,
            nonce: keccak256(abi.encode(keccak256(abi.encode(paymentDetails)), refundSalt)),
            signature: signature
        });

        // return tokens to buyer
        SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.payer, value);
    }

    /// @notice Validates required properties of a payment
    function _validatePaymentDetails(PaymentDetails calldata paymentDetails, bytes32 paymentDetailsHash, uint256 value)
        internal
        view
    {
        if (value > paymentDetails.value) revert ValueLimitExceeded(value);
        if (block.timestamp >= paymentDetails.preApprovalExpiry) {
            revert AfterPreApprovalExpiry(uint48(block.timestamp), uint48(paymentDetails.preApprovalExpiry));
        }
        if (paymentDetails.preApprovalExpiry > paymentDetails.authorizationExpiry) {
            revert InvalidExpiries(uint48(paymentDetails.preApprovalExpiry), paymentDetails.authorizationExpiry);
        }
        if (paymentDetails.maxFeeBps > 10_000) revert FeeBpsOverflow(paymentDetails.maxFeeBps);
        if (paymentDetails.minFeeBps > paymentDetails.maxFeeBps) {
            revert InvalidFeeBpsRange(paymentDetails.minFeeBps, paymentDetails.maxFeeBps);
        }
        if (_paymentState[paymentDetailsHash].isAuthorized) revert PaymentAlreadyAuthorized(paymentDetailsHash);
    }

    /// @notice Transfer tokens into this contract
    function _pullTokens(
        PaymentDetails calldata paymentDetails,
        bytes32 paymentDetailsHash,
        uint256 value,
        bytes calldata signature,
        bytes calldata hookData
    ) internal {
        uint256 escrowBalanceBefore = IERC20(paymentDetails.token).balanceOf(address(this));
        IPullTokensHook(paymentDetails.pullTokensHook).pullTokens(
            paymentDetails, paymentDetailsHash, value, signature, hookData
        );
        uint256 escrowBalanceAfter = IERC20(paymentDetails.token).balanceOf(address(this));
        if (escrowBalanceAfter - escrowBalanceBefore != value) revert TokenPullFailed();
    }

    /// @notice Sends tokens to captureAddress and/or feeRecipient
    /// @param token Token to transfer
    /// @param captureAddress Address to receive payment
    /// @param feeRecipient Address to receive fees
    /// @param feeBps Fee percentage in basis points
    /// @param value Total amount to split between payment and fees
    function _distributeTokens(
        address token,
        address captureAddress,
        address feeRecipient,
        uint16 feeBps,
        uint256 value
    ) internal {
        uint256 feeAmount = uint256(value) * feeBps / 10_000;
        if (feeAmount > 0) SafeTransferLib.safeTransfer(token, feeRecipient, feeAmount);
        if (value - feeAmount > 0) SafeTransferLib.safeTransfer(token, captureAddress, value - feeAmount);
    }

    /// @notice Use ERC-3009 receiveWithAuthorization with optional ERC-6492 preparation call
    function _receiveWithAuthorization(
        address token,
        address from,
        uint256 value,
        uint48 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) internal {
        bytes memory innerSignature = signature;
        if (signature.length >= 32 && bytes32(signature[signature.length - 32:]) == ERC6492_MAGIC_VALUE) {
            // parse inner signature from ERC-6492 format
            address target;
            bytes memory prepareData;
            (target, prepareData, innerSignature) =
                abi.decode(signature[0:signature.length - 32], (address, bytes, bytes));

            // construct call to target with prepareData
            IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
            calls[0] = IMulticall3.Call(target, prepareData);
            multicall3.tryAggregate({requireSuccess: false, calls: calls});
        }

        // receive tokens from authorization signer
        IERC3009(token).receiveWithAuthorization({
            from: from,
            to: address(this),
            value: value,
            validAfter: 0,
            validBefore: validBefore,
            nonce: nonce,
            signature: innerSignature
        });
    }

    /// @notice Validate and update state for refund
    function _refund(uint256 value, address operator, address originalPaymentReceiver, bytes32 paymentDetailsHash)
        internal
    {
        // Check sender is operator or original payment receiver
        if (msg.sender != operator && msg.sender != originalPaymentReceiver) {
            revert InvalidSender(msg.sender);
        }

        // Limit refund value to previously captured
        uint120 captured = _paymentState[paymentDetailsHash].refundable;
        if (captured < value) revert RefundExceedsCapture(value, captured);

        _paymentState[paymentDetailsHash].refundable = captured - uint120(value);
        emit PaymentRefunded(paymentDetailsHash, value, msg.sender);
    }

    /// @notice Validates attempted fee adheres to constraints set by payment details.
    function _validateFee(PaymentDetails calldata paymentDetails, uint16 feeBps, address feeRecipient) internal pure {
        // check fee bps within [min, max]
        if (feeBps < paymentDetails.minFeeBps || feeBps > paymentDetails.maxFeeBps) {
            revert FeeBpsOutOfRange(feeBps, paymentDetails.minFeeBps, paymentDetails.maxFeeBps);
        }

        // check fee recipient only zero address if zero fee bps
        if (feeBps > 0 && feeRecipient == address(0)) revert ZeroFeeRecipient();

        // check fee recipient matches payment details if non-zero
        if (paymentDetails.feeRecipient != address(0) && paymentDetails.feeRecipient != feeRecipient) {
            revert InvalidFeeRecipient(feeRecipient, paymentDetails.feeRecipient);
        }
    }
}
