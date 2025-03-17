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
    /// @notice ERC-3009 authorization with additional payment routing data
    /// @param operator Entity responsible for driving payment flow
    /// @param buyer The buyer's address authorizing the payment
    /// @param captureAddress Address that receives the captured payment (minus fees)
    /// @param token The ERC-3009 token contract address
    /// @param value The amount of tokens that will be transferred from the buyer to the escrow
    /// @param authorizeDeadline Timestamp when the authorization expires
    /// @param captureDeadline Timestamp when the buyer can withdraw authorization from escrow
    /// @param feeBps Fee percentage in basis points (1/100th of a percent)
    /// @param feeRecipient Address that receives the fee portion of payments
    /// @param salt A source of entropy to ensure unique hashes across different payment details
    struct PaymentDetails {
        address operator;
        address buyer;
        address captureAddress;
        address token;
        uint256 value;
        uint256 authorizeDeadline;
        uint48 captureDeadline;
        uint16 feeBps;
        address feeRecipient;
        uint256 salt;
    }

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

    /// @notice Emitted when captured payment is refunded
    event PaymentRefunded(bytes32 indexed paymentDetailsHash, uint256 value, address sender);

    error InvalidSender(address sender);
    error InsufficientAuthorization(bytes32 paymentDetailsHash, uint256 authorizedValue, uint256 requestedValue);
    error ValueLimitExceeded(uint256 value);
    error AfterAuthorizationDeadline(uint48 timestamp, uint48 deadline);
    error BeforeCaptureDeadline(uint48 timestamp, uint48 deadline);
    error AfterCaptureDeadline(uint48 timestamp, uint48 deadline);
    error RefundExceedsCapture(uint256 refund, uint256 captured);
    error FeeBpsOverflow(uint16 feeBps);
    error ZeroFeeRecipient();
    error ZeroValue();
    error AuthorizationVoided(bytes32 paymentDetailsHash);
    error ZeroAuthorization(bytes32 paymentDetailsHash);

    /// @notice Initialize contract with ERC6492 validator
    /// @param _erc6492Validator Address of the validator contract
    constructor(address _erc6492Validator) {
        erc6492Validator = PublicERC6492Validator(_erc6492Validator);
    }

    /// @notice Ensures caller is the operator specified in payment details
    modifier onlyOperator(PaymentDetails calldata paymentDetails) {
        if (msg.sender != paymentDetails.operator) revert InvalidSender(msg.sender);
        _;
    }

    /// @notice Ensures value is not zero
    modifier validValue(uint256 value) {
        if (value == 0) revert ZeroValue();
        _;
    }

    receive() external payable {}

    /// @notice Transfers funds from buyer to captureAddress in one step
    /// @dev If value is less than the authorized value, difference is returned to buyer
    /// @dev Reverts if the authorization has been voided or the capture deadline has passed
    /// @param value Amount to charge and capture
    /// @param paymentDetails PaymentDetails struct
    /// @param signature Signature of the buyer authorizing the payment
    function charge(uint256 value, PaymentDetails calldata paymentDetails, bytes calldata signature)
        external
        onlyOperator(paymentDetails)
        validValue(value)
    {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        _pullTokens(paymentDetails, paymentDetailsHash, value, signature);

        // Update captured amount for refund tracking
        _captured[paymentDetailsHash] = value;
        emit PaymentCharged(
            paymentDetailsHash,
            paymentDetails.operator,
            paymentDetails.buyer,
            paymentDetails.captureAddress,
            paymentDetails.token,
            value
        );

        // Handle fees only for the actual charged amount
        _distributeTokens(
            paymentDetails.token,
            paymentDetails.captureAddress,
            paymentDetails.feeRecipient,
            paymentDetails.feeBps,
            value
        );
    }

    /// @notice Validates buyer signature and transfers funds from buyer to escrow
    /// @param value Amount to authorize
    /// @param paymentDetails PaymentDetails struct
    /// @param signature Signature of the buyer authorizing the payment
    function authorize(uint256 value, PaymentDetails calldata paymentDetails, bytes calldata signature)
        external
        onlyOperator(paymentDetails)
        validValue(value)
    {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        _pullTokens(paymentDetails, paymentDetailsHash, value, signature);

        // Update authorized amount to only what we're keeping
        _authorized[paymentDetailsHash] = value;
        emit PaymentAuthorized(
            paymentDetailsHash,
            paymentDetails.operator,
            paymentDetails.buyer,
            paymentDetails.captureAddress,
            paymentDetails.token,
            value
        );
    }

    /// @notice Transfer previously-escrowed funds to captureAddress
    /// @dev Can be called multiple times up to cumulative authorized amount
    /// @param value Amount to capture
    /// @param paymentDetails PaymentDetails struct
    function capture(uint256 value, PaymentDetails calldata paymentDetails) external validValue(value) {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        if (msg.sender != paymentDetails.operator && msg.sender != paymentDetails.captureAddress) {
            revert InvalidSender(msg.sender);
        }

        // check capture deadline
        if (block.timestamp > paymentDetails.captureDeadline) {
            revert AfterCaptureDeadline(uint48(block.timestamp), paymentDetails.captureDeadline);
        }

        // check sufficient escrow to capture
        uint256 authorizedValue = _authorized[paymentDetailsHash];
        if (authorizedValue < value) revert InsufficientAuthorization(paymentDetailsHash, authorizedValue, value);

        // update state
        _authorized[paymentDetailsHash] = authorizedValue - value;
        _captured[paymentDetailsHash] += value;
        emit PaymentCaptured(paymentDetailsHash, value, msg.sender);

        // handle fees only for the actual charged amount
        _distributeTokens(
            paymentDetails.token,
            paymentDetails.captureAddress,
            paymentDetails.feeRecipient,
            paymentDetails.feeBps,
            value
        );
    }

    /// @notice Permanently voids a payment authorization
    /// @dev Returns any escrowed funds to buyer
    /// @param paymentDetails PaymentDetails struct
    function void(PaymentDetails calldata paymentDetails) external {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        if (msg.sender != paymentDetails.operator && msg.sender != paymentDetails.captureAddress) {
            revert InvalidSender(msg.sender);
        }

        // check authorization non-zero
        uint256 authorizedValue = _authorized[paymentDetailsHash];
        if (authorizedValue == 0) revert ZeroAuthorization(paymentDetailsHash);

        // Return any escrowed funds
        delete _authorized[paymentDetailsHash];
        emit PaymentVoided(paymentDetailsHash, authorizedValue, msg.sender);
        SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.buyer, authorizedValue);
    }

    /// @notice Permanently voids a payment authorization
    /// @dev Returns any escrowed funds to buyer
    /// @param paymentDetails PaymentDetails struct
    function reclaim(PaymentDetails calldata paymentDetails) external {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        if (msg.sender != paymentDetails.buyer) {
            revert InvalidSender(msg.sender);
        }

        if (block.timestamp < paymentDetails.captureDeadline) {
            revert BeforeCaptureDeadline(uint48(block.timestamp), paymentDetails.captureDeadline);
        }

        // check authorization non-zero
        uint256 authorizedValue = _authorized[paymentDetailsHash];
        if (authorizedValue == 0) revert ZeroAuthorization(paymentDetailsHash);

        // Return any escrowed funds
        delete _authorized[paymentDetailsHash];
        emit PaymentReclaimed(paymentDetailsHash, authorizedValue);
        SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.buyer, authorizedValue);
    }

    /// @notice Return previously-captured tokens to buyer
    /// @dev Can be called by operator or captureAddress
    /// @param value Amount to refund
    /// @param paymentDetails PaymentDetails struct
    function refund(uint256 value, PaymentDetails calldata paymentDetails) external validValue(value) {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // Check sender is operator or captureAddress
        if (msg.sender != paymentDetails.operator && msg.sender != paymentDetails.captureAddress) {
            revert InvalidSender(msg.sender);
        }

        // Limit refund value to previously captured
        uint256 captured = _captured[paymentDetailsHash];
        if (captured < value) revert RefundExceedsCapture(value, captured);

        _captured[paymentDetailsHash] = captured - value;
        emit PaymentRefunded(paymentDetailsHash, value, msg.sender);

        // Return tokens to buyer
        SafeTransferLib.safeTransferFrom(paymentDetails.token, msg.sender, paymentDetails.buyer, value);
    }

    function _pullTokens(
        PaymentDetails memory paymentDetails,
        bytes32 paymentDetailsHash,
        uint256 value,
        bytes calldata signature
    ) internal {
        // validate value
        if (value > paymentDetails.value) revert ValueLimitExceeded(value);

        // validate deadlines
        if (block.timestamp >= paymentDetails.authorizeDeadline) {
            revert AfterAuthorizationDeadline(uint48(block.timestamp), uint48(paymentDetails.authorizeDeadline));
        }
        if (paymentDetails.authorizeDeadline > paymentDetails.captureDeadline) {
            revert AfterCaptureDeadline(uint48(paymentDetails.authorizeDeadline), paymentDetails.captureDeadline);
        }

        // validate fees
        if (paymentDetails.feeBps > 10_000) revert FeeBpsOverflow(paymentDetails.feeBps);
        if (paymentDetails.feeRecipient == address(0) && paymentDetails.feeBps != 0) revert ZeroFeeRecipient();

        // parse signature to use for 3009 receiveWithAuthorization
        bytes memory innerSignature = signature;
        if (signature.length >= 32 && bytes32(signature[signature.length - 32:]) == ERC6492_MAGIC_VALUE) {
            // apply 6492 signature prepareData
            erc6492Validator.isValidSignatureNowAllowSideEffects(paymentDetails.buyer, paymentDetailsHash, signature);
            // parse inner signature from 6492 format
            (,, innerSignature) = abi.decode(signature[0:signature.length - 32], (address, bytes, bytes));
        }

        // pull the full authorized amount from the buyer
        IERC3009(paymentDetails.token).receiveWithAuthorization({
            from: paymentDetails.buyer,
            to: address(this),
            value: paymentDetails.value,
            validAfter: 0,
            validBefore: paymentDetails.authorizeDeadline,
            nonce: paymentDetailsHash,
            signature: innerSignature
        });

        // send excess funds back to buyer
        uint256 excessFunds = paymentDetails.value - value;
        if (excessFunds > 0) SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.buyer, excessFunds);
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
}
