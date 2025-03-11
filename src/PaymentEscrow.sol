// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PublicERC6492Validator} from "spend-permissions/PublicERC6492Validator.sol";

import {IERC3009} from "./IERC3009.sol";

/// @notice Route and escrow payments using ERC-3009 authorizations.
/// @dev This contract handles payment flows where a buyer authorizes a future payment,
///      which can then be captured in parts or refunded by an operator.
/// @author Coinbase
contract PaymentEscrow {
    /// @notice Payment details stored by complete payment data hash
    struct PaymentDetails {
        address operator; // Primary actor who can call most functions
        address buyer; // Source of funds
        address token; // Token being transferred
        address captureAddress; // Destination for captured funds
        uint256 value; // Amount authorized
        uint48 captureDeadline; // When buyer can void
        address feeRecipient; // Optional fee destination
        uint16 feeBps; // Optional fee amount
    }

    /// @notice Full payment details stored by hash
    mapping(bytes32 => PaymentDetails) private _storedPaymentDetails;

    /// @notice ERC-6492 magic value
    bytes32 public constant ERC6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;

    /// @notice Validator contract for processing ERC-6492 signatures
    PublicERC6492Validator public immutable erc6492Validator;

    /// @notice Authorization state for a specific 3009 authorization.
    /// @dev Used to track whether an authorization has been voided or expired, and to limit amount that can
    ///      be captured or refunded from escrow.
    mapping(bytes32 paymentDetailsHash => uint256 value) internal _authorized;

    /// @notice Amount of tokens captured for a specific 3009 authorization.
    /// @dev Used to limit amount that can be refunded post-capture.
    mapping(bytes32 paymentDetailsHash => uint256 value) internal _captured;

    /// @notice Whether or not a payment has been voided.
    /// @dev Prevents future authorization and captures for this payment if voided.
    mapping(bytes32 paymentDetailsHash => bool isVoided) internal _voided;

    /// @notice Emitted when a payment is charged and immediately captured
    event PaymentCharged(bytes32 indexed paymentDetailsHash, uint256 value);

    /// @notice Emitted when authorized (escrowed) value is increased
    event PaymentAuthorized(bytes32 indexed paymentDetailsHash, uint256 value);

    /// @notice Emitted when a payment authorization is voided, returning any escrowed funds to the buyer
    event PaymentVoided(bytes32 indexed paymentDetailsHash);

    /// @notice Emitted when payment is captured from escrow
    event PaymentCaptured(bytes32 indexed paymentDetailsHash, uint256 value);

    /// @notice Emitted when captured payment is refunded
    event PaymentRefunded(bytes32 indexed paymentDetailsHash, address indexed refunder, uint256 value);

    error InsufficientAuthorization(bytes32 paymentDetailsHash, uint256 authorizedValue, uint256 requestedValue);
    error ValueLimitExceeded(uint256 value);
    error PermissionApprovalFailed();
    error InvalidSender(address sender);
    error BeforeCaptureDeadline(uint48 timestamp, uint48 deadline);
    error AfterCaptureDeadline(uint48 timestamp, uint48 deadline);
    error RefundExceedsCapture(uint256 refund, uint256 captured);
    error FeeBpsOverflow(uint16 feeBps);
    error ZeroFeeRecipient();
    error ZeroValue();
    error VoidAuthorization(bytes32 paymentDetailsHash);
    error PaymentNotRegistered(bytes32 paymentHash);

    /// @notice Initialize contract with ERC6492 validator
    /// @param _erc6492Validator Address of the validator contract
    constructor(address _erc6492Validator) {
        erc6492Validator = PublicERC6492Validator(_erc6492Validator);
    }

    /// @notice Ensures value is not zero
    modifier validValue(uint256 value) {
        if (value == 0) revert ZeroValue();
        _;
    }

    receive() external payable {}

    /// @dev Computes payment hash and registers details if first time seeing this payment
    /// @return paymentHash The computed hash for this payment
    /// @return storedDetails Storage pointer to payment details (registered or existing)
    function _registerPaymentDetails(
        uint256 salt,
        PaymentDetails calldata details,
        uint256 validAfter,
        uint256 validBefore
    ) internal returns (bytes32 paymentHash, PaymentDetails storage storedDetails) {
        // Validate fee configuration upfront
        _validateFees(details.feeBps, details.feeRecipient);
        if (details.operator == address(0)) revert InvalidSender(address(0));

        paymentHash = keccak256(
            abi.encode(
                details.value,
                validAfter,
                validBefore,
                details.captureDeadline,
                details.operator,
                details.captureAddress,
                details.feeBps,
                details.feeRecipient,
                details.token,
                salt
            )
        );

        // Just store it - ERC3009 ensures we can't use same hash twice
        _storedPaymentDetails[paymentHash] = details;
        storedDetails = _storedPaymentDetails[paymentHash];
    }

    /// @dev Validates fee configuration
    function _validateFees(uint16 feeBps, address feeRecipient) internal pure {
        if (feeBps > 10_000) revert FeeBpsOverflow(feeBps);
        if (feeRecipient == address(0) && feeBps != 0) revert ZeroFeeRecipient();
    }

    /// @dev Validates operator and basic payment configuration
    function _validatePaymentConfig(PaymentDetails memory details, address sender) internal pure {
        if (sender != details.operator) revert InvalidSender(sender);
        if (details.operator == address(0)) revert InvalidSender(address(0));
    }

    /// @dev Validates capture deadline hasn't passed
    function _validateCaptureDeadline(uint48 captureDeadline) internal view {
        if (block.timestamp > captureDeadline) {
            revert AfterCaptureDeadline(uint48(block.timestamp), captureDeadline);
        }
    }

    /// @dev Validates payment hasn't been voided
    function _validateNotVoided(bytes32 paymentHash) internal view {
        if (_voided[paymentHash]) revert VoidAuthorization(paymentHash);
    }

    /// @dev Validates payment value against maximum
    function _validatePaymentValue(uint256 value, uint256 maxValue) internal view {
        if (value > maxValue) revert ValueLimitExceeded(value);
    }

    /// @dev Validates sender can refund (operator or captureAddress)
    function _validateRefundSender(PaymentDetails storage details, address sender) internal view {
        if (sender != details.operator && sender != details.captureAddress) {
            revert InvalidSender(sender);
        }
    }

    /// @dev Validates sender can void (buyer after deadline, operator, or captureAddress)
    function _validateVoidSender(PaymentDetails storage details, address sender) internal view {
        if (sender == details.buyer) {
            if (block.timestamp < details.captureDeadline) {
                revert BeforeCaptureDeadline(uint48(block.timestamp), details.captureDeadline);
            }
        } else if (sender != details.operator && sender != details.captureAddress) {
            revert InvalidSender(sender);
        }
    }

    /// @dev Validates sufficient authorized value for capture
    function _validateAuthorizedValue(bytes32 paymentHash, uint256 value) internal view {
        uint256 authorizedValue = _authorized[paymentHash];
        if (authorizedValue < value) {
            revert InsufficientAuthorization(paymentHash, authorizedValue, value);
        }
    }

    /// @dev Validates sufficient captured value for refund
    function _validateRefundValue(bytes32 paymentHash, uint256 value) internal view {
        uint256 captured = _captured[paymentHash];
        if (captured < value) revert RefundExceedsCapture(value, captured);
    }

    /// @notice Validates buyer signature and transfers funds from buyer to escrow
    /// @param salt Direct salt parameter
    /// @param details Full payment details (stored if first time seeing this payment)
    /// @param validAfter The earliest time the payment can be authorized
    /// @param validBefore The latest time the payment can be authorized
    /// @param value Amount to authorize
    /// @param signature Signature of the buyer authorizing the payment
    function authorize(
        uint256 salt,
        PaymentDetails calldata details,
        uint256 validAfter,
        uint256 validBefore,
        uint256 value,
        bytes calldata signature
    ) external validValue(value) {
        _validatePaymentConfig(details, msg.sender);
        if (value > details.value) revert ValueLimitExceeded(value);

        bytes32 paymentHash;
        PaymentDetails storage storedDetails;
        (paymentHash, storedDetails) = _registerPaymentDetails(salt, details, validAfter, validBefore);

        _validateNotVoided(paymentHash);
        _pullTokens(storedDetails, value, paymentHash, validAfter, validBefore, signature);

        _authorized[paymentHash] += value;
        emit PaymentAuthorized(paymentHash, value);
    }

    /// @notice Transfers funds from buyer to captureAddress in one step
    /// @param salt Direct salt parameter
    /// @param details Full payment details (stored if first time seeing this payment)
    /// @param value Amount to charge
    /// @param signature Signature of the buyer authorizing the payment
    function charge(uint256 salt, PaymentDetails calldata details, uint256 value, bytes calldata signature)
        external
        validValue(value)
    {
        _validatePaymentConfig(details, msg.sender);
        _validateCaptureDeadline(details.captureDeadline);
        if (value > details.value) revert ValueLimitExceeded(value);

        bytes32 paymentHash;
        PaymentDetails storage storedDetails;
        (paymentHash, storedDetails) = _registerPaymentDetails(salt, details, 0, 0);

        _validateNotVoided(paymentHash);
        _pullTokens(storedDetails, value, paymentHash, 0, 0, signature);

        _authorized[paymentHash] = 0;
        _captured[paymentHash] += value;
        emit PaymentCharged(paymentHash, value);

        _distributeTokens(details.token, details.captureAddress, details.feeRecipient, details.feeBps, value);
    }

    /// @notice Permanently voids a payment authorization
    /// @dev Returns any escrowed funds to buyer
    /// @param paymentHash Hash identifying the payment
    function void(bytes32 paymentHash) external {
        PaymentDetails storage details = _storedPaymentDetails[paymentHash];

        if (msg.sender == details.buyer) {
            if (block.timestamp < details.captureDeadline) {
                revert BeforeCaptureDeadline(uint48(block.timestamp), details.captureDeadline);
            }
        } else if (msg.sender != details.operator && msg.sender != details.captureAddress) {
            revert InvalidSender(msg.sender);
        }

        if (_voided[paymentHash]) return;

        _voided[paymentHash] = true;
        emit PaymentVoided(paymentHash);

        uint256 authorizedValue = _authorized[paymentHash];
        if (authorizedValue == 0) return;

        delete _authorized[paymentHash];
        SafeTransferLib.safeTransfer(details.token, details.buyer, authorizedValue);
    }

    /// @notice Transfers escrowed payment to merchant
    /// @dev Reverts if capture deadline has passed
    /// @param paymentHash Hash identifying the payment
    /// @param value Amount to capture
    function capture(bytes32 paymentHash, uint256 value) external validValue(value) {
        PaymentDetails storage details = _storedPaymentDetails[paymentHash];

        _validatePaymentConfig(details, msg.sender);
        _validateCaptureDeadline(details.captureDeadline);

        uint256 authorizedValue = _authorized[paymentHash];
        if (authorizedValue < value) {
            revert InsufficientAuthorization(paymentHash, authorizedValue, value);
        }

        _authorized[paymentHash] = authorizedValue - value;
        _captured[paymentHash] += value;
        emit PaymentCaptured(paymentHash, value);

        _distributeTokens(details.token, details.captureAddress, details.feeRecipient, details.feeBps, value);
    }

    /// @notice Return previously-captured tokens to buyer
    /// @dev Can be called by operator or captureAddress
    /// @param paymentHash Hash identifying the payment
    /// @param value Amount to refund
    function refund(bytes32 paymentHash, uint256 value) external validValue(value) {
        PaymentDetails storage details = _storedPaymentDetails[paymentHash];

        if (msg.sender != details.operator && msg.sender != details.captureAddress) {
            revert InvalidSender(msg.sender);
        }

        uint256 captured = _captured[paymentHash];
        if (captured < value) revert RefundExceedsCapture(value, captured);

        _captured[paymentHash] = captured - value;
        emit PaymentRefunded(paymentHash, msg.sender, value);

        SafeTransferLib.safeTransferFrom(details.token, msg.sender, details.buyer, value);
    }

    /// @notice Sends tokens to captureAddress and/or feeRecipient
    /// @param token Token to transfer
    /// @param captureAddress Address to receive payment
    /// @param feeRecipient Address to receive fees
    /// @param feeBps Fee percentage in basis points
    /// @param value Total amount to split between payment and fees
    /// @return remainingValue Amount after fees deducted
    function _distributeTokens(
        address token,
        address captureAddress,
        address feeRecipient,
        uint16 feeBps,
        uint256 value
    ) internal returns (uint256 remainingValue) {
        uint256 feeAmount = uint256(value) * feeBps / 10_000;
        remainingValue = value - feeAmount;

        if (feeAmount > 0) SafeTransferLib.safeTransfer(token, feeRecipient, feeAmount);
        if (remainingValue > 0) SafeTransferLib.safeTransfer(token, captureAddress, remainingValue);
    }

    function _pullTokens(
        PaymentDetails storage details,
        uint256 value,
        bytes32 paymentHash,
        uint256 validAfter,
        uint256 validBefore,
        bytes calldata signature
    ) internal {
        // parse signature to use for 3009 receiveWithAuthorization
        bytes memory innerSignature = signature;
        if (signature.length >= 32 && bytes32(signature[signature.length - 32:]) == ERC6492_MAGIC_VALUE) {
            // apply 6492 signature prepareData
            erc6492Validator.isValidSignatureNowAllowSideEffects(details.buyer, paymentHash, signature);
            // parse inner signature from 6492 format
            (,, innerSignature) = abi.decode(signature[0:signature.length - 32], (address, bytes, bytes));
        }

        // pull the full authorized amount from the buyer
        IERC3009(details.token).receiveWithAuthorization(
            details.buyer, address(this), details.value, validAfter, validBefore, paymentHash, innerSignature
        );

        // send excess funds back to buyer
        uint256 excessFunds = details.value - value;
        if (excessFunds > 0) SafeTransferLib.safeTransfer(details.token, details.buyer, excessFunds);
    }
}
