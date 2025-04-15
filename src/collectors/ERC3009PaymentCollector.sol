// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {IERC3009} from "../interfaces/IERC3009.sol";
import {IMulticall3} from "../interfaces/IMulticall3.sol";
import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

/// @title ERC3009PaymentCollector
/// @notice Collect payments using ERC-3009 ReceiveWithAuthorization signatures
/// @author Coinbase
contract ERC3009PaymentCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    bytes32 internal constant _ERC6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;

    /// @notice Public Multicall3 singleton for safe ERC-6492 external calls
    IMulticall3 public immutable multicall3;

    // Selector for standard ERC3009 receiveWithAuthorization
    bytes4 private constant STANDARD_RECEIVE_WITH_AUTH_SELECTOR = bytes4(
        keccak256("receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)")
    );

    /// @notice Error emitted when both USDC-style and standard ERC3009 receiveWithAuthorization calls fail
    error ReceiveWithAuthorizationFailed();

    /// @notice Constructor
    /// @param paymentEscrow_ PaymentEscrow singleton that calls to collect tokens
    /// @param multicall3_ Public Multicall3 singleton for safe ERC-6492 external calls
    constructor(address paymentEscrow_, address multicall3_) TokenCollector(paymentEscrow_) {
        multicall3 = IMulticall3(multicall3_);
    }

    /// @inheritdoc TokenCollector
    function _collectTokens(
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        bytes calldata collectorData
    ) internal override {
        address token = paymentInfo.token;
        address payer = paymentInfo.payer;
        uint256 maxAmount = paymentInfo.maxAmount;
        address tokenStore = paymentEscrow.getTokenStore(paymentInfo.operator);

        // Apply ERC-6492 preparation call if present
        bytes memory signature = _handleERC6492Signature(collectorData);

        // Try USDC-style first, then fallback to standard if it fails
        bool success =
            _tryUSDCStyleTransfer(token, paymentInfo, signature) || _tryStandardTransfer(token, paymentInfo, signature);

        if (!success) {
            revert ReceiveWithAuthorizationFailed();
        }

        // Handle excess tokens and final transfer
        _handleTokenTransfers(token, payer, tokenStore, maxAmount, amount);
    }

    function _tryUSDCStyleTransfer(
        address token,
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        bytes memory signature
    ) internal returns (bool) {
        bytes32 nonce = _getHashPayerAgnostic(paymentInfo);

        (bool success,) = token.call(
            abi.encodeWithSelector(
                IERC3009.receiveWithAuthorization.selector,
                paymentInfo.payer,
                address(this),
                paymentInfo.maxAmount,
                0,
                paymentInfo.preApprovalExpiry,
                nonce,
                signature
            )
        );

        return success;
    }

    function _tryStandardTransfer(address token, PaymentEscrow.PaymentInfo calldata paymentInfo, bytes memory signature)
        internal
        returns (bool)
    {
        if (signature.length != 65) return false;

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        bytes32 nonce = _getHashPayerAgnostic(paymentInfo);

        (bool success,) = token.call(
            abi.encodeWithSelector(
                STANDARD_RECEIVE_WITH_AUTH_SELECTOR,
                paymentInfo.payer,
                address(this),
                paymentInfo.maxAmount,
                0,
                paymentInfo.preApprovalExpiry,
                nonce,
                v,
                r,
                s
            )
        );

        return success;
    }

    function _handleTokenTransfers(address token, address payer, address tokenStore, uint256 maxAmount, uint256 amount)
        internal
    {
        unchecked {
            uint256 excess = maxAmount - amount;
            if (excess > 0) {
                SafeTransferLib.safeTransfer(token, payer, excess);
            }
        }
        SafeTransferLib.safeTransfer(token, tokenStore, amount);
    }

    /// @notice Parse and process ERC-6492 signatures
    /// @param signature User-provided signature
    /// @return innerSignature Remaining signature after ERC-6492 parsing
    function _handleERC6492Signature(bytes memory signature) internal returns (bytes memory) {
        // Early return if signature less than 32 bytes
        if (signature.length < 32) return signature;

        // Early return if signature suffix not ERC-6492 magic value
        bytes32 suffix;
        assembly {
            suffix := mload(add(add(signature, 32), sub(mload(signature), 32)))
        }
        if (suffix != _ERC6492_MAGIC_VALUE) return signature;

        // Parse inner signature from ERC-6492 format
        bytes memory erc6492Data = new bytes(signature.length - 32);
        for (uint256 i; i < signature.length - 32; i++) {
            erc6492Data[i] = signature[i];
        }
        address prepareTarget;
        bytes memory prepareData;
        (prepareTarget, prepareData, signature) = abi.decode(erc6492Data, (address, bytes, bytes));

        // Construct call to prepareTarget with prepareData
        // Calls made through a neutral public contract to prevent abuse of using this contract as sender
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
        calls[0] = IMulticall3.Call(prepareTarget, prepareData);
        multicall3.tryAggregate({requireSuccess: false, calls: calls});

        return signature;
    }
}
