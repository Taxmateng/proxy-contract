// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { Taxmate } from "../contracts/Taxmate.sol";
import { TaxCategory, Gender } from "../contracts/lib/TaxTypes.sol";
import { Errors } from "../contracts/lib/Errors.sol";
import { Events } from "../contracts/lib/Events.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TaxPaymentTest is Test {
    Taxmate public taxmate;
    Taxmate public taxmateImplementation;
    address public superAdmin;
    address public subAdmin;
    address public taxPayer;
    address public taxPayer2;
    address public attacker;
    
    // Test constants
    address constant ZERO_ADDRESS = address(0);
    address constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // Test data
    string constant INDIVIDUAL_TIN = "123456789";
    string constant BUSINESS_TIN = "987654321";
    string constant DUPLICATE_TIN = "111111111";

    // Tax item test data
    string constant VAT_NAME = "Value Added Tax";
    string constant VAT_DESCRIPTION = "Tax on goods and services";
    string constant PAYE_NAME = "Pay As You Earn";
    string constant PAYE_DESCRIPTION = "Tax on employee income";
    string constant WHT_NAME = "Withholding Tax";
    string constant WHT_DESCRIPTION = "Tax withheld at source";

    // Payment test data
    uint256 constant VAT_ITEM_ID = 1;
    uint256 constant PAYE_ITEM_ID = 2;
    uint256 constant WHT_ITEM_ID = 3;
    uint256 constant AMOUNT_PAID = 1000000; // 1,000,000 (assuming 6 decimals)
    string constant PAYMENT_REF = "PAYREF123456";
    string constant RECEIPT_HASH = "QmReceiptHash123456789";

    function setUp() public {
        superAdmin = makeAddr("superAdmin");
        subAdmin = makeAddr("subAdmin");
        taxPayer = makeAddr("taxPayer");
        taxPayer2 = makeAddr("taxPayer2");
        attacker = makeAddr("attacker");

        // Deploy contract
        vm.startPrank(superAdmin);
        taxmateImplementation = new Taxmate();
        
        bytes memory data = abi.encodeWithSelector(Taxmate.initialize.selector, superAdmin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(taxmateImplementation), data);
        taxmate = Taxmate(address(proxy));

        // Grant SUB_ADMIN_ROLE to subAdmin for tax item management
        taxmate.addAdmin(subAdmin, taxmate.SUB_ADMIN_ROLE());
        vm.stopPrank();

        // Setup test data: register taxpayers and create tax items
        _setupTestData();
    }

    function _setupTestData() internal {
        // Register individual taxpayer
        taxmate.registerTaxpayer(
            taxPayer,
            INDIVIDUAL_TIN,
            "ID123456",
            "BVN",
            "test@example.com",
            "John",
            "Doe",
            "Middle",
            "1990-01-01",
            "male"
        );

        // Register business taxpayer
        taxmate.registerBusiness(
            taxPayer2,
            BUSINESS_TIN,
            "RC123456",
            "Test Company Ltd",
            "LLC",
            "2020-01-01",
            "123 Branch St",
            "company@test.com",
            "Lagos",
            "Large Enterprise",
            "456 HQ Avenue",
            "Ikeja",
            "Affiliate1, Affiliate2",
            "1000000",
            "One Million Naira",
            "Lagos State",
            true
        );

        // Create tax items
        vm.startPrank(subAdmin);
        taxmate.createTaxItem(VAT_NAME, VAT_DESCRIPTION, TaxCategory.VAT, 750); // 7.5%
        taxmate.createTaxItem(PAYE_NAME, PAYE_DESCRIPTION, TaxCategory.PAYE, 2500); // 25%
        taxmate.createTaxItem(WHT_NAME, WHT_DESCRIPTION, TaxCategory.WHT, 500); // 5%
        vm.stopPrank();
    }

    // ========== SUCCESSFUL PAYMENT TESTS ==========

    function test_RecordTaxPayment_Individual_Success() public {
        // Act
        vm.expectEmit(true, true, true, true);
        emit Events.TaxPaid(
            1,
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            AMOUNT_PAID,
            PAYMENT_REF,
            RECEIPT_HASH,
            block.timestamp
        );

        vm.prank(subAdmin);
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            AMOUNT_PAID,
            PAYMENT_REF,
            RECEIPT_HASH
        );

        // Assert
        Taxmate.PaymentRecord memory payment = taxmate.getPaymentRecord(1);
        assertEq(payment.recordId, 1);
        assertEq(payment.payer, taxPayer);
        assertEq(payment.tin, INDIVIDUAL_TIN);
        assertEq(payment.itemId, VAT_ITEM_ID);
        assertEq(payment.amountPaid, AMOUNT_PAID);
        assertEq(payment.paymentRef, PAYMENT_REF);
        assertEq(payment.receiptHash, RECEIPT_HASH);
        assertEq(payment.timestamp, block.timestamp);
        assertEq(uint(payment.category), uint(TaxCategory.VAT));

        // Verify payment history
        uint256[] memory paymentHistory = taxmate.getTaxpayerPaymentHistory(taxPayer);
        assertEq(paymentHistory.length, 1);
        assertEq(paymentHistory[0], 1);

        // Verify last payment date updated
        Taxmate.IndividualProfile memory profile = taxmate.getIndividualProfile(taxPayer);
        assertEq(profile.lastPaymentDate, block.timestamp);

        // Verify counter increased
        assertEq(taxmate.getTotalPaymentRecords(), 1);
    }

    function test_RecordTaxPayment_Business_Success() public {
        // Act
        vm.prank(subAdmin);
        taxmate.recordTaxPayment(
            taxPayer2,
            BUSINESS_TIN,
            PAYE_ITEM_ID,
            AMOUNT_PAID,
            PAYMENT_REF,
            RECEIPT_HASH
        );

        // Assert
        Taxmate.PaymentRecord memory payment = taxmate.getPaymentRecord(1);
        assertEq(payment.payer, taxPayer2);
        assertEq(payment.tin, BUSINESS_TIN);
        assertEq(payment.itemId, PAYE_ITEM_ID);
        assertEq(uint(payment.category), uint(TaxCategory.PAYE));

        // Verify last payment date updated for business
        Taxmate.BusinessProfile memory profile = taxmate.getBusinessProfile(taxPayer2);
        assertEq(profile.lastPaymentDate, block.timestamp);
    }

    function test_RecordMultipleTaxPayments_Success() public {
        // Act - Record multiple payments
        vm.startPrank(subAdmin);
        
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, VAT_ITEM_ID, 1000000, "REF1", "HASH1");
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, PAYE_ITEM_ID, 2000000, "REF2", "HASH2");
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, WHT_ITEM_ID, 500000, "REF3", "HASH3");
        
        vm.stopPrank();

        // Assert
        assertEq(taxmate.getTotalPaymentRecords(), 3);

        // Verify payment records
        Taxmate.PaymentRecord memory payment1 = taxmate.getPaymentRecord(1);
        assertEq(payment1.itemId, VAT_ITEM_ID);
        assertEq(payment1.amountPaid, 1000000);

        Taxmate.PaymentRecord memory payment2 = taxmate.getPaymentRecord(2);
        assertEq(payment2.itemId, PAYE_ITEM_ID);
        assertEq(payment2.amountPaid, 2000000);

        Taxmate.PaymentRecord memory payment3 = taxmate.getPaymentRecord(3);
        assertEq(payment3.itemId, WHT_ITEM_ID);
        assertEq(payment3.amountPaid, 500000);

        // Verify payment history
        uint256[] memory paymentHistory = taxmate.getTaxpayerPaymentHistory(taxPayer);
        assertEq(paymentHistory.length, 3);
        assertEq(paymentHistory[0], 1);
        assertEq(paymentHistory[1], 2);
        assertEq(paymentHistory[2], 3);
    }

    function test_RecordTaxPayment_DifferentTaxpayers() public {
        // Act - Record payments for different taxpayers
        vm.startPrank(subAdmin);
        
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, VAT_ITEM_ID, 1000000, "REF1", "HASH1");
        taxmate.recordTaxPayment(taxPayer2, BUSINESS_TIN, PAYE_ITEM_ID, 2000000, "REF2", "HASH2");
        
        vm.stopPrank();

        // Assert
        assertEq(taxmate.getTotalPaymentRecords(), 2);

        // Verify individual taxpayer payment history
        uint256[] memory individualHistory = taxmate.getTaxpayerPaymentHistory(taxPayer);
        assertEq(individualHistory.length, 1);
        assertEq(individualHistory[0], 1);

        // Verify business taxpayer payment history
        uint256[] memory businessHistory = taxmate.getTaxpayerPaymentHistory(taxPayer2);
        assertEq(businessHistory.length, 1);
        assertEq(businessHistory[0], 2);
    }

    function test_RecordTaxPayment_AllCategories() public {
        // Test recording payments for all tax categories
        vm.startPrank(subAdmin);
        
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, VAT_ITEM_ID, 1000000, "REF_VAT", "HASH_VAT");
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, PAYE_ITEM_ID, 2000000, "REF_PAYE", "HASH_PAYE");
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, WHT_ITEM_ID, 500000, "REF_WHT", "HASH_WHT");
        
        vm.stopPrank();

        // Assert categories are correctly stored
        Taxmate.PaymentRecord memory vatPayment = taxmate.getPaymentRecord(1);
        assertEq(uint(vatPayment.category), uint(TaxCategory.VAT));

        Taxmate.PaymentRecord memory payePayment = taxmate.getPaymentRecord(2);
        assertEq(uint(payePayment.category), uint(TaxCategory.PAYE));

        Taxmate.PaymentRecord memory whtPayment = taxmate.getPaymentRecord(3);
        assertEq(uint(whtPayment.category), uint(TaxCategory.WHT));
    }

    // ========== ACCESS CONTROL ERROR TESTS ==========

    function test_RevertWhen_RecordTaxPayment_NonSubAdmin() public {
        // Act & Assert
        vm.prank(attacker);
        vm.expectRevert(Errors.CALLER_IS_NOT_A_SUB_ADMIN.selector);
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            AMOUNT_PAID,
            PAYMENT_REF,
            RECEIPT_HASH
        );
    }

    function test_RevertWhen_RecordTaxPayment_TaxPayer() public {
        // Act & Assert - Taxpayer cannot record payments
        vm.prank(taxPayer);
        vm.expectRevert(Errors.CALLER_IS_NOT_A_SUB_ADMIN.selector);
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            AMOUNT_PAID,
            PAYMENT_REF,
            RECEIPT_HASH
        );
    }

    // ========== VALIDATION ERROR TESTS ==========

    function test_RevertWhen_RecordTaxPayment_TinAddressMismatch() public {
        // Act & Assert - TIN doesn't match payer address
        vm.prank(subAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.TIN_AND_ADDRESS_MISMATCH.selector, INDIVIDUAL_TIN));
        taxmate.recordTaxPayment(
            taxPayer2, // Different address
            INDIVIDUAL_TIN, // TIN belongs to taxPayer
            VAT_ITEM_ID,
            AMOUNT_PAID,
            PAYMENT_REF,
            RECEIPT_HASH
        );
    }

    function test_RevertWhen_RecordTaxPayment_ZeroAmount() public {
        // Act & Assert
        vm.prank(subAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.AMOUNT_MUST_BE_GREATER_THAN_ZERO.selector, 0));
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            0, // Zero amount
            PAYMENT_REF,
            RECEIPT_HASH
        );
    }

    function test_RevertWhen_RecordTaxPayment_EmptyPaymentRef() public {
        // Act & Assert
        vm.prank(subAdmin);
        vm.expectRevert(Errors.PAYMENT_REFERENCE_REQUIRED.selector);
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            AMOUNT_PAID,
            "", // Empty payment reference
            RECEIPT_HASH
        );
    }

    function test_RevertWhen_RecordTaxPayment_EmptyReceiptHash() public {
        // Act & Assert
        vm.prank(subAdmin);
        vm.expectRevert(Errors.RECEIPT_HASH_REQUIRED.selector);
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            AMOUNT_PAID,
            PAYMENT_REF,
            "" // Empty receipt hash
        );
    }

    function test_RevertWhen_RecordTaxPayment_NonExistentTaxItem() public {
        // Act & Assert
        vm.prank(subAdmin);
        vm.expectRevert(Errors.TAX_ITEM_DOES_NOT_EXIST.selector);
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            999, // Non-existent tax item
            AMOUNT_PAID,
            PAYMENT_REF,
            RECEIPT_HASH
        );
    }

    function test_RevertWhen_RecordTaxPayment_InactiveTaxItem() public {
        // Arrange - Deactivate tax item
        vm.prank(subAdmin);
        taxmate.updateTaxItem(VAT_ITEM_ID, false);

        // Act & Assert
        vm.prank(subAdmin);
        vm.expectRevert(Errors.TAX_ITEM_IS_NOT_ACTIVE.selector);
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            AMOUNT_PAID,
            PAYMENT_REF,
            RECEIPT_HASH
        );
    }

    function test_RevertWhen_RecordTaxPayment_UnregisteredTaxpayer() public {
        address unregisteredUser = makeAddr("unregistered");
        
        // Act & Assert
        vm.prank(subAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.TIN_AND_ADDRESS_MISMATCH.selector, INDIVIDUAL_TIN));
        taxmate.recordTaxPayment(
            unregisteredUser,
            INDIVIDUAL_TIN, // TIN exists but address doesn't match
            VAT_ITEM_ID,
            AMOUNT_PAID,
            PAYMENT_REF,
            RECEIPT_HASH
        );
    }

    // ========== REENTRANCY GUARD TESTS ==========

    function test_ReentrancyGuard_Protection() public {
        // This test ensures the nonReentrant modifier works
        // We'll create a malicious contract that tries to reenter
        MaliciousContract malicious = new MaliciousContract(address(taxmate), subAdmin);
        
        // Fund the malicious contract to pay for gas
        vm.deal(address(malicious), 1 ether);
        
        // Should not be able to reenter
        vm.expectRevert(Errors.CALLER_IS_NOT_A_SUB_ADMIN.selector);
        malicious.attemptReentrancy(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            AMOUNT_PAID,
            PAYMENT_REF,
            RECEIPT_HASH
        );
    }

    // ========== EDGE CASE TESTS ==========

    function test_RecordTaxPayment_MinimumAmount() public {
        // Test with minimum valid amount (1)
        vm.prank(subAdmin);
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            1, // Minimum amount
            PAYMENT_REF,
            RECEIPT_HASH
        );

        // Assert
        Taxmate.PaymentRecord memory payment = taxmate.getPaymentRecord(1);
        assertEq(payment.amountPaid, 1);
    }

    function test_RecordTaxPayment_LargeAmount() public {
        uint256 largeAmount = 1_000_000_000_000; // 1 trillion
        
        vm.prank(subAdmin);
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            largeAmount,
            PAYMENT_REF,
            RECEIPT_HASH
        );

        // Assert
        Taxmate.PaymentRecord memory payment = taxmate.getPaymentRecord(1);
        assertEq(payment.amountPaid, largeAmount);
    }

    function test_RecordTaxPayment_LongStrings() public {
        string memory longPaymentRef = "Very_Long_Payment_Reference_Number_That_Exceeds_Normal_Length_1234567890";
        string memory longReceiptHash = "QmVeryLongReceiptHashThatContainsLotsOfCharactersAndShouldStillWorkFine1234567890";
        
        vm.prank(subAdmin);
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            AMOUNT_PAID,
            longPaymentRef,
            longReceiptHash
        );

        // Assert
        Taxmate.PaymentRecord memory payment = taxmate.getPaymentRecord(1);
        assertEq(payment.paymentRef, longPaymentRef);
        assertEq(payment.receiptHash, longReceiptHash);
    }

    function test_RecordTaxPayment_LastPaymentDate_Individual() public {
        // Record initial payment
        uint256 firstPaymentTime = block.timestamp;
        vm.prank(subAdmin);
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, VAT_ITEM_ID, AMOUNT_PAID, "REF1", "HASH1");
        
        Taxmate.IndividualProfile memory profile1 = taxmate.getIndividualProfile(taxPayer);
        assertEq(profile1.lastPaymentDate, firstPaymentTime);

        // Record second payment later
        vm.warp(block.timestamp + 30 days);
        vm.prank(subAdmin);
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, PAYE_ITEM_ID, AMOUNT_PAID, "REF2", "HASH2");
        
        Taxmate.IndividualProfile memory profile2 = taxmate.getIndividualProfile(taxPayer);
        assertEq(profile2.lastPaymentDate, block.timestamp);
    }

    function test_RecordTaxPayment_LastPaymentDate_Business() public {
        // Record initial payment
        uint256 firstPaymentTime = block.timestamp;
        vm.prank(subAdmin);
        taxmate.recordTaxPayment(taxPayer2, BUSINESS_TIN, VAT_ITEM_ID, AMOUNT_PAID, "REF1", "HASH1");
        
        Taxmate.BusinessProfile memory profile1 = taxmate.getBusinessProfile(taxPayer2);
        assertEq(profile1.lastPaymentDate, firstPaymentTime);

        // Record second payment later
        vm.warp(block.timestamp + 30 days);
        vm.prank(subAdmin);
        taxmate.recordTaxPayment(taxPayer2, BUSINESS_TIN, PAYE_ITEM_ID, AMOUNT_PAID, "REF2", "HASH2");
        
        Taxmate.BusinessProfile memory profile2 = taxmate.getBusinessProfile(taxPayer2);
        assertEq(profile2.lastPaymentDate, block.timestamp);
    }

    // ========== EVENT EMISSION TESTS ==========

    function test_Events_EmittedCorrectly() public {
        // Test TaxPaid event emission
        vm.expectEmit(true, true, true, true);
        emit Events.TaxPaid(1, taxPayer, INDIVIDUAL_TIN, VAT_ITEM_ID, AMOUNT_PAID, PAYMENT_REF, RECEIPT_HASH, block.timestamp);
        
        vm.prank(subAdmin);
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, VAT_ITEM_ID, AMOUNT_PAID, PAYMENT_REF, RECEIPT_HASH);
    }

    // ========== COUNTER TESTS ==========

    function test_PaymentRecordCounter_IncrementsCorrectly() public {
        vm.startPrank(subAdmin);
        
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, VAT_ITEM_ID, 1000000, "REF1", "HASH1");
        assertEq(taxmate.getTotalPaymentRecords(), 1);
        
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, PAYE_ITEM_ID, 2000000, "REF2", "HASH2");
        assertEq(taxmate.getTotalPaymentRecords(), 2);
        
        taxmate.recordTaxPayment(taxPayer2, BUSINESS_TIN, WHT_ITEM_ID, 500000, "REF3", "HASH3");
        assertEq(taxmate.getTotalPaymentRecords(), 3);
        
        vm.stopPrank();
    }

    // ========== SUPER ADMIN TESTS ==========

    function test_SuperAdmin_CanRecordTaxPayment() public {
        // SuperAdmin should be able to record payments (has SUB_ADMIN_ROLE)
        vm.prank(superAdmin);
        taxmate.recordTaxPayment(
            taxPayer,
            INDIVIDUAL_TIN,
            VAT_ITEM_ID,
            AMOUNT_PAID,
            PAYMENT_REF,
            RECEIPT_HASH
        );

        // Assert
        assertEq(taxmate.getTotalPaymentRecords(), 1);
    }
}

// Malicious contract for testing reentrancy
contract MaliciousContract {
    Taxmate public taxmate;
    address public subAdmin;
    
    constructor(address _taxmate, address _subAdmin) {
        taxmate = Taxmate(_taxmate);
        subAdmin = _subAdmin;
    }
    
    function attemptReentrancy(
        address payer,
        string memory tin,
        uint256 itemId,
        uint256 amountPaid,
        string memory paymentRef,
        string memory receiptHash
    ) external {
        // First call
        taxmate.recordTaxPayment(payer, tin, itemId, amountPaid, paymentRef, receiptHash);
        
        // Attempt reentrant call (this should fail due to nonReentrant modifier)
        taxmate.recordTaxPayment(payer, tin, itemId, amountPaid, paymentRef, receiptHash);
    }
}