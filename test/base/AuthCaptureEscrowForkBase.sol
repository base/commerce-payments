// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {Test} from "forge-std/Test.sol";

import {AuthCaptureEscrow} from "../../src/AuthCaptureEscrow.sol";
import {IERC3009} from "../../src/interfaces/IERC3009.sol";
import {SpendPermissionPaymentCollector} from "../../src/collectors/SpendPermissionPaymentCollector.sol";
import {AuthCaptureEscrowSmartWalletBase} from "../base/AuthCaptureEscrowSmartWalletBase.sol";

contract AuthCaptureEscrowForkBase is AuthCaptureEscrowSmartWalletBase {
    // Base mainnet USDC address
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDC_WHALE = 0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A; // Binance
    uint256 public MAX_AMOUNT;

    address payable constant SPEND_PERMISSION_MANAGER = payable(0xf85210B21cC50302F477BA56686d2019dC9b67Ad);

    // Base mainnet RPC URL
    string internal BASE_RPC_URL = vm.envString("BASE_RPC_URL");

    // Contract instances
    IERC20 public usdc;

    function setUp() public virtual override {
        if (bytes(BASE_RPC_URL).length == 0) {
            revert(
                "BASE_RPC_URL is not set. To exclude integration tests from test run use `forge test --no-match-path [INTEGRATION_TEST_FILE]`"
            );
        }

        // Create a fork of Base mainnet
        vm.createSelectFork(BASE_RPC_URL);

        // Call parent setup to deploy contracts
        super.setUp();

        // Initialize USDC contract
        usdc = IERC20(BASE_USDC);

        vm.label(BASE_USDC, "USDC");

        MAX_AMOUNT = usdc.balanceOf(USDC_WHALE);

        // Override spend permission values to use deployed spend permission manager
        spendPermissionManager = SpendPermissionManager(SPEND_PERMISSION_MANAGER);
        spendPermissionPaymentCollector =
            new SpendPermissionPaymentCollector(address(authCaptureEscrow), address(spendPermissionManager));
        // Add deployed spend permission manager as owner of (deployed) smart wallet
        vm.prank(deployedWalletOwner);
        smartWalletDeployed.addOwnerAddress(address(spendPermissionManager));
    }

    // Helper function to fund an address with USDC
    function _fundWithUSDC(address recipient, uint256 amount) internal {
        // Impersonate the whale and transfer USDC
        vm.startPrank(USDC_WHALE);
        usdc.transfer(recipient, amount);
        vm.stopPrank();

        // Verify the transfer worked
        assertEq(usdc.balanceOf(recipient), amount, "USDC funding failed");
    }
}
