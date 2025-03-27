// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IPullTokensHook} from "../interfaces/IPullTokensHook.sol";
import {IERC3009} from "../interfaces/IERC3009.sol";
import {IMulticall3} from "../interfaces/IMulticall3.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract ERC3009PullTokensHook is IPullTokensHook {
    bytes32 public constant ERC6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;
    IMulticall3 public immutable multicall3;

    constructor(address _multicall3, address _paymentEscrow) IPullTokensHook(_paymentEscrow) {
        multicall3 = IMulticall3(_multicall3);
    }

    function pullTokens(PaymentEscrow.PullTokensData memory pullTokensData) external override onlyPaymentEscrow {
        bytes memory innerSignature = pullTokensData.signature;
        bytes memory signature = pullTokensData.signature;
        // Check for ERC-6492 signature format
        bytes32 magicValue;
        if (signature.length >= 32) {
            assembly {
                magicValue := mload(add(add(signature, 32), sub(mload(signature), 32)))
            }
        }

        if (signature.length >= 32 && magicValue == ERC6492_MAGIC_VALUE) {
            // parse inner signature from ERC-6492 format
            address target;
            bytes memory prepareData;
            bytes memory erc6492Data = new bytes(signature.length - 32);
            for (uint256 i = 0; i < signature.length - 32; i++) {
                erc6492Data[i] = signature[i];
            }
            (target, prepareData, innerSignature) = abi.decode(erc6492Data, (address, bytes, bytes));

            // construct call to target with prepareData
            IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
            calls[0] = IMulticall3.Call(target, prepareData);
            multicall3.tryAggregate({requireSuccess: false, calls: calls});
        }

        // First receive the tokens to this contract
        IERC3009(pullTokensData.token).receiveWithAuthorization({
            from: pullTokensData.payer,
            to: address(this),
            value: pullTokensData.maxAmount,
            validAfter: 0,
            validBefore: pullTokensData.preApprovalExpiry,
            nonce: pullTokensData.nonce,
            signature: innerSignature
        });

        // Return excess funds to buyer
        uint256 excessFunds = pullTokensData.maxAmount - pullTokensData.value;
        if (excessFunds > 0) {
            SafeTransferLib.safeTransfer(pullTokensData.token, pullTokensData.payer, excessFunds);
        }

        // Then transfer them to the escrow
        SafeTransferLib.safeTransfer(pullTokensData.token, address(paymentEscrow), pullTokensData.value);
    }
}
