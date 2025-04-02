// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {OperatorFactory} from "../src/operator/OperatorFactory.sol";

/**
 * forge script DeployOperator --account dev --sender $SENDER --rpc-url $BASE_SEPOLIA_RPC --broadcast -vvvv
 * --verify --verifier-url $SEPOLIA_BASESCAN_API --etherscan-api-key $BASESCAN_API_KEY
 */
contract DeployOperator is Script {
    function run() public {
        vm.startBroadcast();

        OperatorFactory operatorFactory = new OperatorFactory();

        vm.stopBroadcast();

        // Log deployed addresses
        console2.log("Deployed addresses:");
        console2.log("OperatorFactory:", address(operatorFactory));
    }
}
