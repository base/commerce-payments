// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC3009} from "./IERC3009.sol";
import {IMulticall3} from "./IMulticall3.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";

/// @title PaymentEscrow
/// @notice Facilitate payments through an escrow.
/// @dev By escrowing payment, this contract can mimic the 2-step payment pattern of "authorization" and "capture".
/// @dev Authorization is defined as placing a hold on a buyer's funds temporarily.
/// @dev Capture is defined as distributing payment to the end recipient.
/// @dev An Operator plays the primary role of moving payments between both parties.
/// @author Coinbase
contract PaymentEscrow {
    /// @notice ERC-3009 authorization with additional payment routing data
    struct PaymentDetails {
        /// @dev operator Entity responsible for driving payment flow
        address operator;
        /// @dev buyer The buyer's address authorizing the payment
        address buyer;
        /// @dev captureAddress Address that receives the captured payment (minus fees)
        address captureAddress;
        /// @dev token The ERC-3009 token contract address
        address token;
        /// @dev value The amount of tokens that will be transferred from the buyer to the escrow
        uint256 value;
        /// @dev authorizeDeadline Timestamp when the authorization expires
        uint256 authorizeDeadline;
        /// @dev captureDeadline Timestamp when the payment can no longer be captured and the buyer can reclaim authorization from escrow
        uint48 captureDeadline;
        /// @dev feeBps Fee percentage in basis points (1/100th of a percent)
        uint16 feeBps;
        /// @dev feeRecipient Address that receives the fee portion of payments
        address feeRecipient;
        /// @dev salt A source of entropy to ensure unique hashes across different payment details
        uint256 salt;
    }

    /// @notice State for tracking payments through lifecycle
    struct PaymentState {
        /// @dev isPreApproved True if payment was pre-aproved by the buyer
        bool isPreApproved;
        /// @dev isAuthorized True if payment has been authorized or charged
        bool isAuthorized;
        /// @dev authorized Value of tokens currently on hold in escrow
        uint120 authorized;
        /// @dev captured Value of tokens previously captured and not refunded
        uint120 captured;
    }

    /// @notice ERC-6492 magic value
    bytes32 public constant ERC6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;

    /// @notice Public Multicall3 contract, used to apply ERC-6492 preparation data
    IMulticall3 public immutable multicall3;

    /// @notice State per unique payment
    mapping(bytes32 paymentDetailsHash => PaymentState state) _paymentState;

    /// @notice Emitted when a buyer pre-approves a payment
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

    /// @notice Emitted when a captured payment is refunded
    event PaymentRefunded(bytes32 indexed paymentDetailsHash, uint256 value, address sender);

    /// @notice Sender for a function call does not follow access control requirements
    error InvalidSender(address sender);

    /// @notice Payment has already been authorized
    error PaymentAlreadyAuthorized(bytes32 paymentDetailsHash);

    /// @notice Payment has not been approved
    error PaymentNotApproved(bytes32 paymentDetailsHash);

    /// @notice Payment authorization is insufficient for a requested capture
    error InsufficientAuthorization(bytes32 paymentDetailsHash, uint256 authorizedValue, uint256 requestedValue);

    /// @notice Requested authorization value exceeds limit on payment details
    error ValueLimitExceeded(uint256 value);

    /// @notice Authorization attempted after deadline
    error AfterAuthorizationDeadline(uint48 timestamp, uint48 deadline);

    /// @notice Authorization deadline after capture deadline
    error InvalidDeadlines(uint48 authorize, uint48 capture);

    /// @notice Capture attempted after deadline
    error AfterCaptureDeadline(uint48 timestamp, uint48 deadline);

    /// @notice Reclaim attempted before capture deadline
    error BeforeCaptureDeadline(uint48 timestamp, uint48 deadline);

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

    /// @notice Permit2 contract address - this should be the canonical deployment
    IPermit2 public immutable permit2;

    /// @notice Permit2 transfer failed
    error Permit2TransferFailed();

    /// @notice Initialize contract with ERC6492 Executor and Permit2
    /// @param _multicall3 Address of the Executor contract
    /// @param _permit2 Address of the Permit2 contract
    constructor(address _multicall3, address _permit2) {
        multicall3 = IMulticall3(_multicall3);
        permit2 = IPermit2(_permit2);
    }

    /// @notice Ensures value is non-zero and does not overflow storage
    modifier validValue(uint256 value) {
        if (value == 0) revert ZeroValue();
        if (value > type(uint120).max) revert ValueOverflow(value, type(uint120).max);
        _;
    }

    /// @notice Registers buyer's token approval for a specific payment
    /// @dev Must be called by the buyer specified in the payment details
    /// @param paymentDetails PaymentDetails struct
    function preApprove(PaymentDetails calldata paymentDetails) external {
        // check sender is buyer
        if (msg.sender != paymentDetails.buyer) revert InvalidSender(msg.sender);

        // check status is not authorized
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        if (_paymentState[paymentDetailsHash].isAuthorized) revert PaymentAlreadyAuthorized(paymentDetailsHash);

        _paymentState[paymentDetailsHash].isPreApproved = true;
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

        // update captured amount for refund accounting
        _paymentState[paymentDetailsHash].captured = uint120(value);
        emit PaymentCharged(
            paymentDetailsHash,
            paymentDetails.operator,
            paymentDetails.buyer,
            paymentDetails.captureAddress,
            paymentDetails.token,
            value
        );

        // distribute tokens including fees
        _distributeTokens(
            paymentDetails.token,
            paymentDetails.captureAddress,
            paymentDetails.feeRecipient,
            paymentDetails.feeBps,
            value
        );
    }

    /// @notice Transfers funds from buyer to escrow
    /// @dev Validates either buyer signature for ERC-3009 or, if empty signature, pre-approval via ERC-20 approva
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

        // update authorized amount for capture accounting
        _paymentState[paymentDetailsHash].authorized = uint120(value);
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
        PaymentState memory state = _paymentState[paymentDetailsHash];
        if (state.authorized < value) revert InsufficientAuthorization(paymentDetailsHash, state.authorized, value);

        // update state
        state.authorized -= uint120(value);
        state.captured += uint120(value);
        _paymentState[paymentDetailsHash] = state;
        emit PaymentCaptured(paymentDetailsHash, value, msg.sender);

        // distribute tokens including fees
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
    /// @dev Can only be called by the operator or captureAddress
    /// @param paymentDetails PaymentDetails struct
    function void(PaymentDetails calldata paymentDetails) external {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // check sender is operator or captureAddress
        if (msg.sender != paymentDetails.operator && msg.sender != paymentDetails.captureAddress) {
            revert InvalidSender(msg.sender);
        }

        // check authorization non-zero
        uint256 authorizedValue = _paymentState[paymentDetailsHash].authorized;
        if (authorizedValue == 0) revert ZeroAuthorization(paymentDetailsHash);

        // return any escrowed funds
        _paymentState[paymentDetailsHash].authorized = 0;
        emit PaymentVoided(paymentDetailsHash, authorizedValue, msg.sender);
        SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.buyer, authorizedValue);
    }

    /// @notice Returns any escrowed funds to buyer
    /// @dev Can only be called by the buyer and only after the capture deadline
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
        uint256 authorizedValue = _paymentState[paymentDetailsHash].authorized;
        if (authorizedValue == 0) revert ZeroAuthorization(paymentDetailsHash);

        // return any escrowed funds
        _paymentState[paymentDetailsHash].authorized = 0;
        emit PaymentReclaimed(paymentDetailsHash, authorizedValue);
        SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.buyer, authorizedValue);
    }

    /// @notice Return previously-captured tokens to buyer
    /// @dev Can be called by operator or captureAddress
    /// @dev Funds are transferred from the caller
    /// @param value Amount to refund
    /// @param paymentDetails PaymentDetails struct
    function refund(uint256 value, PaymentDetails calldata paymentDetails) external validValue(value) {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // validate refund
        _refund(value, paymentDetails.operator, paymentDetails.captureAddress, paymentDetailsHash);

        // return tokens to buyer
        SafeTransferLib.safeTransferFrom(paymentDetails.token, msg.sender, paymentDetails.buyer, value);
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

        // return tokens to buyer
        SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.buyer, value);
    }

    /// @notice Transfer tokens into this contract
    function _pullTokens(
        PaymentDetails calldata paymentDetails,
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

        // check authorize deadline not after capture deadline
        if (paymentDetails.authorizeDeadline > paymentDetails.captureDeadline) {
            revert InvalidDeadlines(uint48(paymentDetails.authorizeDeadline), paymentDetails.captureDeadline);
        }

        // validate fees
        if (paymentDetails.feeBps > 10_000) revert FeeBpsOverflow(paymentDetails.feeBps);
        if (paymentDetails.feeRecipient == address(0) && paymentDetails.feeBps != 0) revert ZeroFeeRecipient();

        // check payment not previously authorized
        if (_paymentState[paymentDetailsHash].isAuthorized) revert PaymentAlreadyAuthorized(paymentDetailsHash);
        _paymentState[paymentDetailsHash].isAuthorized = true;

        // use ERC-20 approval if no signature, else use ERC-3009 authorization
        if (signature.length == 0) {
            // check status is pre-approved
            if (!_paymentState[paymentDetailsHash].isPreApproved) revert PaymentNotApproved(paymentDetailsHash);

            SafeTransferLib.safeTransferFrom(paymentDetails.token, paymentDetails.buyer, address(this), value);
        } else {
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
            // Try ERC3009 first
            try IERC3009(paymentDetails.token).receiveWithAuthorization({
                from: paymentDetails.buyer,
                to: address(this),
                value: paymentDetails.value,
                validAfter: 0,
                validBefore: uint48(paymentDetails.authorizeDeadline),
                nonce: paymentDetailsHash,
                signature: innerSignature
            }) {
                // ERC3009 succeeded
            } catch {
                // ERC3009 failed, try Permit2
                try permit2.permitTransferFrom(
                    ISignatureTransfer.PermitTransferFrom({
                        permitted: ISignatureTransfer.TokenPermissions({token: paymentDetails.token, amount: value}),
                        nonce: uint256(paymentDetailsHash),
                        deadline: paymentDetails.authorizeDeadline
                    }),
                    ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: value}),
                    paymentDetails.buyer,
                    signature
                ) {
                    return; // Permit2 succeeded
                    // can return here because we don't need to return excess funds to the buyer, we transferred the exact amount
                } catch {
                    // Both methods failed
                    revert Permit2TransferFailed();
                }
            }

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

    /// @notice Validate and update state for refund
    function _refund(uint256 value, address operator, address captureAddress, bytes32 paymentDetailsHash) internal {
        // Check sender is operator or captureAddress
        if (msg.sender != operator && msg.sender != captureAddress) {
            revert InvalidSender(msg.sender);
        }

        // Limit refund value to previously captured
        uint120 captured = _paymentState[paymentDetailsHash].captured;
        if (captured < value) revert RefundExceedsCapture(value, captured);

        _paymentState[paymentDetailsHash].captured = captured - uint120(value);
        emit PaymentRefunded(paymentDetailsHash, value, msg.sender);
    }
}
