// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Create2} from "openzeppelin-contracts/contracts/utils/Create2.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";

import {TokenCollector} from "./collectors/TokenCollector.sol";
import {OperatorTreasury} from "./OperatorTreasury.sol";

/// @title PaymentEscrow
/// @notice Facilitate payments through an escrow.
/// @dev By escrowing payment, this contract can mimic the 2-step payment pattern of "authorization" and "capture".
/// @dev Authorization is defined as placing a hold on a payer's funds temporarily.
/// @dev Capture is defined as distributing payment to the end recipient.
/// @dev An Operator plays the primary role of moving payments between both parties.
/// @author Coinbase
contract PaymentEscrow is ReentrancyGuardTransient {
    /// @notice Payment info, contains all information required to authorize and capture a unique payment
    struct PaymentInfo {
        /// @dev Entity responsible for driving payment flow
        address operator;
        /// @dev The payer's address authorizing the payment
        address payer;
        /// @dev Address that receives the payment (minus fees)
        address receiver;
        /// @dev The token contract address
        address token;
        /// @dev The amount of tokens that can be authorized
        uint120 maxAmount;
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
        /// @dev A source of entropy to ensure unique hashes across different payments
        uint256 salt;
    }

    /// @notice State for tracking payments through lifecycle
    struct PaymentState {
        /// @dev True if payment has been authorized or charged
        bool hasCollectedPayment;
        /// @dev Amount of tokens currently on hold in escrow that can be captured
        uint120 capturableAmount;
        /// @dev Amount of tokens previously captured that can be refunded
        uint120 refundableAmount;
    }

    /// @notice Typehash used for hashing PaymentInfo structs
    bytes32 public constant PAYMENT_INFO_TYPEHASH = keccak256(
        "PaymentInfo(address operator,address payer,address receiver,address token,uint256 maxAmount,uint48 preApprovalExpiry,uint48 authorizationExpiry,uint48 refundExpiry,uint16 minFeeBps,uint16 maxFeeBps,address feeReceiver,uint256 salt)"
    );

    /// @notice State per unique payment
    mapping(bytes32 paymentInfoHash => PaymentState state) public paymentState;

    /// @notice Emitted when a payment is charged and immediately captured
    event PaymentCharged(
        bytes32 indexed paymentInfoHash,
        address operator,
        address payer,
        address receiver,
        address token,
        uint256 amount,
        address tokenCollector
    );

    /// @notice Emitted when authorized (escrowed) amount is increased
    event PaymentAuthorized(
        bytes32 indexed paymentInfoHash,
        address operator,
        address payer,
        address receiver,
        address token,
        uint256 amount,
        address tokenCollector
    );

    /// @notice Emitted when payment is captured from escrow
    event PaymentCaptured(bytes32 indexed paymentInfoHash, uint256 amount);

    /// @notice Emitted when an authorized payment is voided, returning any escrowed funds to the payer
    event PaymentVoided(bytes32 indexed paymentInfoHash, uint256 amount);

    /// @notice Emitted when an authorized payment is reclaimed, returning any escrowed funds to the payer
    event PaymentReclaimed(bytes32 indexed paymentInfoHash, uint256 amount);

    /// @notice Emitted when a captured payment is refunded
    event PaymentRefunded(bytes32 indexed paymentInfoHash, uint256 amount, address tokenCollector);

    /// @notice Event emitted when new treasury is created
    event TreasuryCreated(address indexed operator, address treasury);

    /// @notice Sender for a function call does not follow access control requirements
    error InvalidSender(address sender, address expected);

    /// @notice Amount is zero
    error ZeroAmount();

    /// @notice Amount overflows allowed storage size of uint120
    error AmountOverflow(uint256 amount, uint256 limit);

    /// @notice Requested authorization amount exceeds `PaymentInfo.maxAmount`
    error ExceedsMaxAmount(uint256 amount, uint256 maxAmount);

    /// @notice Authorization attempted after pre-approval expiry
    error AfterPreApprovalExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Expiry timestamps violate preApproval <= authorization <= refund
    error InvalidExpiries(uint48 preApproval, uint48 authorization, uint48 refund);

    /// @notice Fee bips overflows 10_000 maximum
    error FeeBpsOverflow(uint16 feeBps);

    /// @notice Fee bps range invalid due to min > max
    error InvalidFeeBpsRange(uint16 minFeeBps, uint16 maxFeeBps);

    /// @notice Fee bps outside of allowed range
    error FeeBpsOutOfRange(uint16 feeBps, uint16 minFeeBps, uint16 maxFeeBps);

    /// @notice Fee receiver is zero address with a non-zero fee
    error ZeroFeeReceiver();

    /// @notice Fee recipient cannot be changed
    error InvalidFeeReceiver(address attempted, address expected);

    /// @notice Token collector is not valid for the operation
    error InvalidCollectorForOperation();

    /// @notice Token pull failed
    error TokenCollectionFailed();

    /// @notice Charge or authorize attempted on a payment has already been collected
    error PaymentAlreadyCollected(bytes32 paymentInfoHash);

    /// @notice Capture attempted at or after authorization expiry
    error AfterAuthorizationExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Capture attempted with insufficient authorization amount
    error InsufficientAuthorization(bytes32 paymentInfoHash, uint256 authorizedAmount, uint256 requestedAmount);

    /// @notice Void or reclaim attempted with zero authorization amount
    error ZeroAuthorization(bytes32 paymentInfoHash);

    /// @notice Reclaim attempted before authorization expiry
    error BeforeAuthorizationExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Refund attempted at or after refund expiry
    error AfterRefundExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Refund attempted with amount exceeding previous non-refunded captures
    error RefundExceedsCapture(uint256 refund, uint256 captured);

    /// @notice Treasury not found for an operator
    error TreasuryNotFound(address operator);

    /// @notice Check call sender is specified address
    modifier onlySender(address sender) {
        if (msg.sender != sender) revert InvalidSender(msg.sender, sender);
        _;
    }

    /// @notice Ensures amount is non-zero and does not overflow storage
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        if (amount > type(uint120).max) revert AmountOverflow(amount, type(uint120).max);
        _;
    }

    /// @notice Transfers funds from payer to receiver in one step
    /// @dev If amount is less than the authorized amount, only amount is taken from payer
    /// @dev Reverts if the authorization has been voided or expired
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount to charge and capture
    /// @param tokenCollector Address of the token collector
    /// @param collectorData Data to pass to the token collector
    /// @param feeBps Fee percentage to apply (must be within min/max range)
    /// @param feeReceiver Address to receive fees (can only be set if original feeReceiver was 0)
    function charge(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData,
        uint16 feeBps,
        address feeReceiver
    ) external nonReentrant onlySender(paymentInfo.operator) validAmount(amount) {
        // Check payment info valid
        _validatePayment(paymentInfo, amount);

        // Check fee parameters valid
        _validateFee(paymentInfo, feeBps, feeReceiver);

        // Check payment not already collected
        bytes32 paymentInfoHash = getHash(paymentInfo);
        if (paymentState[paymentInfoHash].hasCollectedPayment) revert PaymentAlreadyCollected(paymentInfoHash);

        // Set payment state with refundable amount
        paymentState[paymentInfoHash] =
            PaymentState({hasCollectedPayment: true, capturableAmount: 0, refundableAmount: uint120(amount)});
        emit PaymentCharged(
            paymentInfoHash,
            paymentInfo.operator,
            paymentInfo.payer,
            paymentInfo.receiver,
            paymentInfo.token,
            amount,
            tokenCollector
        );

        // Transfer tokens into escrow
        _collectTokens(
            paymentInfoHash, paymentInfo, amount, tokenCollector, collectorData, TokenCollector.CollectorType.Payment
        );

        // Transfer tokens to receiver and fee receiver
        _distributeTokens(paymentInfo.token, paymentInfo.receiver, amount, feeBps, feeReceiver);
    }

    /// @notice Transfers funds from payer to escrow
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount to authorize
    /// @param tokenCollector Address of the token collector
    /// @param collectorData Data to pass to the token collector
    function authorize(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external nonReentrant onlySender(paymentInfo.operator) validAmount(amount) {
        // Check payment info valid
        _validatePayment(paymentInfo, amount);

        // Check payment not already collected
        bytes32 paymentInfoHash = getHash(paymentInfo);
        if (paymentState[paymentInfoHash].hasCollectedPayment) revert PaymentAlreadyCollected(paymentInfoHash);

        // Set payment state with capturable amount
        paymentState[paymentInfoHash] =
            PaymentState({hasCollectedPayment: true, capturableAmount: uint120(amount), refundableAmount: 0});
        emit PaymentAuthorized(
            paymentInfoHash,
            paymentInfo.operator,
            paymentInfo.payer,
            paymentInfo.receiver,
            paymentInfo.token,
            amount,
            tokenCollector
        );

        // Transfer tokens into escrow
        _collectTokens(
            paymentInfoHash, paymentInfo, amount, tokenCollector, collectorData, TokenCollector.CollectorType.Payment
        );
    }

    /// @notice Transfer previously-escrowed funds to receiver
    /// @dev Can be called multiple times up to cumulative authorized amount
    /// @dev Can only be called by the operator
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount to capture
    /// @param feeBps Fee percentage to apply (must be within min/max range)
    /// @param feeReceiver Address to receive fees (can only be set if original feeReceiver was 0)
    function capture(PaymentInfo calldata paymentInfo, uint256 amount, uint16 feeBps, address feeReceiver)
        external
        nonReentrant
        onlySender(paymentInfo.operator)
        validAmount(amount)
    {
        // Check fee parameters valid
        _validateFee(paymentInfo, feeBps, feeReceiver);

        // Check before authorization expiry
        if (block.timestamp >= paymentInfo.authorizationExpiry) {
            revert AfterAuthorizationExpiry(uint48(block.timestamp), paymentInfo.authorizationExpiry);
        }

        // Check sufficient escrow to capture
        bytes32 paymentInfoHash = getHash(paymentInfo);
        PaymentState memory state = paymentState[paymentInfoHash];
        if (state.capturableAmount < amount) {
            revert InsufficientAuthorization(paymentInfoHash, state.capturableAmount, amount);
        }

        // Update payment state, converting capturable amount to refundable amount
        state.capturableAmount -= uint120(amount);
        state.refundableAmount += uint120(amount);
        paymentState[paymentInfoHash] = state;
        emit PaymentCaptured(paymentInfoHash, amount);

        // Transfer tokens to receiver and fee receiver
        _distributeTokens(paymentInfo.token, paymentInfo.receiver, amount, feeBps, feeReceiver);
    }

    /// @notice Permanently voids a payment authorization
    /// @dev Returns any escrowed funds to payer
    /// @dev Can only be called by the operator
    /// @param paymentInfo PaymentInfo struct
    function void(PaymentInfo calldata paymentInfo) external nonReentrant onlySender(paymentInfo.operator) {
        // Check authorization non-zero
        bytes32 paymentInfoHash = getHash(paymentInfo);
        uint256 authorizedAmount = paymentState[paymentInfoHash].capturableAmount;
        if (authorizedAmount == 0) revert ZeroAuthorization(paymentInfoHash);

        // Clear capturable amount state
        paymentState[paymentInfoHash].capturableAmount = 0;
        emit PaymentVoided(paymentInfoHash, authorizedAmount);

        // Transfer tokens to payer from treasury
        _sendTokens(paymentInfo.operator, paymentInfo.token, authorizedAmount, paymentInfo.payer);
    }

    /// @notice Returns any escrowed funds to payer
    /// @dev Can only be called by the payer and only after the authorization expiry
    /// @param paymentInfo PaymentInfo struct
    function reclaim(PaymentInfo calldata paymentInfo) external nonReentrant onlySender(paymentInfo.payer) {
        // Check not before authorization expiry
        if (block.timestamp < paymentInfo.authorizationExpiry) {
            revert BeforeAuthorizationExpiry(uint48(block.timestamp), paymentInfo.authorizationExpiry);
        }

        // Check authorization non-zero
        bytes32 paymentInfoHash = getHash(paymentInfo);
        uint256 authorizedAmount = paymentState[paymentInfoHash].capturableAmount;
        if (authorizedAmount == 0) revert ZeroAuthorization(paymentInfoHash);

        // Clear capturable amount state
        paymentState[paymentInfoHash].capturableAmount = 0;
        emit PaymentReclaimed(paymentInfoHash, authorizedAmount);

        // Transfer tokens to payer from treasury
        _sendTokens(paymentInfo.operator, paymentInfo.token, authorizedAmount, paymentInfo.payer);
    }

    /// @notice Return previously-captured tokens to payer
    /// @dev Can be called by operator
    /// @dev Funds are transferred from the caller or from the escrow if token collector retrieves external liquidity
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount to refund
    /// @param tokenCollector Address of the token collector
    /// @param collectorData Data to pass to the token collector
    function refund(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external nonReentrant onlySender(paymentInfo.operator) validAmount(amount) {
        // Check refund has not expired
        if (block.timestamp >= paymentInfo.refundExpiry) {
            revert AfterRefundExpiry(uint48(block.timestamp), paymentInfo.refundExpiry);
        }

        // Limit refund amount to previously captured
        bytes32 paymentInfoHash = getHash(paymentInfo);
        uint120 captured = paymentState[paymentInfoHash].refundableAmount;
        if (captured < amount) revert RefundExceedsCapture(amount, captured);

        // Update refundable amount
        paymentState[paymentInfoHash].refundableAmount = captured - uint120(amount);
        emit PaymentRefunded(paymentInfoHash, amount, tokenCollector);

        // Transfer tokens into escrow and forward to payer
        _collectTokens(
            paymentInfoHash, paymentInfo, amount, tokenCollector, collectorData, TokenCollector.CollectorType.Refund
        );
        _sendTokens(paymentInfo.operator, paymentInfo.token, amount, paymentInfo.payer);
    }

    /// @notice Get hash of PaymentInfo struct
    /// @dev Includes chainId and verifyingContract in hash for cross-chain and cross-contract uniqueness
    /// @param paymentInfo PaymentInfo struct
    /// @return Hash of payment info for the current chain and contract address
    function getHash(PaymentInfo calldata paymentInfo) public view returns (bytes32) {
        bytes32 paymentInfoHash = keccak256(abi.encode(PAYMENT_INFO_TYPEHASH, paymentInfo));
        return keccak256(abi.encode(block.chainid, address(this), paymentInfoHash));
    }

    /// @notice Transfer tokens into this contract
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount of tokens to collect
    /// @param tokenCollector Address of the token collector
    /// @param collectorData Data to pass to the token collector
    /// @param collectorType Type of collector to enforce (payment or refund)
    function _collectTokens(
        bytes32 paymentInfoHash,
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData,
        TokenCollector.CollectorType collectorType
    ) internal {
        // Check token collector matches required type
        if (TokenCollector(tokenCollector).collectorType() != collectorType) revert InvalidCollectorForOperation();

        address treasury = _getOrCreateTreasury(paymentInfo.operator);

        // Measure balance change for collecting tokens to enforce as equal to expected amount
        uint256 escrowBalanceBefore = IERC20(paymentInfo.token).balanceOf(address(this));

        TokenCollector(tokenCollector).collectTokens(paymentInfoHash, paymentInfo, amount, collectorData);
        uint256 escrowBalanceAfter = IERC20(paymentInfo.token).balanceOf(address(this));
        if (escrowBalanceAfter != escrowBalanceBefore + amount) revert TokenCollectionFailed();

        // Forward tokens to operator's treasury
        SafeTransferLib.safeTransfer(paymentInfo.token, treasury, amount);
    }

    /// @notice Sends tokens to receiver and/or feeReceiver
    /// @param token Token to transfer
    /// @param receiver Address to receive payment
    /// @param amount Total amount to split between payment and fees
    /// @param feeBps Fee percentage in basis points
    /// @param feeReceiver Address to receive fees
    function _distributeTokens(address token, address receiver, uint256 amount, uint16 feeBps, address feeReceiver)
        internal
    {
        address treasury = operatorTreasury(msg.sender);
        if (treasury == address(0)) revert TreasuryNotFound(msg.sender);

        uint256 feeAmount = uint256(amount) * feeBps / 10_000;

        // Send fee portion if non-zero
        if (feeAmount > 0) {
            OperatorTreasury(treasury).sendTokens(token, feeAmount, feeReceiver);
        }

        // Send remaining amount to receiver
        if (amount - feeAmount > 0) {
            OperatorTreasury(treasury).sendTokens(token, amount - feeAmount, receiver);
        }
    }

    /// @notice Validates required properties of a payment
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Token amount to validate against
    function _validatePayment(PaymentInfo calldata paymentInfo, uint256 amount) internal view {
        // Check amount does not exceed maximum
        if (amount > paymentInfo.maxAmount) revert ExceedsMaxAmount(amount, paymentInfo.maxAmount);

        // Check timestamp before pre-approval expiry
        if (block.timestamp >= paymentInfo.preApprovalExpiry) {
            revert AfterPreApprovalExpiry(uint48(block.timestamp), uint48(paymentInfo.preApprovalExpiry));
        }

        // Check expiry timestamps properly ordered
        if (
            paymentInfo.preApprovalExpiry > paymentInfo.authorizationExpiry
                || paymentInfo.authorizationExpiry > paymentInfo.refundExpiry
        ) {
            revert InvalidExpiries(
                paymentInfo.preApprovalExpiry, paymentInfo.authorizationExpiry, paymentInfo.refundExpiry
            );
        }

        // Check fee bps do not exceed maximum value
        if (paymentInfo.maxFeeBps > 10_000) revert FeeBpsOverflow(paymentInfo.maxFeeBps);

        // Check min fee bps does not exceed max fee
        if (paymentInfo.minFeeBps > paymentInfo.maxFeeBps) {
            revert InvalidFeeBpsRange(paymentInfo.minFeeBps, paymentInfo.maxFeeBps);
        }
    }

    /// @notice Validates attempted fee adheres to constraints set by payment info
    /// @param paymentInfo PaymentInfo struct
    /// @param feeBps Fee percentage in basis points
    /// @param feeReceiver Address to receive fees
    function _validateFee(PaymentInfo calldata paymentInfo, uint16 feeBps, address feeReceiver) internal pure {
        // Check fee bps within [min, max]
        if (feeBps < paymentInfo.minFeeBps || feeBps > paymentInfo.maxFeeBps) {
            revert FeeBpsOutOfRange(feeBps, paymentInfo.minFeeBps, paymentInfo.maxFeeBps);
        }

        // Check fee recipient only zero address if zero fee bps
        if (feeBps > 0 && feeReceiver == address(0)) revert ZeroFeeReceiver();

        // Check fee recipient matches payment info if non-zero
        if (paymentInfo.feeReceiver != address(0) && paymentInfo.feeReceiver != feeReceiver) {
            revert InvalidFeeReceiver(feeReceiver, paymentInfo.feeReceiver);
        }
    }

    /// @notice Get or create treasury for an operator
    /// @param operator The operator to get/create treasury for
    /// @return treasury The operator's treasury address
    function _getOrCreateTreasury(address operator) internal returns (address treasury) {
        treasury = operatorTreasury(operator);
        if (treasury.code.length == 0) {
            bytes memory creationCode = type(OperatorTreasury).creationCode;
            bytes memory constructorArgs = abi.encode(operator);
            bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
            bytes32 salt = keccak256(abi.encode(operator));
            treasury = Create2.deploy(0, salt, bytecode);
            emit TreasuryCreated(operator, treasury);
        }
    }

    /// @notice Helper to send tokens from an operator's treasury
    /// @param operator The operator whose treasury to use
    /// @param token The token to send
    /// @param amount Amount of tokens to send
    /// @param recipient Address to receive the tokens
    function _sendTokens(address operator, address token, uint256 amount, address recipient) internal {
        address treasury = operatorTreasury(operator);
        if (treasury.code.length == 0) revert TreasuryNotFound(operator);
        OperatorTreasury(treasury).sendTokens(token, amount, recipient);
    }

    /// @notice Get the treasury address for an operator
    /// @param operator The operator to get the treasury for
    /// @return The operator's treasury address
    function operatorTreasury(address operator) public view returns (address) {
        bytes32 salt = keccak256(abi.encode(operator));
        return Create2.computeAddress(
            salt, keccak256(abi.encodePacked(type(OperatorTreasury).creationCode, abi.encode(operator)))
        );
    }
}
