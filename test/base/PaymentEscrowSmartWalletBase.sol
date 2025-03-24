// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrowBase} from "./PaymentEscrowBase.sol";
import {Test} from "forge-std/Test.sol";

import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {CoinbaseSmartWalletFactory} from "smart-wallet/CoinbaseSmartWalletFactory.sol";
import {PaymentEscrow} from "src/PaymentEscrow.sol";

contract PaymentEscrowSmartWalletBase is PaymentEscrowBase {
    // Constants for EIP-6492 support
    bytes32 constant EIP6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;
    bytes32 constant CBSW_MESSAGE_TYPEHASH = keccak256("CoinbaseSmartWalletMessage(bytes32 hash)");

    // Smart wallet specific state
    CoinbaseSmartWalletFactory public smartWalletFactory;
    address public smartWalletImplementation;
    address public counterfactualWalletOwner;
    address public smartWalletCounterfactual; // The counterfactual address
    CoinbaseSmartWallet public smartWalletDeployed; // Helper instance for using smart wallet functions
    uint256 internal constant COUNTERFACTUAL_WALLET_OWNER_PK = 0x5678; // Different from BUYER_PK
    uint256 internal constant DEPLOYED_WALLET_OWNER_PK = 0x1111;

    function setUp() public virtual override {
        super.setUp();

        // Deploy the implementation and factory
        smartWalletImplementation = address(new CoinbaseSmartWallet());
        smartWalletFactory = new CoinbaseSmartWalletFactory(smartWalletImplementation);

        // Create and initialize deployed wallet through factory
        address deployedWalletOwner = vm.addr(DEPLOYED_WALLET_OWNER_PK);
        bytes[] memory deployedWalletOwners = new bytes[](1);
        deployedWalletOwners[0] = abi.encode(deployedWalletOwner);
        smartWalletDeployed = CoinbaseSmartWallet(payable(smartWalletFactory.createAccount(deployedWalletOwners, 0)));

        // Create counterfactual wallet address
        counterfactualWalletOwner = vm.addr(COUNTERFACTUAL_WALLET_OWNER_PK);
        bytes[] memory counterfactualWalletOwners = new bytes[](1);
        counterfactualWalletOwners[0] = abi.encode(counterfactualWalletOwner);
        smartWalletCounterfactual = smartWalletFactory.getAddress(counterfactualWalletOwners, 0);

        // Fund the smart wallets
        mockERC3009Token.mint(address(smartWalletDeployed), 1000e6);
        mockERC3009Token.mint(smartWalletCounterfactual, 1000e6);
    }

    function _sign(uint256 pk, bytes32 hash) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        return abi.encodePacked(r, s, v);
    }

    function _signSmartWalletERC3009(
        address buyer,
        address captureAddress,
        uint256 value,
        uint256 validBefore,
        uint48 captureDeadline,
        uint256 ownerPk,
        uint256 ownerIndex
    ) internal view returns (bytes memory) {
        // First compute the ERC3009 digest that needs to be signed
        bytes32 nonce = keccak256(
            abi.encode(
                PaymentEscrow.PaymentDetails({
                    operator: operator,
                    buyer: buyer,
                    captureAddress: captureAddress,
                    token: address(mockERC3009Token),
                    value: value,
                    authorizeDeadline: validBefore,
                    captureDeadline: captureDeadline,
                    feeBps: FEE_BPS,
                    feeRecipient: feeRecipient,
                    salt: uint256(0),
                    authType: PaymentEscrow.AuthorizationType.ERC3009
                })
            )
        );

        // This is what needs to be signed by the smart wallet
        bytes32 erc3009Digest = _getERC3009Digest(buyer, value, 0, validBefore, nonce);

        // Now wrap the ERC3009 digest in the smart wallet's domain
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Coinbase Smart Wallet")),
                keccak256(bytes("1")),
                block.chainid,
                buyer
            )
        );

        bytes32 messageHash = keccak256(abi.encode(CBSW_MESSAGE_TYPEHASH, erc3009Digest));
        bytes32 finalHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, messageHash));

        bytes memory signature = _sign(ownerPk, finalHash);
        return abi.encode(CoinbaseSmartWallet.SignatureWrapper(ownerIndex, signature));
    }

    function _getERC3009Digest(address buyer, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 nonce)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                mockERC3009Token.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                buyer,
                address(paymentEscrow),
                value,
                validAfter,
                validBefore,
                nonce
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", mockERC3009Token.DOMAIN_SEPARATOR(), structHash));
    }

    function _signSmartWalletERC3009WithERC6492(
        address buyer,
        address captureAddress,
        uint256 value,
        uint256 authorizeDeadline,
        uint48 captureDeadline,
        uint256 ownerPk,
        uint256 ownerIndex
    ) internal view returns (bytes memory) {
        // First get the normal smart wallet signature
        bytes memory signature = _signSmartWalletERC3009(
            buyer, captureAddress, value, authorizeDeadline, captureDeadline, ownerPk, ownerIndex
        );

        // Prepare the factory call data
        bytes[] memory allInitialOwners = new bytes[](1);
        allInitialOwners[0] = abi.encode(vm.addr(ownerPk));
        bytes memory factoryCallData =
            abi.encodeCall(CoinbaseSmartWalletFactory.createAccount, (allInitialOwners, ownerIndex));

        // Then wrap it in ERC6492 format
        bytes memory eip6492Signature = abi.encode(address(smartWalletFactory), factoryCallData, signature);
        return abi.encodePacked(eip6492Signature, EIP6492_MAGIC_VALUE);
    }
}
