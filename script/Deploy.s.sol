// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {PaymentEscrow} from "../src/PaymentEscrow.sol";
import {ERC3009PaymentCollector} from "../src/collectors/ERC3009PaymentCollector.sol";

/**
 * @notice Deploy the PaymentEscrow contract.
 *
 * forge script Deploy --account dev --sender $SENDER --rpc-url $BASE_SEPOLIA_RPC --broadcast -vvvv
 * --verify --verifier-url $SEPOLIA_BASESCAN_API --etherscan-api-key $BASESCAN_API_KEY
 */
contract Deploy is Script {
    // Known addresses
    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant SPEND_PERMISSION_MANAGER = 0xf85210B21cC50302F477BA56686d2019dC9b67Ad;
    address constant PUBLIC_ERC6492_VALIDATOR = 0xcfCE48B757601F3f351CB6f434CB0517aEEE293D;
    address constant MAGIC_SPEND = 0x011A61C07DbF256A68256B1cB51A5e246730aB92;

    function run() public {
        vm.startBroadcast();

        // Deploy PaymentEscrow with known dependencies
        PaymentEscrow paymentEscrow = new PaymentEscrow();
        ERC3009PaymentCollector erc3009Collector = new ERC3009PaymentCollector(address(paymentEscrow), MULTICALL3);

        vm.stopBroadcast();

        // Log deployed addresses
        console2.log("Deployed addresses:");
        console2.log("PaymentEscrow:", address(paymentEscrow));
        console2.log("ERC3009PaymentCollector:", address(erc3009Collector));

        // Log known addresses used
        console2.log("\nKnown addresses used:");
        console2.log("Multicall3:", MULTICALL3);
        console2.log("Permit2:", PERMIT2);
        console2.log("SpendPermissionManager:", SPEND_PERMISSION_MANAGER);
        console2.log("PublicERC6492Validator:", PUBLIC_ERC6492_VALIDATOR);
        console2.log("MagicSpend:", MAGIC_SPEND);
    }
}
