// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {AuthCaptureEscrow} from "../src/AuthCaptureEscrow.sol";
import {ERC3009PaymentCollector} from "../src/collectors/ERC3009PaymentCollector.sol";
import {Permit2PaymentCollector} from "../src/collectors/Permit2PaymentCollector.sol";
import {PreApprovalPaymentCollector} from "../src/collectors/PreApprovalPaymentCollector.sol";
import {SpendPermissionPaymentCollector} from "../src/collectors/SpendPermissionPaymentCollector.sol";
import {OperatorRefundCollector} from "../src/collectors/OperatorRefundCollector.sol";

/**
 * @notice Deploy the AuthCaptureEscrow contract and all collectors.
 *
 * forge script Deploy --account spmdeployer --sender $SPM_DEPLOYER --rpc-url $BASE_SEPOLIA_RPC --broadcast -vvvv --verify --verifier-url $SEPOLIA_BASESCAN_API --etherscan-api-key $BASESCAN_API_KEY
 * forge script Deploy --account spmdeployer --sender $SPM_DEPLOYER --rpc-url $BASE_RPC --broadcast -vvvv --verify --verifier-url $BASESCAN_API --etherscan-api-key $BASESCAN_API_KEY
 */
contract Deploy is Script {
    // Known addresses
    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant SPEND_PERMISSION_MANAGER = 0xf85210B21cC50302F477BA56686d2019dC9b67Ad;

    function run() public {
        vm.startBroadcast();

        // Deploy AuthCaptureEscrow with known dependencies
        AuthCaptureEscrow authCaptureEscrow = new AuthCaptureEscrow();

        // Deploy all collectors
        ERC3009PaymentCollector erc3009Collector = new ERC3009PaymentCollector(address(authCaptureEscrow), MULTICALL3);

        Permit2PaymentCollector permit2Collector =
            new Permit2PaymentCollector(address(authCaptureEscrow), PERMIT2, MULTICALL3);

        PreApprovalPaymentCollector preApprovalCollector = new PreApprovalPaymentCollector(address(authCaptureEscrow));

        SpendPermissionPaymentCollector spendPermissionCollector =
            new SpendPermissionPaymentCollector(address(authCaptureEscrow), SPEND_PERMISSION_MANAGER);

        OperatorRefundCollector operatorRefundCollector = new OperatorRefundCollector(address(authCaptureEscrow));

        vm.stopBroadcast();

        // Log deployed addresses
        console2.log("Deployed addresses:");
        console2.log("AuthCaptureEscrow:", address(authCaptureEscrow));
        console2.log("ERC3009PaymentCollector:", address(erc3009Collector));
        console2.log("Permit2PaymentCollector:", address(permit2Collector));
        console2.log("PreApprovalPaymentCollector:", address(preApprovalCollector));
        console2.log("SpendPermissionPaymentCollector:", address(spendPermissionCollector));
        console2.log("OperatorRefundCollector:", address(operatorRefundCollector));

        // Log known addresses used
        // console2.log("\nKnown addresses used:");
        // console2.log("Multicall3:", MULTICALL3);
        // console2.log("Permit2:", PERMIT2);
        // console2.log("SpendPermissionManager:", SPEND_PERMISSION_MANAGER);

        //   Deployed addresses:
        //   AuthCaptureEscrow: 0xb43A5c066D92f063BaD7F6Be4260aBE522DDEf04
        //   ERC3009PaymentCollector: 0x2C52AbfdF0128f392a391a827a7588eff424AFD5
        //   Permit2PaymentCollector: 0xb63Ba5901cCb5F365AE51Eb14B7e7805E2A3096e
        //   PreApprovalPaymentCollector: 0x90Fe98605edA1dCd3F6D22F8bb202CfdbB537809
        //   SpendPermissionPaymentCollector: 0xC5DBF6B6160257466479F8414c53649aD363773c
        //   OperatorRefundCollector: 0x59805308e5BA80d388792Fa9374b0fD9CA511a19
    }
}
