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
 * @notice Deploy the AuthCaptureEscrow contract and all collectors using CREATE2.
 *
 * forge script Deploy --account spmdeployer --sender $SPM_DEPLOYER --rpc-url $BASE_SEPOLIA_RPC --broadcast -vvvv --verify --verifier-url $SEPOLIA_BASESCAN_API --etherscan-api-key $BASESCAN_API_KEY
 * forge script Deploy --account spmdeployer --sender $SPM_DEPLOYER --rpc-url $BASE_RPC --broadcast -vvvv --verify --verifier-url $BASESCAN_API --etherscan-api-key $BASESCAN_API_KEY
 */
contract Deploy is Script {
    // Known addresses
    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant SPEND_PERMISSION_MANAGER = 0xf85210B21cC50302F477BA56686d2019dC9b67Ad;

    // Salt for CREATE2 deployments
    bytes32 constant DEPLOYMENT_SALT = bytes32(uint256(1));

    function run() public {
        vm.startBroadcast();

        // Deploy AuthCaptureEscrow with CREATE2
        AuthCaptureEscrow authCaptureEscrow = new AuthCaptureEscrow{salt: DEPLOYMENT_SALT}();

        // Deploy all collectors with CREATE2
        ERC3009PaymentCollector erc3009Collector =
            new ERC3009PaymentCollector{salt: DEPLOYMENT_SALT}(address(authCaptureEscrow), MULTICALL3);

        Permit2PaymentCollector permit2Collector =
            new Permit2PaymentCollector{salt: DEPLOYMENT_SALT}(address(authCaptureEscrow), PERMIT2, MULTICALL3);

        PreApprovalPaymentCollector preApprovalCollector =
            new PreApprovalPaymentCollector{salt: DEPLOYMENT_SALT}(address(authCaptureEscrow));

        SpendPermissionPaymentCollector spendPermissionCollector = new SpendPermissionPaymentCollector{
            salt: DEPLOYMENT_SALT
        }(address(authCaptureEscrow), SPEND_PERMISSION_MANAGER);

        OperatorRefundCollector operatorRefundCollector =
            new OperatorRefundCollector{salt: DEPLOYMENT_SALT}(address(authCaptureEscrow));

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

        //           AuthCaptureEscrow: 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff
        //   ERC3009PaymentCollector: 0x0E3dF9510de65469C4518D7843919c0b8C7A7757
        //   Permit2PaymentCollector: 0x992476B9Ee81d52a5BdA0622C333938D0Af0aB26
        //   PreApprovalPaymentCollector: 0x1b77ABd71FCD21fbe2398AE821Aa27D1E6B94bC6
        //   SpendPermissionPaymentCollector: 0x8d9F34934dc9619e5DC3Df27D0A40b4A744E7eAa
        //   OperatorRefundCollector: 0x934907bffd0901b6A21e398B9C53A4A38F02fa5d
    }
}
