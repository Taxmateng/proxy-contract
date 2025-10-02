// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { Taxmate } from "../contracts/Taxmate.sol";
import { TaxCategory, Gender } from "../contracts/lib/TaxTypes.sol";
import { Errors } from "../contracts/lib/Errors.sol";
import { Events } from "../contracts/lib/Events.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RegistrationTest is Test {
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

    function setUp() public {
        superAdmin = makeAddr("superAdmin");
        subAdmin = makeAddr("subAdmin");
        taxPayer = makeAddr("taxPayer");
        taxPayer2 = makeAddr("taxPayer2");
        attacker = makeAddr("attacker");

        // Deploy contract
        vm.prank(superAdmin);
        taxmateImplementation = new Taxmate();
        
        bytes memory data = abi.encodeWithSelector(Taxmate.initialize.selector, superAdmin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(taxmateImplementation), data);
        taxmate = Taxmate(address(proxy));
    }

    // ========== SUCCESSFUL REGISTRATION TESTS ==========

    function test_RegisterIndividual_Success() public {
        // Act
        vm.expectEmit(true, true, true, true);
        emit Events.UserRegistered(taxPayer, INDIVIDUAL_TIN, block.timestamp);

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

        // Assert
        assertTrue(taxmate.hasRole(taxmate.TAX_PAYER_ROLE(), taxPayer));
        assertTrue(taxmate.isRegisteredTaxpayer(taxPayer));
        
        Taxmate.IndividualProfile memory profile = taxmate.getIndividualProfile(taxPayer);
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
        assertEq(profile.lastPaymentDate, 0);

        // Check TIN mappings
        assertEq(taxmate.tinToAddress(INDIVIDUAL_TIN), taxPayer);
        assertEq(taxmate.addressToTin(taxPayer), INDIVIDUAL_TIN);
    }

    function test_RegisterIndividual_FemaleGender() public {
        // Act
        taxmate.registerTaxpayer(
            taxPayer,
            INDIVIDUAL_TIN,
            "ID123456",
            "BVN",
            "test@example.com",
            "Jane",
            "Doe",
            "Middle",
            "1990-01-01",
            "female"
        );

        // Assert
        Taxmate.IndividualProfile memory profile = taxmate.getIndividualProfile(taxPayer);
        assertEq(uint(profile.gender), uint(Gender.FEMALE));
    }

    function test_RegisterBusiness_Success() public {
        // Act
        vm.expectEmit(true, true, true, true);
        emit Events.UserRegistered(taxPayer, BUSINESS_TIN, block.timestamp);

        taxmate.registerBusiness(
            taxPayer,
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

        // Assert
        assertTrue(taxmate.hasRole(taxmate.TAX_PAYER_ROLE(), taxPayer));
        assertTrue(taxmate.isRegisteredTaxpayer(taxPayer));
        
        Taxmate.BusinessProfile memory profile = taxmate.getBusinessProfile(taxPayer);
        assertEq(profile.walletAddress, taxPayer);
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
        assertEq(profile.lastPaymentDate, 0);

        // Check TIN mappings
        assertEq(taxmate.tinToAddress(BUSINESS_TIN), taxPayer);
        assertEq(taxmate.addressToTin(taxPayer), BUSINESS_TIN);
    }

    function test_RegisterBusiness_Inactive() public {
        // Act
        taxmate.registerBusiness(
            taxPayer,
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
            false // isActive = false
        );

        // Assert
        Taxmate.BusinessProfile memory profile = taxmate.getBusinessProfile(taxPayer);
        assertFalse(profile.isActive);
        assertTrue(taxmate.hasRole(taxmate.TAX_PAYER_ROLE(), taxPayer)); // Should still get TAX_PAYER_ROLE
    }

    // ========== INDIVIDUAL REGISTRATION ERROR TESTS ==========

    function test_RevertWhen_RegisterIndividual_EmptyTIN() public {
        // Act & Assert
        vm.expectRevert(Errors.TIN_CAN_NOT_BE_EMPTY.selector);
        taxmate.registerTaxpayer(
            taxPayer,
            "", // Empty TIN
            "ID123456",
            "BVN",
            "test@example.com",
            "John",
            "Doe",
            "Middle",
            "1990-01-01",
            "male"
        );
    }

    function test_RevertWhen_RegisterIndividual_TINAlreadyExists() public {
        // Arrange - Register first user
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

        // Act & Assert - Try to register another user with same TIN
        vm.expectRevert(Errors.TIN_ALREADY_EXISTS.selector);
        taxmate.registerTaxpayer(
            taxPayer2,
            INDIVIDUAL_TIN, // Same TIN
            "ID789012",
            "NIN",
            "test2@example.com",
            "Jane",
            "Smith",
            "",
            "1992-02-02",
            "female"
        );
    }

    function test_RevertWhen_RegisterIndividual_UserAlreadyExists() public {
        // Arrange - Register user
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

        // Act & Assert - Try to register same user again with different TIN
        vm.expectRevert(Errors.USER_EXISTS_ALREADY.selector);
        taxmate.registerTaxpayer(
            taxPayer, // Same user address
            DUPLICATE_TIN, // Different TIN
            "ID789012",
            "NIN",
            "test2@example.com",
            "Jane",
            "Smith",
            "",
            "1992-02-02",
            "female"
        );
    }

    function test_RevertWhen_RegisterIndividual_InvalidGender() public {
        // Act & Assert
        vm.expectRevert(Errors.INVALID_GENDER.selector);
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
            "invalid_gender" // Invalid gender
        );
    }

    function test_RevertWhen_RegisterIndividual_GenderCaseSensitive() public {
        // Act & Assert - "Male" with capital M should fail
        vm.expectRevert(Errors.INVALID_GENDER.selector);
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
            "Male" // Should be "male"
        );
    }


    // ========== BUSINESS REGISTRATION ERROR TESTS ==========

    function test_RevertWhen_RegisterBusiness_EmptyTIN() public {
        // Act & Assert
        vm.expectRevert(Errors.TIN_CAN_NOT_BE_EMPTY.selector);
        taxmate.registerBusiness(
            taxPayer,
            "", // Empty TIN
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
    }

    function test_RevertWhen_RegisterBusiness_TINAlreadyExists() public {
        // Arrange - Register individual first
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

        // Act & Assert - Try to register business with same TIN
        vm.expectRevert(Errors.TIN_ALREADY_EXISTS.selector);
        taxmate.registerBusiness(
            taxPayer2,
            INDIVIDUAL_TIN, // Same TIN as individual
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
    }

    function test_RevertWhen_RegisterBusiness_BusinessAlreadyExists() public {
        // Arrange - Register business first
        taxmate.registerBusiness(
            taxPayer,
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

        // Act & Assert - Try to register same business again with different TIN
        vm.expectRevert(Errors.BUSINESS_EXISTS_ALREADY.selector);
        taxmate.registerBusiness(
            taxPayer, // Same business address
            DUPLICATE_TIN, // Different TIN
            "RC789012",
            "Another Company",
            "Corp",
            "2021-01-01",
            "456 Other St",
            "another@test.com",
            "Abuja",
            "Small Enterprise",
            "789 Other Ave",
            "Garki",
            "Affiliate3",
            "500000",
            "Five Hundred Thousand",
            "Abuja",
            true
        );
    }

    // ========== MIXED REGISTRATION SCENARIOS ==========

    function test_IndividualAndBusiness_CanHaveDifferentTINs() public {
        // Arrange - Register individual
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

        // Act - Register business with different TIN
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

        // Assert - Both should be registered successfully
        assertTrue(taxmate.isRegisteredTaxpayer(taxPayer));
        assertTrue(taxmate.isRegisteredTaxpayer(taxPayer2));
        assertEq(taxmate.tinToAddress(INDIVIDUAL_TIN), taxPayer);
        assertEq(taxmate.tinToAddress(BUSINESS_TIN), taxPayer2);
    }

    function test_CannotRegisterIndividualAndBusiness_WithSameAddress() public {
        // Arrange - Register individual
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

        // Act & Assert - Try to register business with same address
        vm.expectRevert(Errors.BUSINESS_EXISTS_ALREADY.selector);
        taxmate.registerBusiness(
            taxPayer, // Same address as individual
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
    }

    function test_CannotRegisterBusinessAndIndividual_WithSameAddress() public {
        // Arrange - Register business first
        taxmate.registerBusiness(
            taxPayer,
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

        // Act & Assert - Try to register individual with same address
        vm.expectRevert(Errors.USER_EXISTS_ALREADY.selector);
        taxmate.registerTaxpayer(
            taxPayer, // Same address as business
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
    }

    // ========== ROLE ASSIGNMENT TESTS ==========

    function test_TaxPayerRole_AssignedAfterIndividualRegistration() public {
        // Act
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

        // Assert
        assertTrue(taxmate.hasRole(taxmate.TAX_PAYER_ROLE(), taxPayer));
        assertFalse(taxmate.hasRole(taxmate.SUPER_ADMIN_ROLE(), taxPayer));
        assertFalse(taxmate.hasRole(taxmate.SUB_ADMIN_ROLE(), taxPayer));
    }

    function test_TaxPayerRole_AssignedAfterBusinessRegistration() public {
        // Act
        taxmate.registerBusiness(
            taxPayer,
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

        // Assert
        assertTrue(taxmate.hasRole(taxmate.TAX_PAYER_ROLE(), taxPayer));
        assertFalse(taxmate.hasRole(taxmate.SUPER_ADMIN_ROLE(), taxPayer));
        assertFalse(taxmate.hasRole(taxmate.SUB_ADMIN_ROLE(), taxPayer));
    }

    // ========== PROFILE TYPE DETECTION TESTS ==========

    function test_GetProfileType_Individual() public {
        // Arrange
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

        // Act & Assert
        assertEq(taxmate.getProfileType(taxPayer), "individual");
    }

    function test_GetProfileType_Business() public {
        // Arrange
        taxmate.registerBusiness(
            taxPayer,
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

        // Act & Assert
        assertEq(taxmate.getProfileType(taxPayer), "business");
    }

    function test_GetProfileType_None() public view {
        // Act & Assert
        assertEq(taxmate.getProfileType(taxPayer), "none");
    }

    // ========== EDGE CASE TESTS ==========

    function test_RegisterIndividual_ZeroAddress() public {
        // Act & Assert
        vm.expectRevert(Errors.CANNOT_REGISTER_ADDRESS_ZERO.selector);
        taxmate.registerTaxpayer(
            ZERO_ADDRESS,
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
    }

    function test_RegisterBusiness_ZeroAddress() public {
        // Act & Assert
        vm.expectRevert(Errors.CANNOT_REGISTER_ADDRESS_ZERO.selector); // Will revert due to zero address checks in AccessControl
        taxmate.registerBusiness(
            ZERO_ADDRESS,
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
    }

    function test_RegisterIndividual_MaxStringLengths() public {
        // Act - Test with reasonably long strings
        taxmate.registerTaxpayer(
            taxPayer,
            "12345678901234567890", // 20 char TIN
            "ID12345678901234567890", // 22 char ID
            "BVN_VERY_LONG_TYPE_123", // 23 char type
            "very.long.email.address@example-domain.com", // 41 char email
            "VeryLongFirstNameThatExceedsNormalLength", // 40 char firstname
            "VeryLongLastNameThatAlsoExceedsNormalLength", // 43 char lastname
            "ExtremelyLongMiddleNameThatIsVeryLongIndeed", // 45 char middlename
            "1990-01-01",
            "male"
        );

        // Assert
        assertTrue(taxmate.isRegisteredTaxpayer(taxPayer));
    }

    // ========== EVENT EMISSION TESTS ==========

    function test_Events_EmittedCorrectly() public {
        // Test individual registration event
        vm.expectEmit(true, true, true, true);
        emit Events.UserRegistered(taxPayer, INDIVIDUAL_TIN, block.timestamp);
        
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

        // Test business registration event
        vm.expectEmit(true, true, true, true);
        emit Events.UserRegistered(taxPayer2, BUSINESS_TIN, block.timestamp);
        
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
    }
}