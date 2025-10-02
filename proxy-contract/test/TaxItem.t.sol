// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { Taxmate } from "../contracts/Taxmate.sol";
import { TaxCategory, Gender } from "../contracts/lib/TaxTypes.sol";
import { Errors } from "../contracts/lib/Errors.sol";
import { Events } from "../contracts/lib/Events.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TaxItemTest is Test {
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
    }

    // ========== SUCCESSFUL TAX ITEM CREATION TESTS ==========

    function test_CreateTaxItem_Success() public {
        // Act
        vm.expectEmit(true, true, true, true);
        emit Events.TaxItemCreated(1, VAT_NAME, TaxCategory.VAT, 750);

        vm.prank(subAdmin);
        taxmate.createTaxItem(
            VAT_NAME,
            VAT_DESCRIPTION,
            TaxCategory.VAT,
            750 // 7.5%
        );

        // Assert
        Taxmate.TaxItem memory item = taxmate.getTaxItem(1);
        assertEq(item.itemId, 1);
        assertEq(item.name, VAT_NAME);
        assertEq(item.description, VAT_DESCRIPTION);
        assertEq(uint(item.category), uint(TaxCategory.VAT));
        assertEq(item.rate, 750);
        assertTrue(item.isActive);
        assertEq(item.createdAt, block.timestamp);
        assertEq(item.updatedAt, block.timestamp);

        // Verify counter increased
        assertEq(taxmate.getTotalTaxItems(), 1);
    }

    function test_CreateMultipleTaxItems_Success() public {
        // Act - Create multiple tax items
        vm.startPrank(subAdmin);
        
        taxmate.createTaxItem(
            VAT_NAME,
            VAT_DESCRIPTION,
            TaxCategory.VAT,
            750
        );

        taxmate.createTaxItem(
            PAYE_NAME,
            PAYE_DESCRIPTION,
            TaxCategory.PAYE,
            2500 // 25%
        );

        taxmate.createTaxItem(
            WHT_NAME,
            WHT_DESCRIPTION,
            TaxCategory.WHT,
            500 // 5%
        );

        vm.stopPrank();

        // Assert
        assertEq(taxmate.getTotalTaxItems(), 3);

        // Verify each item
        Taxmate.TaxItem memory vatItem = taxmate.getTaxItem(1);
        assertEq(vatItem.name, VAT_NAME);
        assertEq(vatItem.rate, 750);

        Taxmate.TaxItem memory payeItem = taxmate.getTaxItem(2);
        assertEq(payeItem.name, PAYE_NAME);
        assertEq(payeItem.rate, 2500);

        Taxmate.TaxItem memory whtItem = taxmate.getTaxItem(3);
        assertEq(whtItem.name, WHT_NAME);
        assertEq(whtItem.rate, 500);
    }

    function test_CreateTaxItem_AllCategories() public {
        // Test creating tax items for all available categories
        vm.startPrank(subAdmin);

        taxmate.createTaxItem("VAT", "Value Added Tax", TaxCategory.VAT, 750);
        taxmate.createTaxItem("PAYE", "Pay As You Earn", TaxCategory.PAYE, 2500);
        taxmate.createTaxItem("WHT", "Withholding Tax", TaxCategory.WHT, 500);
        taxmate.createTaxItem("Income Tax", "Personal Income Tax", TaxCategory.INCOME_TAX, 2000);
        taxmate.createTaxItem("Corporate Tax", "Corporate Income Tax", TaxCategory.CORPORATE_TAX, 3000);

        vm.stopPrank();

        // Assert
        assertEq(taxmate.getTotalTaxItems(), 5);

        // Verify categories
        Taxmate.TaxItem memory item1 = taxmate.getTaxItem(1);
        assertEq(uint(item1.category), uint(TaxCategory.VAT));

        Taxmate.TaxItem memory item2 = taxmate.getTaxItem(2);
        assertEq(uint(item2.category), uint(TaxCategory.PAYE));

        Taxmate.TaxItem memory item3 = taxmate.getTaxItem(3);
        assertEq(uint(item3.category), uint(TaxCategory.WHT));

        Taxmate.TaxItem memory item4 = taxmate.getTaxItem(4);
        assertEq(uint(item4.category), uint(TaxCategory.INCOME_TAX));

        Taxmate.TaxItem memory item5 = taxmate.getTaxItem(5);
        assertEq(uint(item5.category), uint(TaxCategory.CORPORATE_TAX));
    }

    function test_CreateTaxItem_ZeroRate() public {
        // Act
        vm.prank(subAdmin);
        taxmate.createTaxItem(
            "Zero Tax",
            "Tax with zero rate",
            TaxCategory.VAT,
            0 // 0%
        );

        // Assert
        Taxmate.TaxItem memory item = taxmate.getTaxItem(1);
        assertEq(item.rate, 0);
        assertTrue(item.isActive);
    }

    function test_CreateTaxItem_MaxRate() public {
        // Act
        vm.prank(subAdmin);
        taxmate.createTaxItem(
            "High Tax",
            "Tax with high rate",
            TaxCategory.VAT,
            10000 // 100%
        );

        // Assert
        Taxmate.TaxItem memory item = taxmate.getTaxItem(1);
        assertEq(item.rate, 10000);
    }

    // ========== SUCCESSFUL TAX ITEM UPDATE TESTS ==========

    function test_UpdateTaxItem_Success() public {
        // Arrange - Create tax item
        vm.prank(subAdmin);
        taxmate.createTaxItem(
            VAT_NAME,
            VAT_DESCRIPTION,
            TaxCategory.VAT,
            750
        );

        // Act - Update tax item status
        vm.warp(block.timestamp + 1 days); // Move time forward

        vm.expectEmit(true, true, true, true);
        emit Events.TaxItemUpdated(1, false, block.timestamp);

        vm.prank(subAdmin);
        taxmate.updateTaxItem(1, false);

        // Assert
        Taxmate.TaxItem memory item = taxmate.getTaxItem(1);
        assertFalse(item.isActive);
        assertEq(item.updatedAt, block.timestamp);
        // Other properties should remain unchanged
        assertEq(item.name, VAT_NAME);
        assertEq(item.description, VAT_DESCRIPTION);
        assertEq(item.rate, 750);
        assertEq(item.createdAt, block.timestamp - 1 days);
    }

    function test_UpdateTaxItem_Reactivate() public {
        // Arrange - Create and deactivate tax item
        vm.startPrank(subAdmin);
        taxmate.createTaxItem(
            VAT_NAME,
            VAT_DESCRIPTION,
            TaxCategory.VAT,
            750
        );
        taxmate.updateTaxItem(1, false);
        vm.stopPrank();

        // Act - Reactivate tax item
        vm.warp(block.timestamp + 1 days);

        vm.prank(subAdmin);
        taxmate.updateTaxItem(1, true);

        // Assert
        Taxmate.TaxItem memory item = taxmate.getTaxItem(1);
        assertTrue(item.isActive);
        assertEq(item.updatedAt, block.timestamp);
    }

    // ========== ACCESS CONTROL ERROR TESTS ==========

    function test_RevertWhen_CreateTaxItem_NonSubAdmin() public {
        // Act & Assert - Caller without SUB_ADMIN_ROLE
        vm.prank(attacker);
        vm.expectRevert(Errors.CALLER_IS_NOT_A_SUB_ADMIN.selector);
        taxmate.createTaxItem(
            VAT_NAME,
            VAT_DESCRIPTION,
            TaxCategory.VAT,
            750
        );
    }

    function test_RevertWhen_CreateTaxItem_TaxPayer() public {
        // Arrange - Register a taxpayer
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

        // Act & Assert - Taxpayer cannot create tax items
        vm.prank(taxPayer);
        vm.expectRevert(Errors.CALLER_IS_NOT_A_SUB_ADMIN.selector);
        taxmate.createTaxItem(
            VAT_NAME,
            VAT_DESCRIPTION,
            TaxCategory.VAT,
            750
        );
    }

    function test_RevertWhen_UpdateTaxItem_NonSubAdmin() public {
        // Arrange - Create tax item first
        vm.prank(subAdmin);
        taxmate.createTaxItem(
            VAT_NAME,
            VAT_DESCRIPTION,
            TaxCategory.VAT,
            750
        );

        // Act & Assert - Caller without SUB_ADMIN_ROLE
        vm.prank(attacker);
        vm.expectRevert(Errors.CALLER_IS_NOT_A_SUB_ADMIN.selector);
        taxmate.updateTaxItem(1, false);
    }

    function test_RevertWhen_UpdateTaxItem_TaxPayer() public {
        // Arrange - Create tax item and register taxpayer
        vm.prank(subAdmin);
        taxmate.createTaxItem(
            VAT_NAME,
            VAT_DESCRIPTION,
            TaxCategory.VAT,
            750
        );

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

        // Act & Assert - Taxpayer cannot update tax items
        vm.prank(taxPayer);
        vm.expectRevert(Errors.CALLER_IS_NOT_A_SUB_ADMIN.selector);
        taxmate.updateTaxItem(1, false);
    }

    // ========== VALIDATION ERROR TESTS ==========

    function test_RevertWhen_UpdateTaxItem_NonExistent() public {
        // Act & Assert - Try to update non-existent tax item
        vm.prank(subAdmin);
        vm.expectRevert(Errors.TAX_ITEM_DOES_NOT_EXIST.selector);
        taxmate.updateTaxItem(999, false);
    }

    function test_RevertWhen_CreateTaxItem_EmptyName() public {
        // Act & Assert
        vm.prank(subAdmin);
        vm.expectRevert(Errors.TAX_ITEM_NAME_CANNOT_BE_EMPTY.selector);
        taxmate.createTaxItem(
            "", // Empty name
            VAT_DESCRIPTION,
            TaxCategory.VAT,
            750
        );
    }

    function test_RevertWhen_CreateTaxItem_EmptyDescription() public {
        // Act & Assert
        vm.prank(subAdmin);
        vm.expectRevert(Errors.TAX_ITEM_DESCRIPTION_CANNOT_BE_EMPTY.selector); // Will revert due to empty string check
        taxmate.createTaxItem(
            VAT_NAME,
            "", // Empty description
            TaxCategory.VAT,
            750
        );
    }

    // ========== ACTIVE TAX ITEMS TESTS ==========

    function test_GetActiveTaxItems_Success() public {
        // Arrange - Create multiple tax items with mixed status
        vm.startPrank(subAdmin);
        
        taxmate.createTaxItem("VAT Active", "Active VAT", TaxCategory.VAT, 750);
        taxmate.createTaxItem("PAYE Inactive", "Inactive PAYE", TaxCategory.PAYE, 2500);
        taxmate.createTaxItem("WHT Active", "Active WHT", TaxCategory.WHT, 500);
        
        // Deactivate PAYE
        taxmate.updateTaxItem(2, false);
        
        vm.stopPrank();

        // Act
        Taxmate.TaxItem[] memory activeItems = taxmate.getActiveTaxItems();

        // Assert
        assertEq(activeItems.length, 2);
        assertEq(activeItems[0].name, "VAT Active");
        assertEq(activeItems[1].name, "WHT Active");
    }

    function test_GetActiveTaxItems_Empty() public view {
        // Act
        Taxmate.TaxItem[] memory activeItems = taxmate.getActiveTaxItems();

        // Assert
        assertEq(activeItems.length, 0);
    }

    function test_GetActiveTaxItems_AllInactive() public {
        // Arrange - Create and deactivate all items
        vm.startPrank(subAdmin);
        
        taxmate.createTaxItem("VAT", "VAT Desc", TaxCategory.VAT, 750);
        taxmate.createTaxItem("PAYE", "PAYE Desc", TaxCategory.PAYE, 2500);
        
        taxmate.updateTaxItem(1, false);
        taxmate.updateTaxItem(2, false);
        
        vm.stopPrank();

        // Act
        Taxmate.TaxItem[] memory activeItems = taxmate.getActiveTaxItems();

        // Assert
        assertEq(activeItems.length, 0);
    }

    // ========== UTILITY FUNCTION TESTS ==========

    function test_BasisPointsToPercentage() public view {
        // Test various basis points conversions
        assertEq(taxmate.basisPointsToPercentage(100), 1); // 1%
        assertEq(taxmate.basisPointsToPercentage(750), 7); // 7.5% -> 7 (integer division)
        assertEq(taxmate.basisPointsToPercentage(2500), 25); // 25%
        assertEq(taxmate.basisPointsToPercentage(0), 0); // 0%
        assertEq(taxmate.basisPointsToPercentage(10000), 100); // 100%
    }

    function test_CalculateTaxAmount() public view {
        // Test tax calculation
        assertEq(taxmate.calculateTaxAmount(1000, 100), 10); // 1% of 1000 = 10
        assertEq(taxmate.calculateTaxAmount(1000, 750), 75); // 7.5% of 1000 = 75
        assertEq(taxmate.calculateTaxAmount(1000, 2500), 250); // 25% of 1000 = 250
        assertEq(taxmate.calculateTaxAmount(1000, 0), 0); // 0% of 1000 = 0
        assertEq(taxmate.calculateTaxAmount(1000, 10000), 1000); // 100% of 1000 = 1000
        
        // Test with larger amounts
        assertEq(taxmate.calculateTaxAmount(1000000, 750), 75000); // 7.5% of 1,000,000 = 75,000
    }

    function test_CalculateTaxAmount_Rounding() public view {
        // Test rounding behavior
        assertEq(taxmate.calculateTaxAmount(100, 125), 1); // 1.25% of 100 = 1.25 -> 1 (truncated)
        assertEq(taxmate.calculateTaxAmount(1000, 333), 33); // 3.33% of 1000 = 33.3 -> 33 (truncated)
    }

    // ========== EDGE CASE TESTS ==========

    function test_CreateTaxItem_LongStrings() public {
        // Test with maximum reasonable string lengths
        string memory longName = "Very Long Tax Item Name That Exceeds Normal Length Limits But Should Still Work";
        string memory longDescription = "This is an extremely long description for a tax item that contains detailed information about the tax regulations, applicable sectors, calculation methods, and compliance requirements. It should handle long strings without issues.";

        vm.prank(subAdmin);
        taxmate.createTaxItem(
            longName,
            longDescription,
            TaxCategory.VAT,
            750
        );

        // Assert
        Taxmate.TaxItem memory item = taxmate.getTaxItem(1);
        assertEq(item.name, longName);
        assertEq(item.description, longDescription);
    }

    function test_UpdateTaxItem_MultipleTimes() public {
        // Arrange
        vm.prank(subAdmin);
        taxmate.createTaxItem(VAT_NAME, VAT_DESCRIPTION, TaxCategory.VAT, 750);

        // Act - Update multiple times
        vm.startPrank(subAdmin);
        
        vm.warp(block.timestamp + 1 hours);
        taxmate.updateTaxItem(1, false);
        
        vm.warp(block.timestamp + 1 hours);
        taxmate.updateTaxItem(1, true);
        
        vm.warp(block.timestamp + 1 hours);
        taxmate.updateTaxItem(1, false);
        
        vm.stopPrank();

        // Assert
        Taxmate.TaxItem memory item = taxmate.getTaxItem(1);
        assertFalse(item.isActive);
        assertEq(item.updatedAt, block.timestamp);
    }

    function test_TaxItemCounter_IncrementsCorrectly() public {
        // Create multiple items and verify counter
        vm.startPrank(subAdmin);
        
        taxmate.createTaxItem("Tax 1", "Desc 1", TaxCategory.VAT, 100);
        assertEq(taxmate.getTotalTaxItems(), 1);
        
        taxmate.createTaxItem("Tax 2", "Desc 2", TaxCategory.PAYE, 200);
        assertEq(taxmate.getTotalTaxItems(), 2);
        
        taxmate.createTaxItem("Tax 3", "Desc 3", TaxCategory.WHT, 300);
        assertEq(taxmate.getTotalTaxItems(), 3);
        
        vm.stopPrank();
    }

    // ========== EVENT EMISSION TESTS ==========

    function test_Events_EmittedCorrectly() public {
        // Test TaxItemCreated event
        vm.expectEmit(true, true, true, true);
        emit Events.TaxItemCreated(1, VAT_NAME, TaxCategory.VAT, 750);
        
        vm.prank(subAdmin);
        taxmate.createTaxItem(VAT_NAME, VAT_DESCRIPTION, TaxCategory.VAT, 750);

        // Test TaxItemUpdated event
        vm.expectEmit(true, true, true, true);
        emit Events.TaxItemUpdated(1, false, block.timestamp);
        
        vm.prank(subAdmin);
        taxmate.updateTaxItem(1, false);
    }

    // ========== SUPER ADMIN TESTS ==========

    function test_SuperAdmin_CanCreateTaxItems() public {
        // SuperAdmin should be able to create tax items (has SUB_ADMIN_ROLE)
        vm.prank(superAdmin);
        taxmate.createTaxItem(
            VAT_NAME,
            VAT_DESCRIPTION,
            TaxCategory.VAT,
            750
        );

        // Assert
        assertEq(taxmate.getTotalTaxItems(), 1);
    }

    function test_SuperAdmin_CanUpdateTaxItems() public {
        // Arrange
        vm.prank(subAdmin);
        taxmate.createTaxItem(VAT_NAME, VAT_DESCRIPTION, TaxCategory.VAT, 750);

        // Act - SuperAdmin updates
        vm.prank(superAdmin);
        taxmate.updateTaxItem(1, false);

        // Assert
        Taxmate.TaxItem memory item = taxmate.getTaxItem(1);
        assertFalse(item.isActive);
    }
}