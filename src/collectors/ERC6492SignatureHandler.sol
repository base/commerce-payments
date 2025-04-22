// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IMulticall3} from "../interfaces/IMulticall3.sol";

/// @title ERC6492SignatureHandler
/// @notice Base contract for handling ERC-6492 signatures
/// @dev This contract does not perform standard ERC-6492 signature handling flow because it does not itself
///      validate the signature. It simply ensures any ERC-6492 factory/prepare data is executed it present since
///      signature validators may not implement ERC-6492 handling.
/// @author Coinbase
abstract contract ERC6492SignatureHandler {
    bytes32 internal constant _ERC6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;

    /// @notice Public Multicall3 singleton for safe ERC-6492 external calls
    IMulticall3 public immutable multicall3;

    /// @notice Constructor
    /// @param multicall3_ Public Multicall3 singleton for safe ERC-6492 external calls
    constructor(address multicall3_) {
        multicall3 = IMulticall3(multicall3_);
    }

    /// @notice Parse and process ERC-6492 signatures
    /// @param signature User-provided signature
    /// @return innerSignature Remaining signature after ERC-6492 parsing
    function _handleERC6492Signature(bytes memory signature) internal returns (bytes memory) {
        uint256 signatureLength = signature.length;

        // Early return if signature less than 32 bytes
        if (signatureLength < 32) return signature;

        // Early return if signature suffix not ERC-6492 magic value
        bytes32 suffix;
        assembly {
            suffix := mload(add(add(signature, 32), sub(signatureLength, 32)))
        }
        if (suffix != _ERC6492_MAGIC_VALUE) return signature;

        // Parse inner signature from ERC-6492 format
        bytes memory erc6492Data = new bytes(signatureLength - 32);
        for (uint256 i; i < signatureLength - 32; i++) {
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
