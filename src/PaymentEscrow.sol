// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "../lib/spend-permissions/lib/solady/src/utils/SafeTransferLib.sol";
import {PublicERC6492Validator} from "../lib/spend-permissions/src/PublicERC6492Validator.sol";

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
    error BeforeValidAfter(uint48 timestamp, uint48 validAfter);
    error AfterValidBefore(uint48 timestamp, uint48 validBefore);

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
    /// @return details Storage pointer to payment details (registered or existing)
    function _registerPaymentDetails(
        uint256 salt,
        PaymentDetails calldata details,
        uint256 validAfter,
        uint256 validBefore
    ) internal returns (bytes32 paymentHash, PaymentDetails storage storedDetails) {
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

        storedDetails = _storedPaymentDetails[paymentHash];

        if (storedDetails.operator == address(0)) {
            if (details.feeBps > 10_000) revert FeeBpsOverflow(details.feeBps);
            if (details.feeRecipient == address(0) && details.feeBps != 0) revert ZeroFeeRecipient();
            if (details.operator == address(0)) revert InvalidSender(address(0));

            _storedPaymentDetails[paymentHash] = details;
            storedDetails = _storedPaymentDetails[paymentHash];
        }
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
        bytes32 paymentHash;
        PaymentDetails storage storedDetails;
        (paymentHash, storedDetails) = _registerPaymentDetails(salt, details, validAfter, validBefore);

        if (msg.sender != storedDetails.operator) {
            revert InvalidSender(msg.sender);
        }

        // Validate timing constraints during authorization
        if (block.timestamp < validAfter) {
            revert BeforeValidAfter(uint48(block.timestamp), uint48(validAfter));
        }
        if (block.timestamp > validBefore) {
            revert AfterValidBefore(uint48(block.timestamp), uint48(validBefore));
        }

        // Validate value
        if (value > storedDetails.value) {
            revert ValueLimitExceeded(value);
        }

        // Check if authorization has been voided
        if (_voided[paymentHash]) {
            revert VoidAuthorization(paymentHash);
        }

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
        bytes32 paymentHash;
        PaymentDetails storage storedDetails;
        (paymentHash, storedDetails) = _registerPaymentDetails(salt, details, 0, 0);

        // check capture deadline
        if (block.timestamp > details.captureDeadline) {
            revert AfterCaptureDeadline(uint48(block.timestamp), uint48(details.captureDeadline));
        }

        // check sufficient escrow to capture
        uint256 authorizedValue = _authorized[paymentHash];
        if (authorizedValue < value) revert InsufficientAuthorization(paymentHash, authorizedValue, value);

        // update state
        _authorized[paymentHash] = authorizedValue - value;
        _captured[paymentHash] += value;
        emit PaymentCharged(paymentHash, value);

        // handle fees only for the actual charged amount
        _distributeTokens(details.token, details.captureAddress, details.feeRecipient, details.feeBps, value);
    }

    /// @notice Permanently voids a payment authorization
    /// @dev Returns any escrowed funds to buyer
    /// @param paymentHash Hash identifying the payment
    function void(bytes32 paymentHash) external {
        PaymentDetails storage details = _storedPaymentDetails[paymentHash];

        // Access control check
        if (msg.sender == details.buyer) {
            if (block.timestamp < details.captureDeadline) {
                revert BeforeCaptureDeadline(uint48(block.timestamp), details.captureDeadline);
            }
        } else if (msg.sender != details.operator && msg.sender != details.captureAddress) {
            revert InvalidSender(msg.sender);
        }

        // Early return if previously voided
        if (_voided[paymentHash]) return;

        // Mark the authorization as void
        _voided[paymentHash] = true;
        emit PaymentVoided(paymentHash);

        // Early return if no existing authorization escrowed
        uint256 authorizedValue = _authorized[paymentHash];
        if (authorizedValue == 0) return;

        // Return any escrowed funds
        delete _authorized[paymentHash];
        SafeTransferLib.safeTransfer(details.token, details.buyer, authorizedValue);
    }

    /// @notice Transfers escrowed payment to merchant
    /// @dev Reverts if capture deadline has passed
    /// @param paymentHash Hash identifying the payment
    /// @param value Amount to capture
    function capture(bytes32 paymentHash, uint256 value) external validValue(value) {
        PaymentDetails storage details = _storedPaymentDetails[paymentHash];

        // Validate operator
        if (msg.sender != details.operator) {
            revert InvalidSender(msg.sender);
        }

        // Check capture deadline
        if (block.timestamp > details.captureDeadline) {
            revert AfterCaptureDeadline(uint48(block.timestamp), details.captureDeadline);
        }

        // Check sufficient escrow to capture
        uint256 authorizedValue = _authorized[paymentHash];
        if (authorizedValue < value) {
            revert InsufficientAuthorization(paymentHash, authorizedValue, value);
        }

        // Update state
        _authorized[paymentHash] = authorizedValue - value;
        _captured[paymentHash] += value;
        emit PaymentCaptured(paymentHash, value);

        // Handle fees and distribute tokens
        _distributeTokens(details.token, details.captureAddress, details.feeRecipient, details.feeBps, value);
    }

    /// @notice Return previously-captured tokens to buyer
    /// @dev Can be called by operator or captureAddress
    /// @param paymentHash Hash identifying the payment
    /// @param value Amount to refund
    function refund(bytes32 paymentHash, uint256 value) external validValue(value) {
        PaymentDetails storage details = _storedPaymentDetails[paymentHash];

        // Check sender is operator or captureAddress
        if (msg.sender != details.operator && msg.sender != details.captureAddress) {
            revert InvalidSender(msg.sender);
        }

        // Limit refund value to previously captured
        uint256 captured = _captured[paymentHash];
        if (captured < value) revert RefundExceedsCapture(value, captured);

        _captured[paymentHash] = captured - value;
        emit PaymentRefunded(paymentHash, msg.sender, value);

        // Return tokens to buyer
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
        // validate value
        if (value > details.value) revert ValueLimitExceeded(value);

        // validate fees
        if (details.feeBps > 10_000) revert FeeBpsOverflow(details.feeBps);
        if (details.feeRecipient == address(0) && details.feeBps != 0) revert ZeroFeeRecipient();

        // check if authorization has been voided
        if (_voided[paymentHash]) revert VoidAuthorization(paymentHash);

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
