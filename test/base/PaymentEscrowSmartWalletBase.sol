// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrowBase} from "./PaymentEscrowBase.sol";
import {Test} from "forge-std/Test.sol";

import {CoinbaseSmartWallet} from "smart-wallet/CoinbaseSmartWallet.sol";
import {CoinbaseSmartWalletFactory} from "smart-wallet/CoinbaseSmartWalletFactory.sol";
import {PaymentEscrow} from "src/PaymentEscrow.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {MagicSpend} from "magicspend/MagicSpend.sol";

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
    uint256 internal constant COUNTERFACTUAL_WALLET_OWNER_PK = 0x5678; // Different from payer_PK
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

        // Add spend permission manager as owner of (deployed) smart wallet
        vm.prank(deployedWalletOwner);
        smartWalletDeployed.addOwnerAddress(address(spendPermissionManager));
    }

    function _sign(uint256 pk, bytes32 hash) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        return abi.encodePacked(r, s, v);
    }

    function _signSmartWalletERC3009(PaymentEscrow.PaymentInfo memory paymentInfo, uint256 ownerPk, uint256 ownerIndex)
        internal
        view
        returns (bytes memory)
    {
        address payer = paymentInfo.payer;
        paymentInfo.payer = address(0);
        bytes32 nonce = paymentEscrow.getHash(paymentInfo);
        paymentInfo.payer = payer;

        // This is what needs to be signed by the smart wallet
        bytes32 erc3009Digest = _getERC3009Digest(
            payer, hooks[TokenCollector.ERC3009], paymentInfo.maxAmount, 0, paymentInfo.preApprovalExpiry, nonce
        );

        // Now wrap the ERC3009 digest in the smart wallet's domain
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Coinbase Smart Wallet")),
                keccak256(bytes("1")),
                block.chainid,
                payer
            )
        );

        bytes32 messageHash = keccak256(abi.encode(CBSW_MESSAGE_TYPEHASH, erc3009Digest));
        bytes32 finalHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, messageHash));

        bytes memory signature = _sign(ownerPk, finalHash);
        return abi.encode(CoinbaseSmartWallet.SignatureWrapper(ownerIndex, signature));
    }

    function _signSmartWalletERC3009WithERC6492(
        PaymentEscrow.PaymentInfo memory paymentInfo,
        uint256 ownerPk,
        uint256 ownerIndex
    ) internal view returns (bytes memory) {
        // First get the normal smart wallet signature
        bytes memory signature = _signSmartWalletERC3009(paymentInfo, ownerPk, ownerIndex);

        // Prepare the factory call data
        bytes[] memory allInitialOwners = new bytes[](1);
        allInitialOwners[0] = abi.encode(vm.addr(ownerPk));
        bytes memory factoryCallData =
            abi.encodeCall(CoinbaseSmartWalletFactory.createAccount, (allInitialOwners, ownerIndex));

        // Then wrap it in ERC6492 format
        bytes memory eip6492Signature = abi.encode(address(smartWalletFactory), factoryCallData, signature);
        return abi.encodePacked(eip6492Signature, EIP6492_MAGIC_VALUE);
    }

    /// @notice Helper to create a SpendPermission struct with test defaults
    function _createSpendPermission(PaymentEscrow.PaymentInfo memory paymentInfo)
        internal
        view
        returns (SpendPermissionManager.SpendPermission memory)
    {
        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        return SpendPermissionManager.SpendPermission({
            account: paymentInfo.payer,
            spender: hooks[TokenCollector.SpendPermission],
            token: address(paymentInfo.token),
            allowance: uint160(paymentInfo.maxAmount),
            period: type(uint48).max,
            start: 0,
            end: uint48(paymentInfo.preApprovalExpiry),
            salt: uint256(paymentInfoHash),
            extraData: hex""
        });
    }

    function _signSpendPermission(
        SpendPermissionManager.SpendPermission memory spendPermission,
        uint256 ownerPk,
        uint256 ownerIndex
    ) internal view returns (bytes memory) {
        bytes32 spendPermissionHash = spendPermissionManager.getHash(spendPermission);
        bytes32 replaySafeHash =
            CoinbaseSmartWallet(payable(spendPermission.account)).replaySafeHash(spendPermissionHash);
        bytes memory signature = _sign(ownerPk, replaySafeHash);
        return abi.encode(CoinbaseSmartWallet.SignatureWrapper(ownerIndex, signature));
    }

    function _signSpendPermissionWithERC6492(
        SpendPermissionManager.SpendPermission memory spendPermission,
        uint256 ownerPk,
        uint256 ownerIndex
    ) internal view returns (bytes memory) {
        bytes32 spendPermissionHash = spendPermissionManager.getHash(spendPermission);

        // Construct replaySafeHash without relying on the account contract being deployed
        bytes32 cbswDomainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Coinbase Smart Wallet")),
                keccak256(bytes("1")),
                block.chainid,
                spendPermission.account
            )
        );
        bytes32 replaySafeHash = keccak256(
            abi.encodePacked(
                "\x19\x01", cbswDomainSeparator, keccak256(abi.encode(CBSW_MESSAGE_TYPEHASH, spendPermissionHash))
            )
        );
        bytes memory signature = _sign(ownerPk, replaySafeHash);
        bytes memory wrappedSignature = abi.encode(CoinbaseSmartWallet.SignatureWrapper(ownerIndex, signature));

        // Wrap in ERC6492 format
        bytes[] memory allInitialOwners = new bytes[](1);
        allInitialOwners[0] = abi.encode(vm.addr(ownerPk));
        bytes memory factoryCallData =
            abi.encodeCall(CoinbaseSmartWalletFactory.createAccount, (allInitialOwners, ownerIndex));
        bytes memory eip6492Signature = abi.encode(address(smartWalletFactory), factoryCallData, wrappedSignature);
        return abi.encodePacked(eip6492Signature, EIP6492_MAGIC_VALUE);
    }

    function _createWithdrawRequest(SpendPermissionManager.SpendPermission memory spendPermission)
        internal
        view
        returns (MagicSpend.WithdrawRequest memory)
    {
        bytes32 permissionHash = spendPermissionManager.getHash(spendPermission);
        uint128 hashPortion = uint128(uint256(permissionHash));
        uint256 nonce = uint256(hashPortion);

        return MagicSpend.WithdrawRequest({
            asset: address(0),
            amount: 0,
            nonce: nonce,
            expiry: type(uint48).max,
            signature: new bytes(0)
        });
    }

    function _signWithdrawRequest(address account, MagicSpend.WithdrawRequest memory withdrawRequest)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 hash = magicSpend.getHash(account, withdrawRequest);
        return _sign(magicSpendOwnerPk, hash);
    }
}
