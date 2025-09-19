// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TaxCategory} from "../Taxmate.sol";

library Events {
        event UserRegistered(address indexed user, string tin, uint256 timestamp);
    event TaxItemCreated(uint256 indexed itemId, string name, TaxCategory category, uint256 rate);
    event TaxItemUpdated(uint256 indexed itemId, bool isActive, uint256 updatedAt);
    event TaxPaid(
        uint256 indexed recordId,
        address indexed payer,
        string tin,
        uint256 itemId,
        uint256 amountPaid,
        string paymentRef,
        string receiptHash,
        uint256 timestamp
    );
    event AdminAdded(address indexed admin, bytes32 role);
    event AdminRemoved(address indexed admin, bytes32 role);
}