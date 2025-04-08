// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../../base/PaymentEscrowBase.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract ChargeWithSpendPermissionWithMagicSpendTest is PaymentEscrowBase {}
