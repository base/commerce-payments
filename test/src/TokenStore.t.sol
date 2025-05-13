// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {TokenStore} from "../../src/TokenStore.sol";
import {AuthCaptureEscrow} from "../../src/AuthCaptureEscrow.sol";

import {AuthCaptureEscrowBase} from "../base/AuthCaptureEscrowBase.sol";

contract TokenStoreTest is AuthCaptureEscrowBase {
    TokenStore public tokenStore;
    uint256 public constant INITIAL_BALANCE = 1000e18;

    function setUp() public override {
        super.setUp();
        tokenStore = new TokenStore(address(authCaptureEscrow));
        mockERC20Token.mint(address(tokenStore), INITIAL_BALANCE);
    }

    function test_constructor_setsAuthCaptureEscrow() public view {
        assertEq(
            tokenStore.authCaptureEscrow(), address(authCaptureEscrow), "AuthCaptureEscrow address not set correctly"
        );
    }

    function test_sendTokens_reverts_whenCalledByNonAuthCaptureEscrow(address nonAuthCaptureEscrow, uint256 amount)
        public
    {
        vm.assume(nonAuthCaptureEscrow != address(authCaptureEscrow));
        vm.assume(amount > 0 && amount <= INITIAL_BALANCE);

        vm.expectRevert(TokenStore.OnlyAuthCaptureEscrow.selector);
        vm.prank(nonAuthCaptureEscrow);
        tokenStore.sendTokens(address(mockERC20Token), receiver, amount);
    }

    function test_sendTokens_reverts_whenAmountExceedsBalance(uint256 amount) public {
        vm.assume(amount > INITIAL_BALANCE);

        vm.expectRevert();
        vm.prank(address(authCaptureEscrow));
        tokenStore.sendTokens(address(mockERC20Token), receiver, amount);
    }

    function test_sendTokens_succeeds_whenCalledByAuthCaptureEscrow(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        vm.assume(amount > 0 && amount <= INITIAL_BALANCE);

        uint256 initialRecipientBalance = mockERC20Token.balanceOf(recipient);

        vm.prank(address(authCaptureEscrow));
        bool success = tokenStore.sendTokens(address(mockERC20Token), recipient, amount);

        assertTrue(success, "sendTokens should return true");
        assertEq(
            mockERC20Token.balanceOf(recipient),
            initialRecipientBalance + amount,
            "Recipient balance should increase by amount"
        );
        assertEq(
            mockERC20Token.balanceOf(address(tokenStore)),
            INITIAL_BALANCE - amount,
            "TokenStore balance should decrease by amount"
        );
    }

    function test_sendTokens_succeeds_withZeroAmount() public {
        uint256 amount = 0;
        uint256 initialRecipientBalance = mockERC20Token.balanceOf(receiver);

        vm.prank(address(authCaptureEscrow));
        bool success = tokenStore.sendTokens(address(mockERC20Token), receiver, amount);

        assertTrue(success, "sendTokens should return true");
        assertEq(mockERC20Token.balanceOf(receiver), initialRecipientBalance, "Recipient balance should not change");
        assertEq(mockERC20Token.balanceOf(address(tokenStore)), INITIAL_BALANCE, "TokenStore balance should not change");
    }
}
