// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {IERC3009} from "./IERC3009.sol";
import {IMulticall3} from "./IMulticall3.sol";

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

    enum Status {
        EMPTY,
        PREAPPROVED,
        AUTHORIZED
    }

    /// @notice ERC-6492 magic value
    bytes32 public constant ERC6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;

    /// @notice Public Multicall3 contract, used to apply ERC-6492 preparation data
    IMulticall3 public immutable multicall3;

    /// @notice Authorization state for a specific payment.
    /// @dev Used to track whether an authorization has been voided or expired, and to limit amount that can
    ///      be captured or refunded from escrow.
    mapping(bytes32 paymentDetailsHash => uint256 value) internal _authorized;

    /// @notice Amount of tokens captured for a specific payment.
    /// @dev Used to limit amount that can be refunded post-capture.
    mapping(bytes32 paymentDetailsHash => uint256 value) internal _captured;

    /// @notice Amount of tokens approved by buyer for a specific payment details hash
    /// @dev Used to track and validate ERC-20 approvals for specific payments
    mapping(bytes32 paymentDetailsHash => Status status) internal _status;

    /// @notice Emitted when a buyer pre-approves for a specific payment
    event PaymentApproved(bytes32 indexed paymentDetailsHash);

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
    error PaymentAlreadyAuthorized(bytes32 paymentDetailsHash);
    error PaymentNotApproved(bytes32 paymentDetailsHash);
    error InsufficientAuthorization(bytes32 paymentDetailsHash, uint256 authorizedValue, uint256 requestedValue);
    error ValueLimitExceeded(uint256 value);
    error AfterAuthorizationDeadline(uint48 timestamp, uint48 deadline);
    error InvalidDeadlines(uint48 authorize, uint48 capture);
    error BeforeCaptureDeadline(uint48 timestamp, uint48 deadline);
    error AfterCaptureDeadline(uint48 timestamp, uint48 deadline);
    error RefundExceedsCapture(uint256 refund, uint256 captured);
    error FeeBpsOverflow(uint16 feeBps);
    error ZeroFeeRecipient();
    error ZeroValue();
    error ZeroAuthorization(bytes32 paymentDetailsHash);

    /// @notice Initialize contract with ERC6492 Executor
    /// @param _multicall3 Address of the Executor contract
    constructor(address _multicall3) {
        multicall3 = IMulticall3(_multicall3);
    }

    /// @notice Ensures value is not zero
    modifier validValue(uint256 value) {
        if (value == 0) revert ZeroValue();
        _;
    }

    receive() external payable {}

    /// @notice Registers buyer's token approval for a specific payment
    /// @dev Must be called by the buyer specified in the payment details
    /// @param paymentDetails PaymentDetails struct
    function preApprove(PaymentDetails calldata paymentDetails) external {
        // check sender is buyer
        if (msg.sender != paymentDetails.buyer) revert InvalidSender(msg.sender);

        // check status is not authorized
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        if (_status[paymentDetailsHash] == Status.AUTHORIZED) revert PaymentAlreadyAuthorized(paymentDetailsHash);

        _status[paymentDetailsHash] = Status.PREAPPROVED;
        emit PaymentApproved(paymentDetailsHash);
    }

    /// @notice Transfers funds from buyer to captureAddress in one step
    /// @dev If value is less than the authorized value, difference is returned to buyer
    /// @dev Reverts if the authorization has been voided or the capture deadline has passed
    /// @param value Amount to charge and capture
    /// @param paymentDetails PaymentDetails struct
    /// @param signature Signature of the buyer authorizing the payment
    function charge(uint256 value, PaymentDetails calldata paymentDetails, bytes calldata signature)
        external
        validValue(value)
    {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // check sender is operator
        if (msg.sender != paymentDetails.operator) revert InvalidSender(msg.sender);

        // transfer tokens into escrow
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
        validValue(value)
    {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // check sender is operator
        if (msg.sender != paymentDetails.operator) revert InvalidSender(msg.sender);

        // transfer tokens into escrow
        _pullTokens(paymentDetails, paymentDetailsHash, value, signature);

        // update authorized amount to only what we're keeping
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

        // check sender is operator or captureAddress
        if (msg.sender != paymentDetails.operator && msg.sender != paymentDetails.captureAddress) {
            revert InvalidSender(msg.sender);
        }

        // check before capture deadline
        if (block.timestamp >= paymentDetails.captureDeadline) {
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

        // check sender is operator or captureAddress
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

        // check sender is buyer
        if (msg.sender != paymentDetails.buyer) {
            revert InvalidSender(msg.sender);
        }

        // check not before capture deadline
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

        // validate refund
        _refund(value, paymentDetails.operator, paymentDetails.captureAddress, paymentDetailsHash);

        // Return tokens to buyer
        SafeTransferLib.safeTransferFrom(paymentDetails.token, msg.sender, paymentDetails.buyer, value);
    }

    /// @notice Return previously-captured tokens to buyer
    /// @dev Can be called by operator or captureAddress
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
        _refund(value, paymentDetails.operator, paymentDetails.captureAddress, paymentDetailsHash);

        // pull the refund amount from the sponsor
        _receiveWithAuthorization({
            token: paymentDetails.token,
            from: sponsor,
            value: value,
            validBefore: refundDeadline,
            nonce: keccak256(abi.encode(keccak256(abi.encode(paymentDetails)), refundSalt)),
            signature: signature
        });

        // Return tokens to buyer
        SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.buyer, value);
    }

    /// @notice Validate and update state for refund
    function _refund(uint256 value, address operator, address captureAddress, bytes32 paymentDetailsHash) internal {
        // Check sender is operator or captureAddress
        if (msg.sender != operator && msg.sender != captureAddress) {
            revert InvalidSender(msg.sender);
        }

        // Limit refund value to previously captured
        uint256 captured = _captured[paymentDetailsHash];
        if (captured < value) revert RefundExceedsCapture(value, captured);

        _captured[paymentDetailsHash] = captured - value;
        emit PaymentRefunded(paymentDetailsHash, value, msg.sender);
    }

    /// @notice Transfer tokens into this contract
    function _pullTokens(
        PaymentDetails memory paymentDetails,
        bytes32 paymentDetailsHash,
        uint256 value,
        bytes calldata signature
    ) internal {
        // check value does not exceed payment value
        if (value > paymentDetails.value) revert ValueLimitExceeded(value);

        // check before authorize deadline
        if (block.timestamp >= paymentDetails.authorizeDeadline) {
            revert AfterAuthorizationDeadline(uint48(block.timestamp), uint48(paymentDetails.authorizeDeadline));
        }

        // check before capture deadline
        if (paymentDetails.authorizeDeadline > paymentDetails.captureDeadline) {
            revert InvalidDeadlines(uint48(paymentDetails.authorizeDeadline), paymentDetails.captureDeadline);
        }

        // validate fees
        if (paymentDetails.feeBps > 10_000) revert FeeBpsOverflow(paymentDetails.feeBps);
        if (paymentDetails.feeRecipient == address(0) && paymentDetails.feeBps != 0) revert ZeroFeeRecipient();

        // use ERC-20 approvals if no signature, else use ERC-3009 authorization
        if (signature.length == 0) {
            // check status is pre-approved
            if (_status[paymentDetailsHash] != Status.PREAPPROVED) revert PaymentNotApproved(paymentDetailsHash);

            _status[paymentDetailsHash] = Status.AUTHORIZED;
            SafeTransferLib.safeTransferFrom(paymentDetails.token, paymentDetails.buyer, address(this), value);
        } else {
            _status[paymentDetailsHash] = Status.AUTHORIZED;

            _receiveWithAuthorization({
                token: paymentDetails.token,
                from: paymentDetails.buyer,
                value: paymentDetails.value,
                validBefore: uint48(paymentDetails.authorizeDeadline),
                nonce: paymentDetailsHash,
                signature: signature
            });

            // send excess funds back to buyer
            uint256 excessFunds = paymentDetails.value - value;
            if (excessFunds > 0) SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.buyer, excessFunds);
        }
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

            // construct public call to target with prepareData
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
