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
    error INVALID_GENDER();
    error INITIALIZER_CAN_NOT_BE_ADDRESS_ZERO();
    error TIN_AND_ADDRESS_MISMATCH(string tin);
    error AMOUNT_MUST_BE_GREATER_THAN_ZERO(uint256 amount);
    error PAYMENT_REFERENCE_REQUIRED();
    error RECEIPT_HASH_REQUIRED();
    error INDIVIDUAL_PROFILE_NOT_FOUND(address user);
    error BUSINESS_PROFILE_NOT_FOUND(address user);
    error PAYMENT_RECORD_NOT_FOUND(uint256 id);
    error CANNOT_REGISTER_ADDRESS_ZERO();
    error TAX_ITEM_NAME_CANNOT_BE_EMPTY();
    error TAX_ITEM_DESCRIPTION_CANNOT_BE_EMPTY();
}