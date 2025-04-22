// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

import {PaymentEscrow} from "./PaymentEscrow.sol";
import {TokenCollector} from "./collectors/TokenCollector.sol";

contract ArbitrationOperator {
    uint16 constant MAX_FEE_BPS = 10_000;

    PaymentEscrow public immutable paymentEscrow;
    address public immutable arbiter;
    address public immutable paymentCollector;

    uint256 nextPaymentId;
    uint256 defaultLockup;
    mapping(address receiver => uint48 lockup) internal _receiverLockup;
    mapping(uint256 paymentId => uint48 releaseTimestamp) public releaseTimestamps;
    mapping(uint256 paymentId => bytes payerReceiverToken) internal _cachedInfo;
    mapping(address receiver => mapping(uint256 nonce => bool used)) public nonceUsed;

    event DefaultLockupUpdated(uint256 lockup);
    event ReceiverLockupOverridden(address receiver, uint256 lockup);
    event ReceiverLockupOverrideRemoved(address receiver);

    constructor(address paymentEscrow_, address arbiter_, uint256 defaultLockup_) {
        paymentEscrow = PaymentEscrow(paymentEscrow_);
        arbiter = arbiter_;
        defaultLockup = defaultLockup_;
        paymentCollector = address(new ArbitrationPaymentCollector(paymentEscrow_, address(this)));
    }

    modifier onlyArbiter() {
        if (msg.sender != arbiter) revert();
        _;
    }

    function setDefaultLockup(uint48 lockup) external onlyArbiter {
        defaultLockup = lockup;
        emit DefaultLockupUpdated(lockup);
    }

    function setReceiverLockup(address receiver, uint48 lockup) external onlyArbiter {
        if (lockup != defaultLockup) {
            // Overriding default lockup, set with offset to flag override
            _receiverLockup[receiver] = lockup + 1;
            emit ReceiverLockupOverridden(receiver, lockup);
        } else {
            // Removing override, delete storage to use default lockup
            delete _receiverLockup[receiver];
            emit ReceiverLockupOverrideRemoved(receiver);
        }
    }

    function authorize(address token, address receiver, uint256 amount) external {
        // Add lockup delay to current timestamp for payment release
        uint256 paymentId = nextPaymentId++;
        releaseTimestamps[paymentId] = uint48(block.timestamp + getLockup(receiver));

        // Cache part of payment info
        _cachedInfo[paymentId] = abi.encode(msg.sender, receiver, token);

        // Authorize payment
        paymentEscrow.authorize(
            _getPaymentInfo(paymentId, msg.sender, receiver, token), amount, paymentCollector, hex""
        );
    }

    function capture(uint256 paymentId, uint256 amount) external {
        // Check at or after release timestamp
        if (block.timestamp < releaseTimestamps[paymentId]) revert();

        // Check sender is receiver
        (address payer, address receiver, address token) =
            abi.decode(_cachedInfo[paymentId], (address, address, address));
        if (msg.sender != receiver) revert();

        // Capture funds
        paymentEscrow.capture(_getPaymentInfo(paymentId, payer, receiver, token), amount, 0, address(0));
    }

    function earlyCapture(uint256 paymentId, uint256 amount, uint16 feeBps, uint256 nonce, bytes calldata signature)
        external
        onlyArbiter
    {
        // Check before release timestamp
        if (block.timestamp >= releaseTimestamps[paymentId]) revert();

        // Check nonce not used
        (address payer, address receiver, address token) =
            abi.decode(_cachedInfo[paymentId], (address, address, address));
        if (nonceUsed[receiver][nonce]) revert();

        // Check receiver signed early capture request
        bytes32 message = SignatureCheckerLib.toEthSignedMessageHash(keccak256(abi.encode(paymentId, feeBps, nonce)));
        if (!SignatureCheckerLib.isValidSignatureNow(receiver, message, signature)) revert();

        paymentEscrow.capture(_getPaymentInfo(paymentId, payer, receiver, token), amount, feeBps, arbiter);
    }

    function void(uint256 paymentId) external {
        // Check sender is arbiter or receiver
        (address payer, address receiver, address token) =
            abi.decode(_cachedInfo[paymentId], (address, address, address));
        if (msg.sender != arbiter || msg.sender != receiver) revert();

        paymentEscrow.void(_getPaymentInfo(paymentId, payer, receiver, token));
    }

    function refund(uint256 paymentId, uint256 amount, address refundCollector, bytes calldata collectorData)
        external
        onlyArbiter
    {
        (address payer, address receiver, address token) =
            abi.decode(_cachedInfo[paymentId], (address, address, address));
        paymentEscrow.refund(_getPaymentInfo(paymentId, payer, receiver, token), amount, refundCollector, collectorData);
    }

    function getLockup(address receiver) public view returns (uint256) {
        uint256 lockupOverride = _receiverLockup[receiver];
        return lockupOverride > 0 ? lockupOverride - 1 : defaultLockup;
    }

    function _getPaymentInfo(uint256 paymentId, address payer, address receiver, address token)
        internal
        view
        returns (PaymentEscrow.PaymentInfo memory)
    {
        uint48 releaseTimestamp = releaseTimestamps[paymentId];
        return PaymentEscrow.PaymentInfo({
            operator: address(this),
            payer: payer,
            receiver: receiver,
            token: token,
            maxAmount: type(uint120).max,
            preApprovalExpiry: 0,
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: 0,
            maxFeeBps: MAX_FEE_BPS,
            feeReceiver: address(0),
            salt: (paymentId << 48) + releaseTimestamp
        });
    }
}

contract ArbitrationPaymentCollector is TokenCollector {
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    address public immutable operator;

    constructor(address paymentEscrow_, address operator_) TokenCollector(paymentEscrow_) {
        operator = operator_;
    }

    function _collectTokens(PaymentEscrow.PaymentInfo calldata paymentInfo, uint256 amount, bytes calldata)
        internal
        override
    {
        if (paymentInfo.operator != operator) revert();
        SafeTransferLib.safeTransferFrom(paymentInfo.token, paymentInfo.payer, address(paymentEscrow), amount);
    }
}
