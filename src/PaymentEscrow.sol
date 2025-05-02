// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";
import {LibClone} from "solady/utils/LibClone.sol";

import {TokenStore} from "./TokenStore.sol";
import {TokenCollector} from "./collectors/TokenCollector.sol";

/// @title PaymentEscrow
/// @notice Facilitate payments through an escrow.
/// @dev By escrowing payment, this contract can mimic the 2-step payment pattern of "authorization" and "capture".
/// @dev Authorization is defined as placing a hold on a payer's funds temporarily.
/// @dev Capture is defined as distributing payment to the end recipient.
/// @dev A trusted Operator plays the primary role of moving payments between both parties.
/// @author Coinbase
contract PaymentEscrow is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

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
        "PaymentInfo(address operator,address payer,address receiver,address token,uint120 maxAmount,uint48 preApprovalExpiry,uint48 authorizationExpiry,uint48 refundExpiry,uint16 minFeeBps,uint16 maxFeeBps,address feeReceiver,uint256 salt)"
    );

    uint16 internal constant _MAX_FEE_BPS = 10_000;

    /// @notice Implementation contract for operator token stores
    address public immutable tokenStoreImplementation;

    /// @notice State per unique payment
    mapping(bytes32 paymentInfoHash => PaymentState state) public paymentState;

    /// @notice Emitted when a payment is charged and immediately captured
    event PaymentCharged(
        bytes32 indexed paymentInfoHash,
        PaymentInfo paymentInfo,
        uint256 amount,
        address tokenCollector,
        uint16 feeBps,
        address feeReceiver
    );

    /// @notice Emitted when authorized (escrowed) amount is increased
    event PaymentAuthorized(
        bytes32 indexed paymentInfoHash, PaymentInfo paymentInfo, uint256 amount, address tokenCollector
    );

    /// @notice Emitted when payment is captured from escrow
    event PaymentCaptured(bytes32 indexed paymentInfoHash, uint256 amount, uint16 feeBps, address feeReceiver);

    /// @notice Emitted when an authorized payment is voided, returning any escrowed funds to the payer
    event PaymentVoided(bytes32 indexed paymentInfoHash, uint256 amount);

    /// @notice Emitted when an authorized payment is reclaimed, returning any escrowed funds to the payer
    event PaymentReclaimed(bytes32 indexed paymentInfoHash, uint256 amount);

    /// @notice Emitted when a captured payment is refunded
    event PaymentRefunded(bytes32 indexed paymentInfoHash, uint256 amount, address tokenCollector);

    /// @notice Event emitted when new token store is created
    event TokenStoreCreated(address indexed operator, address tokenStore);

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

    /// @notice Check call sender is specified address
    /// @param sender Address to enforce is the call sender
    modifier onlySender(address sender) {
        if (msg.sender != sender) revert InvalidSender(msg.sender, sender);
        _;
    }

    /// @notice Ensures amount is non-zero and does not overflow storage
    /// @param amount Quantity of tokens being requested for a given operation
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        if (amount > type(uint120).max) revert AmountOverflow(amount, type(uint120).max);
        _;
    }

    /// @notice Constructor that auto-deploys TokenStore implementation to clone
    constructor() {
        tokenStoreImplementation = address(new TokenStore(address(this)));
    }

    /// @notice Transfers funds from payer to receiver in one step
    /// @dev If amount is less than the authorized amount, only amount is taken from payer
    /// @dev Reverts if the authorization has been voided or expired
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount to charge and capture
    /// @param tokenCollector Address of the token collector
    /// @param collectorData Data to pass to the token collector
    /// @param feeBps Fee percentage to apply (must be within min/max range)
    /// @param feeReceiver Address to receive fees (should match the paymentInfo.feeReceiver unless that is 0 in which case it can be any address)
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
        emit PaymentCharged(paymentInfoHash, paymentInfo, amount, tokenCollector, feeBps, feeReceiver);

        // Transfer tokens into escrow
        _collectTokens(paymentInfo, amount, tokenCollector, collectorData, TokenCollector.CollectorType.Payment);

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
        emit PaymentAuthorized(paymentInfoHash, paymentInfo, amount, tokenCollector);

        // Transfer tokens into escrow
        _collectTokens(paymentInfo, amount, tokenCollector, collectorData, TokenCollector.CollectorType.Payment);
    }

    /// @notice Transfer previously-escrowed funds to receiver
    /// @dev Can be called multiple times up to cumulative authorized amount
    /// @dev Can only be called by the operator
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount to capture
    /// @param feeBps Fee percentage to apply (must be within min/max range)
    /// @param feeReceiver Address to receive fees (should match the paymentInfo.feeReceiver unless that is 0 in which case it can be any address)
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
        emit PaymentCaptured(paymentInfoHash, amount, feeBps, feeReceiver);

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

        // Transfer tokens to payer from token store
        _sendTokens(paymentInfo.operator, paymentInfo.token, paymentInfo.payer, authorizedAmount, false);
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

        // Transfer tokens to payer from token store
        _sendTokens(paymentInfo.operator, paymentInfo.token, paymentInfo.payer, authorizedAmount, false);
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
        _collectTokens(paymentInfo, amount, tokenCollector, collectorData, TokenCollector.CollectorType.Refund);
        _sendTokens(paymentInfo.operator, paymentInfo.token, paymentInfo.payer, amount, false);
    }

    /// @notice Disburse fees from a fee receiver's token store to the fee receiver
    /// @param feeReceiver The fee receiver to disburse fees for
    /// @param token The token to disburse
    function disburseFeesToFeeReceiver(address feeReceiver, address token) external {
        address feeStore = getFeeStore(feeReceiver);
        if (feeStore.code.length == 0) return;

        uint256 amount = IERC20(token).balanceOf(feeStore);
        if (amount == 0) return;

        TokenStore(feeStore).sendTokens(token, feeReceiver, amount);
    }

    /// @notice Disburse fees from a fee receiver's token store to a recipient
    /// @dev Can only be called by the fee receiver
    /// @param feeReceiver The fee receiver to disburse fees for
    /// @param token The token to disburse
    /// @param recipient The recipient to disburse fees to
    function disburseFees(address feeReceiver, address token, address recipient) external onlySender(feeReceiver) {
        address feeStore = getFeeStore(feeReceiver);
        if (feeStore.code.length == 0) return;

        uint256 amount = IERC20(token).balanceOf(feeStore);
        if (amount == 0) return;

        TokenStore(feeStore).sendTokens(token, recipient, amount);
    }

    /// @notice Get hash of PaymentInfo struct
    /// @dev Includes chainId and verifyingContract in hash for cross-chain and cross-contract uniqueness
    /// @param paymentInfo PaymentInfo struct
    /// @return Hash of payment info for the current chain and contract address
    function getHash(PaymentInfo calldata paymentInfo) public view returns (bytes32) {
        bytes32 paymentInfoHash = keccak256(abi.encode(PAYMENT_INFO_TYPEHASH, paymentInfo));
        return keccak256(abi.encode(block.chainid, address(this), paymentInfoHash));
    }

    /// @notice Get the token store address for an operator
    /// @param operator The operator to get the token store for
    /// @return The operator's token store address
    function getTokenStore(address operator) public view returns (address) {
        return LibClone.predictDeterministicAddress({
            implementation: tokenStoreImplementation,
            salt: bytes32(bytes20(operator)),
            deployer: address(this)
        });
    }

    /// @notice Get the fee store address for a fee receiver
    /// @param feeReceiver The fee receiver to get the store for
    /// @return The fee receiver's fee store address
    function getFeeStore(address feeReceiver) public view returns (address) {
        // Use a special salt prefix to differentiate from operator token stores
        bytes32 salt = keccak256(abi.encodePacked("fee", bytes20(feeReceiver)));
        return LibClone.predictDeterministicAddress({
            implementation: tokenStoreImplementation,
            salt: salt,
            deployer: address(this)
        });
    }

    /// @notice Transfer tokens into this contract
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount of tokens to collect
    /// @param tokenCollector Address of the token collector
    /// @param collectorData Data to pass to the token collector
    /// @param collectorType Type of collector to enforce (payment or refund)
    function _collectTokens(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData,
        TokenCollector.CollectorType collectorType
    ) internal {
        // Check token collector matches required type
        if (TokenCollector(tokenCollector).collectorType() != collectorType) revert InvalidCollectorForOperation();

        // Measure balance change of token store to enforce as equal to expected amount
        address token = paymentInfo.token;
        address tokenStore = getTokenStore(paymentInfo.operator);
        uint256 tokenStoreBalanceBefore = IERC20(token).balanceOf(tokenStore);
        TokenCollector(tokenCollector).collectTokens(paymentInfo, tokenStore, amount, collectorData);
        uint256 tokenStoreBalanceAfter = IERC20(token).balanceOf(tokenStore);
        if (tokenStoreBalanceAfter != tokenStoreBalanceBefore + amount) revert TokenCollectionFailed();
    }

    /// @notice Helper function to make a low-level call to TokenStore.sendTokens
    /// @param tokenStore The token store to call
    /// @param token The token to send
    /// @param recipient The recipient of the tokens
    /// @param amount The amount to send
    /// @return success Whether the call succeeded
    /// @return returnData The return data from the call
    function _trySendTokens(address tokenStore, address token, address recipient, uint256 amount)
        internal
        returns (bool success, bytes memory returnData)
    {
        bytes memory callData = abi.encodeWithSelector(TokenStore.sendTokens.selector, token, recipient, amount);
        return tokenStore.call(callData);
    }

    /// @notice Send tokens from an operator's token store
    /// @param operator The operator whose token store to use
    /// @param token The token to send
    /// @param recipient Address to receive the tokens
    /// @param amount Amount of tokens to send
    /// @param swallowRevert Whether to swallow a revert and return false instead
    /// @return success Whether the transfer was successful
    function _sendTokens(address operator, address token, address recipient, uint256 amount, bool swallowRevert)
        internal
        returns (bool)
    {
        // Attempt to transfer tokens
        address tokenStore = getTokenStore(operator);
        (bool success, bytes memory returnData) = _trySendTokens(tokenStore, token, recipient, amount);

        if (success && returnData.length == 32 && abi.decode(returnData, (bool))) {
            return true;
        } else if (tokenStore.code.length == 0) {
            // Call failed from undeployed TokenStore, deploy and try again
            tokenStore = LibClone.cloneDeterministic({
                implementation: tokenStoreImplementation,
                salt: bytes32(bytes20(operator))
            });
            emit TokenStoreCreated(operator, tokenStore);

            // Try the low-level call again on the newly deployed store
            (success, returnData) = _trySendTokens(tokenStore, token, recipient, amount);
            if (success && returnData.length == 32 && abi.decode(returnData, (bool))) {
                return true;
            }
        }

        // Call failed from revert
        if (swallowRevert) {
            return false;
        }
        // If not swallowing, bubble up revert data
        if (returnData.length > 0) {
            assembly ("memory-safe") {
                let returnDataSize := mload(returnData)
                revert(add(32, returnData), returnDataSize)
            }
        }
        revert("Token transfer failed");
    }

    /// @notice Sends tokens to receiver and/or feeReceiver
    /// @dev If the fee transfer fails, the fee will be stored in a TokenStore specific to the fee receiver
    /// @param token Token to transfer
    /// @param receiver Address to receive payment
    /// @param amount Total amount to split between payment and fees
    /// @param feeBps Fee percentage in basis points
    /// @param feeReceiver Address to receive fees
    function _distributeTokens(address token, address receiver, uint256 amount, uint16 feeBps, address feeReceiver)
        internal
    {
        uint256 feeAmount = amount * feeBps / _MAX_FEE_BPS;

        // Send fee portion if non-zero
        if (feeAmount > 0) {
            // Try to send fees directly first
            bool feeTransferSucceeded = _sendTokens(msg.sender, token, feeReceiver, feeAmount, true);

            if (!feeTransferSucceeded) {
                // If direct transfer fails, store fees in fee store
                address feeStore = getFeeStore(feeReceiver);

                if (feeStore.code.length == 0) {
                    // Deploy fee store if it doesn't exist
                    bytes32 salt = keccak256(abi.encodePacked("fee", bytes20(feeReceiver)));
                    feeStore = LibClone.cloneDeterministic({implementation: tokenStoreImplementation, salt: salt});
                    emit TokenStoreCreated(feeReceiver, feeStore);
                }
                _sendTokens(msg.sender, token, feeStore, feeAmount, true);
            }
        }

        // Send remaining amount to receiver
        if (amount > feeAmount) _sendTokens(msg.sender, token, receiver, amount - feeAmount, false);
    }

    /// @notice Validates required properties of a payment
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Token amount to validate against
    function _validatePayment(PaymentInfo calldata paymentInfo, uint256 amount) internal view {
        uint120 maxAmount = paymentInfo.maxAmount;
        uint48 preApprovalExp = paymentInfo.preApprovalExpiry;
        uint48 authorizationExp = paymentInfo.authorizationExpiry;
        uint48 refundExp = paymentInfo.refundExpiry;
        uint16 minFeeBps = paymentInfo.minFeeBps;
        uint16 maxFeeBps = paymentInfo.maxFeeBps;
        uint48 currentTime = uint48(block.timestamp);

        // Check amount does not exceed maximum
        if (amount > maxAmount) revert ExceedsMaxAmount(amount, maxAmount);

        // Timestamp comparisons cannot overflow uint48
        if (currentTime >= preApprovalExp) revert AfterPreApprovalExpiry(currentTime, preApprovalExp);

        // Check expiry timestamps properly ordered
        if (preApprovalExp > authorizationExp || authorizationExp > refundExp) {
            revert InvalidExpiries(preApprovalExp, authorizationExp, refundExp);
        }

        // Check fee bps do not exceed maximum value
        if (maxFeeBps > _MAX_FEE_BPS) revert FeeBpsOverflow(maxFeeBps);

        // Check min fee bps does not exceed max fee
        if (minFeeBps > maxFeeBps) revert InvalidFeeBpsRange(minFeeBps, maxFeeBps);
    }

    /// @notice Validates attempted fee adheres to constraints set by payment info
    /// @param paymentInfo PaymentInfo struct
    /// @param feeBps Fee percentage in basis points
    /// @param feeReceiver Address to receive fees
    function _validateFee(PaymentInfo calldata paymentInfo, uint16 feeBps, address feeReceiver) internal pure {
        uint16 minFeeBps = paymentInfo.minFeeBps;
        uint16 maxFeeBps = paymentInfo.maxFeeBps;
        address configuredFeeReceiver = paymentInfo.feeReceiver;

        // Check fee bps within [min, max]
        if (feeBps < minFeeBps || feeBps > maxFeeBps) revert FeeBpsOutOfRange(feeBps, minFeeBps, maxFeeBps);

        // Check fee recipient only zero address if zero fee bps
        if (feeReceiver == address(0) && feeBps > 0) revert ZeroFeeReceiver();

        // Check fee receiver matches payment info if non-zero
        if (configuredFeeReceiver != address(0) && configuredFeeReceiver != feeReceiver) {
            revert InvalidFeeReceiver(feeReceiver, configuredFeeReceiver);
        }
    }
}
