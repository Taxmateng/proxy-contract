// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Errors {
    error CALLER_IS_NOT_A_SUPER_ADMIN();
    error CALLER_IS_NOT_A_SUB_ADMIN();
    error CALLER_IS_NOT_A_TAX_PAYER();
    error TIN_CAN_NOT_BE_EMPTY();
    error TAX_ITEM_DOES_NOT_EXIST();
    error TAX_ITEM_IS_NOT_ACTIVE();
    error INVALID_ROLE(bytes32 role);
    error TIN_ALREADY_EXISTS();
    error USER_EXISTS_ALREADY();
    error BUSINESS_EXISTS_ALREADY();
}