// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { Taxmate } from "../contracts/Taxmate.sol";
import { TaxCategory, Gender } from "../contracts/lib/TaxTypes.sol";
import { Errors } from "../contracts/lib/Errors.sol";
import { Events } from "../contracts/lib/Events.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GetterFunctionsTest is Test {
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
    uint256 constant AMOUNT_PAID = 1000000;
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

        // Setup test data
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
        taxmate.createTaxItem(VAT_NAME, VAT_DESCRIPTION, TaxCategory.VAT, 750);
        taxmate.createTaxItem(PAYE_NAME, PAYE_DESCRIPTION, TaxCategory.PAYE, 2500);
        taxmate.createTaxItem(WHT_NAME, WHT_DESCRIPTION, TaxCategory.WHT, 500);
        
        // Deactivate WHT item for testing mixed active/inactive
        taxmate.updateTaxItem(WHT_ITEM_ID, false);
        vm.stopPrank();

        // Record payments
        vm.startPrank(subAdmin);
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, VAT_ITEM_ID, 1000000, "REF1", "HASH1");
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, PAYE_ITEM_ID, 2000000, "REF2", "HASH2");
        taxmate.recordTaxPayment(taxPayer2, BUSINESS_TIN, VAT_ITEM_ID, 1500000, "REF3", "HASH3");
        vm.stopPrank();
    }

    // ========== PROFILE GETTER TESTS ==========

    function test_GetIndividualProfile_Success() public view {
        // Act
        Taxmate.IndividualProfile memory profile = taxmate.getIndividualProfile(taxPayer);

        // Assert
        assertEq(profile.walletAddress, taxPayer);
        assertEq(profile.tin, INDIVIDUAL_TIN);
        assertEq(profile.idNumber, "ID123456");
        assertEq(profile.idType, "BVN");
        assertEq(profile.email, "test@example.com");
        assertEq(profile.firstname, "John");
        assertEq(profile.lastname, "Doe");
        assertEq(profile.middlename, "Middle");
        assertEq(profile.dob, "1990-01-01");
        assertEq(uint(profile.gender), uint(Gender.MALE));
        assertTrue(profile.isActive);
        assertEq(profile.registrationDate, block.timestamp);
        assertEq(profile.lastPaymentDate, block.timestamp); // Updated by payments
    }

    function test_GetBusinessProfile_Success() public view{
        // Act
        Taxmate.BusinessProfile memory profile = taxmate.getBusinessProfile(taxPayer2);

        // Assert
        assertEq(profile.walletAddress, taxPayer2);
        assertEq(profile.tin, BUSINESS_TIN);
        assertEq(profile.rcNumber, "RC123456");
        assertEq(profile.companyName, "Test Company Ltd");
        assertEq(profile.companyType, "LLC");
        assertEq(profile.businessRegistrationDate, "2020-01-01");
        assertEq(profile.branchAddress, "123 Branch St");
        assertEq(profile.companyEmail, "company@test.com");
        assertEq(profile.city, "Lagos");
        assertEq(profile.classification, "Large Enterprise");
        assertEq(profile.headOfficeAddress, "456 HQ Avenue");
        assertEq(profile.lga, "Ikeja");
        assertEq(profile.affiliates, "Affiliate1, Affiliate2");
        assertEq(profile.shareCapital, "1000000");
        assertEq(profile.shareCapitalInWords, "One Million Naira");
        assertEq(profile.state, "Lagos State");
        assertTrue(profile.isActive);
        assertEq(profile.taxRegistrationDate, block.timestamp);
        assertEq(profile.lastPaymentDate, block.timestamp); // Updated by payments
    }

    function test_RevertWhen_GetIndividualProfile_NotFound() public {
        // Act & Assert
        address nonExistentUser = makeAddr("nonExistent");
        vm.expectRevert(abi.encodeWithSelector(Errors.INDIVIDUAL_PROFILE_NOT_FOUND.selector, nonExistentUser));
        taxmate.getIndividualProfile(nonExistentUser);
    }

    function test_RevertWhen_GetBusinessProfile_NotFound() public {
        // Act & Assert
        address nonExistentUser = makeAddr("nonExistent");
        vm.expectRevert(abi.encodeWithSelector(Errors.BUSINESS_PROFILE_NOT_FOUND.selector, nonExistentUser));
        taxmate.getBusinessProfile(nonExistentUser);
    }

    function test_RevertWhen_GetIndividualProfile_BusinessUser() public {
        // Act & Assert - Try to get individual profile for business user
        vm.expectRevert(abi.encodeWithSelector(Errors.INDIVIDUAL_PROFILE_NOT_FOUND.selector, taxPayer2));
        taxmate.getIndividualProfile(taxPayer2);
    }

    function test_RevertWhen_GetBusinessProfile_IndividualUser() public {
        // Act & Assert - Try to get business profile for individual user
        vm.expectRevert(abi.encodeWithSelector(Errors.BUSINESS_PROFILE_NOT_FOUND.selector, taxPayer));
        taxmate.getBusinessProfile(taxPayer);
    }

    // ========== TAX ITEM GETTER TESTS ==========

    function test_GetTaxItem_Success() public  view {
        // Act
        Taxmate.TaxItem memory item = taxmate.getTaxItem(VAT_ITEM_ID);

        // Assert
        assertEq(item.itemId, VAT_ITEM_ID);
        assertEq(item.name, VAT_NAME);
        assertEq(item.description, VAT_DESCRIPTION);
        assertEq(uint(item.category), uint(TaxCategory.VAT));
        assertEq(item.rate, 750);
        assertTrue(item.isActive);
        assertEq(item.createdAt, block.timestamp);
        assertEq(item.updatedAt, block.timestamp);
    }

    function test_GetTaxItem_Inactive() public view {
        // Act - Get inactive tax item
        Taxmate.TaxItem memory item = taxmate.getTaxItem(WHT_ITEM_ID);

        // Assert
        assertEq(item.itemId, WHT_ITEM_ID);
        assertEq(item.name, WHT_NAME);
        assertFalse(item.isActive);
    }

    function test_RevertWhen_GetTaxItem_NonExistent() public {
        // Act & Assert
        vm.expectRevert(Errors.TAX_ITEM_DOES_NOT_EXIST.selector);
        taxmate.getTaxItem(999);
    }

    function test_GetAllTaxItems_Counters() public view {
        // Act & Assert
        assertEq(taxmate.getTotalTaxItems(), 3);
    }

    // ========== PAYMENT GETTER TESTS ==========

    function test_GetPaymentRecord_Success() public view {
        // Act
        Taxmate.PaymentRecord memory payment = taxmate.getPaymentRecord(1);

        // Assert
        assertEq(payment.recordId, 1);
        assertEq(payment.payer, taxPayer);
        assertEq(payment.tin, INDIVIDUAL_TIN);
        assertEq(payment.itemId, VAT_ITEM_ID);
        assertEq(payment.amountPaid, 1000000);
        assertEq(payment.paymentRef, "REF1");
        assertEq(payment.receiptHash, "HASH1");
        assertEq(payment.timestamp, block.timestamp);
        assertEq(uint(payment.category), uint(TaxCategory.VAT));
    }

    function test_GetPaymentRecord_Multiple() public view {
        // Test getting different payment records
        Taxmate.PaymentRecord memory payment1 = taxmate.getPaymentRecord(1);
        assertEq(payment1.payer, taxPayer);
        assertEq(payment1.itemId, VAT_ITEM_ID);

        Taxmate.PaymentRecord memory payment2 = taxmate.getPaymentRecord(2);
        assertEq(payment2.payer, taxPayer);
        assertEq(payment2.itemId, PAYE_ITEM_ID);

        Taxmate.PaymentRecord memory payment3 = taxmate.getPaymentRecord(3);
        assertEq(payment3.payer, taxPayer2);
        assertEq(payment3.itemId, VAT_ITEM_ID);
    }

    function test_RevertWhen_GetPaymentRecord_NonExistent() public {
        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(Errors.PAYMENT_RECORD_NOT_FOUND.selector, 999));
        taxmate.getPaymentRecord(999);
    }

    function test_GetTotalPaymentRecords() public view{
        // Act & Assert
        assertEq(taxmate.getTotalPaymentRecords(), 3);
    }

    // ========== PAYMENT HISTORY TESTS ==========

    function test_GetTaxpayerPaymentHistory_Individual() public view{
        // Act
        uint256[] memory paymentHistory = taxmate.getTaxpayerPaymentHistory(taxPayer);

        // Assert
        assertEq(paymentHistory.length, 2);
        assertEq(paymentHistory[0], 1);
        assertEq(paymentHistory[1], 2);
    }

    function test_GetTaxpayerPaymentHistory_Business() public {
        // Act
        uint256[] memory paymentHistory = taxmate.getTaxpayerPaymentHistory(taxPayer2);

        // Assert
        assertEq(paymentHistory.length, 1);
        assertEq(paymentHistory[0], 3);
    }

    function test_GetTaxpayerPaymentHistory_Empty() public {
        // Act - User with no payments
        address newUser = makeAddr("newUser");
        taxmate.registerTaxpayer(
            newUser,
            "999999999",
            "ID999999",
            "NIN",
            "new@example.com",
            "New",
            "User",
            "",
            "1995-01-01",
            "female"
        );

        uint256[] memory paymentHistory = taxmate.getTaxpayerPaymentHistory(newUser);

        // Assert
        assertEq(paymentHistory.length, 0);
    }

    function test_GetTaxpayerPaymentHistory_UnregisteredUser() public {
        // Act - Unregistered user should return empty array, not revert
        address unregistered = makeAddr("unregistered");
        uint256[] memory paymentHistory = taxmate.getTaxpayerPaymentHistory(unregistered);

        // Assert
        assertEq(paymentHistory.length, 0);
    }

    // ========== ACTIVE TAX ITEMS TESTS ==========

    function test_GetActiveTaxItems_Success() public view {
        // Act
        Taxmate.TaxItem[] memory activeItems = taxmate.getActiveTaxItems();

        // Assert
        assertEq(activeItems.length, 2); // VAT and PAYE are active, WHT is inactive
        
        // Verify items are active and in correct order
        assertEq(activeItems[0].itemId, VAT_ITEM_ID);
        assertTrue(activeItems[0].isActive);
        assertEq(activeItems[1].itemId, PAYE_ITEM_ID);
        assertTrue(activeItems[1].isActive);
    }

    function test_GetActiveTaxItems_Empty() public {
        // Arrange - Deactivate all items
        vm.startPrank(subAdmin);
        taxmate.updateTaxItem(VAT_ITEM_ID, false);
        taxmate.updateTaxItem(PAYE_ITEM_ID, false);
        vm.stopPrank();

        // Act
        Taxmate.TaxItem[] memory activeItems = taxmate.getActiveTaxItems();

        // Assert
        assertEq(activeItems.length, 0);
    }

    function test_GetActiveTaxItems_AllActive() public {
        // Arrange - Reactivate WHT item
        vm.prank(subAdmin);
        taxmate.updateTaxItem(WHT_ITEM_ID, true);

        // Act
        Taxmate.TaxItem[] memory activeItems = taxmate.getActiveTaxItems();

        // Assert
        assertEq(activeItems.length, 3);
    }

    // ========== REGISTRATION STATUS TESTS ==========

    function test_IsRegisteredTaxpayer_Individual() public {
        // Act & Assert
        assertTrue(taxmate.isRegisteredTaxpayer(taxPayer));
    }

    function test_IsRegisteredTaxpayer_Business() public {
        // Act & Assert
        assertTrue(taxmate.isRegisteredTaxpayer(taxPayer2));
    }

    function test_IsRegisteredTaxpayer_NotRegistered() public {
        // Act & Assert
        address unregistered = makeAddr("unregistered");
        assertFalse(taxmate.isRegisteredTaxpayer(unregistered));
    }

    function test_IsRegisteredTaxpayer_ZeroAddress() public {
        // Act & Assert
        assertFalse(taxmate.isRegisteredTaxpayer(ZERO_ADDRESS));
    }

    // ========== PROFILE TYPE TESTS ==========

    function test_GetProfileType_Individual() public {
        // Act & Assert
        assertEq(taxmate.getProfileType(taxPayer), "individual");
    }

    function test_GetProfileType_Business() public {
        // Act & Assert
        assertEq(taxmate.getProfileType(taxPayer2), "business");
    }

    function test_GetProfileType_None() public {
        // Act & Assert
        address unregistered = makeAddr("unregistered");
        assertEq(taxmate.getProfileType(unregistered), "none");
    }

    function test_GetProfileType_ZeroAddress() public {
        // Act & Assert
        assertEq(taxmate.getProfileType(ZERO_ADDRESS), "none");
    }

    // ========== TIN MAPPING TESTS ==========

    function test_TinToAddress_Mapping() public {
        // Act & Assert
        assertEq(taxmate.tinToAddress(INDIVIDUAL_TIN), taxPayer);
        assertEq(taxmate.tinToAddress(BUSINESS_TIN), taxPayer2);
    }

    function test_TinToAddress_NonExistent() public {
        // Act & Assert
        assertEq(taxmate.tinToAddress("000000000"), ZERO_ADDRESS);
    }

    function test_AddressToTin_Mapping() public {
        // Act & Assert
        assertEq(taxmate.addressToTin(taxPayer), INDIVIDUAL_TIN);
        assertEq(taxmate.addressToTin(taxPayer2), BUSINESS_TIN);
    }

    function test_AddressToTin_NonExistent() public {
        // Act & Assert
        address unregistered = makeAddr("unregistered");
        assertEq(taxmate.addressToTin(unregistered), "");
    }

    // ========== UTILITY FUNCTION TESTS ==========

    function test_BasisPointsToPercentage() public {
        // Test various conversions
        assertEq(taxmate.basisPointsToPercentage(100), 1); // 1%
        assertEq(taxmate.basisPointsToPercentage(750), 7); // 7.5% -> 7 (integer division)
        assertEq(taxmate.basisPointsToPercentage(2500), 25); // 25%
        assertEq(taxmate.basisPointsToPercentage(0), 0); // 0%
        assertEq(taxmate.basisPointsToPercentage(10000), 100); // 100%
        assertEq(taxmate.basisPointsToPercentage(125), 1); // 1.25% -> 1
    }

    function test_CalculateTaxAmount() public {
        // Test tax calculations
        assertEq(taxmate.calculateTaxAmount(1000, 100), 10); // 1% of 1000 = 10
        assertEq(taxmate.calculateTaxAmount(1000, 750), 75); // 7.5% of 1000 = 75
        assertEq(taxmate.calculateTaxAmount(1000, 2500), 250); // 25% of 1000 = 250
        assertEq(taxmate.calculateTaxAmount(1000, 0), 0); // 0% of 1000 = 0
        assertEq(taxmate.calculateTaxAmount(1000, 10000), 1000); // 100% of 1000 = 1000
    }

    function test_CalculateTaxAmount_LargeNumbers() public {
        // Test with large numbers
        assertEq(taxmate.calculateTaxAmount(1_000_000, 750), 75000); // 7.5% of 1,000,000 = 75,000
        assertEq(taxmate.calculateTaxAmount(10_000_000, 2500), 2_500_000); // 25% of 10,000,000 = 2,500,000
    }

    function test_CalculateTaxAmount_Rounding() public {
        // Test rounding behavior (integer division truncates)
        assertEq(taxmate.calculateTaxAmount(100, 125), 1); // 1.25% of 100 = 1.25 -> 1
        assertEq(taxmate.calculateTaxAmount(1000, 333), 33); // 3.33% of 1000 = 33.3 -> 33
        assertEq(taxmate.calculateTaxAmount(999, 100), 9); // 1% of 999 = 9.99 -> 9
    }

    // ========== ACCESS CONTROL TESTS ==========

    function test_Getters_AccessibleByAnyone() public {
        // All getter functions should be accessible by anyone, including attackers
        // Test individual profile getter
        Taxmate.IndividualProfile memory individualProfile = taxmate.getIndividualProfile(taxPayer);
        assertEq(individualProfile.firstname, "John");

        // Test business profile getter
        Taxmate.BusinessProfile memory businessProfile = taxmate.getBusinessProfile(taxPayer2);
        assertEq(businessProfile.companyName, "Test Company Ltd");

        // Test tax item getter
        Taxmate.TaxItem memory taxItem = taxmate.getTaxItem(VAT_ITEM_ID);
        assertEq(taxItem.name, VAT_NAME);

        // Test payment record getter
        Taxmate.PaymentRecord memory payment = taxmate.getPaymentRecord(1);
        assertEq(payment.amountPaid, 1000000);

        // Test payment history
        uint256[] memory history = taxmate.getTaxpayerPaymentHistory(taxPayer);
        assertEq(history.length, 2);

        // Test active tax items
        Taxmate.TaxItem[] memory activeItems = taxmate.getActiveTaxItems();
        assertEq(activeItems.length, 2);

        // Test registration status
        assertTrue(taxmate.isRegisteredTaxpayer(taxPayer));

        // Test counters
        assertEq(taxmate.getTotalTaxItems(), 3);
        assertEq(taxmate.getTotalPaymentRecords(), 3);

        // Test profile type
        assertEq(taxmate.getProfileType(taxPayer), "individual");

        // Test utility functions
        assertEq(taxmate.basisPointsToPercentage(750), 7);
        assertEq(taxmate.calculateTaxAmount(1000, 750), 75);
    }

    // ========== EDGE CASE TESTS ==========

    function test_GetProfileType_AfterProfileDeletion() public {
        // This test ensures profile type returns "none" for addresses that were never registered
        address neverRegistered = makeAddr("neverRegistered");
        assertEq(taxmate.getProfileType(neverRegistered), "none");
    }

    function test_GetPaymentHistory_AfterMultipleOperations() public {
        // Record more payments
        vm.startPrank(subAdmin);
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, VAT_ITEM_ID, 500000, "REF4", "HASH4");
        taxmate.recordTaxPayment(taxPayer, INDIVIDUAL_TIN, PAYE_ITEM_ID, 750000, "REF5", "HASH5");
        vm.stopPrank();

        // Verify payment history is updated
        uint256[] memory history = taxmate.getTaxpayerPaymentHistory(taxPayer);
        assertEq(history.length, 4);
        assertEq(history[0], 1);
        assertEq(history[1], 2);
        assertEq(history[2], 4);
        assertEq(history[3], 5);
    }

    function test_GetActiveTaxItems_AfterMultipleUpdates() public {
        // Toggle tax item status multiple times
        vm.startPrank(subAdmin);
        taxmate.updateTaxItem(VAT_ITEM_ID, false);
        taxmate.updateTaxItem(VAT_ITEM_ID, true);
        taxmate.updateTaxItem(PAYE_ITEM_ID, false);
        vm.stopPrank();

        // Verify only active items are returned
        Taxmate.TaxItem[] memory activeItems = taxmate.getActiveTaxItems();
        assertEq(activeItems.length, 1); // VAT and WHT (if WHT was reactivated)
        assertEq(activeItems[0].itemId, VAT_ITEM_ID);
        assertTrue(activeItems[0].isActive);
    }

    // ========== GAS AND PERFORMANCE TESTS ==========

    function test_Gas_GetIndividualProfile() public view{
        // Test gas consumption for profile getter
        uint256 gasBefore = gasleft();
        taxmate.getIndividualProfile(taxPayer);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for getIndividualProfile: %s", gasUsed);
        assertLt(gasUsed, 100000, "Gas usage should be reasonable");
    }

    function test_Gas_GetActiveTaxItems() public {
        // Test gas consumption for active tax items getter
        uint256 gasBefore = gasleft();
        taxmate.getActiveTaxItems();
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for getActiveTaxItems: %s", gasUsed);
        assertLt(gasUsed, 200000, "Gas usage should be reasonable");
    }

    function test_Gas_GetTaxpayerPaymentHistory() public {
        // Test gas consumption for payment history getter
        uint256 gasBefore = gasleft();
        taxmate.getTaxpayerPaymentHistory(taxPayer);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for getTaxpayerPaymentHistory: %s", gasUsed);
        assertLt(gasUsed, 100000, "Gas usage should be reasonable");
    }
}