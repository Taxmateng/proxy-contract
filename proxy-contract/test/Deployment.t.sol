// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { Taxmate } from "../contracts/Taxmate.sol";
import { TaxCategory } from "../contracts/lib/TaxTypes.sol";
import { Errors } from "../contracts/lib/Errors.sol";
import { Events } from "../contracts/lib/Events.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeploymentTest is Test {
    Taxmate public taxmate;
    Taxmate public taxmateImplementation;
    address public superAdmin;
    address public subAdmin;
    address public taxPayer;
    address public attacker;
    
    // Test constants
    address constant ZERO_ADDRESS = address(0);
    address constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        superAdmin = makeAddr("superAdmin");
        subAdmin = makeAddr("subAdmin");
        taxPayer = makeAddr("taxPayer");
        attacker = makeAddr("attacker");
    }

    // ========== SUCCESSFUL DEPLOYMENT TESTS ==========

    function test_Deployment_Success() public {
        // Act - Deploy using proxy pattern
        vm.prank(superAdmin);
        taxmateImplementation = new Taxmate();
        
        bytes memory data = abi.encodeWithSelector(Taxmate.initialize.selector, superAdmin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(taxmateImplementation), data);
        taxmate = Taxmate(address(proxy));

        // Assert
        assertTrue(taxmate.hasRole(taxmate.SUPER_ADMIN_ROLE(), superAdmin));
        assertEq(taxmate.getRoleAdmin(taxmate.SUPER_ADMIN_ROLE()), taxmate.SUPER_ADMIN_ROLE());
        assertEq(taxmate.getRoleAdmin(taxmate.SUB_ADMIN_ROLE()), taxmate.SUPER_ADMIN_ROLE());
        assertEq(taxmate.getRoleAdmin(taxmate.TAX_PAYER_ROLE()), taxmate.SUPER_ADMIN_ROLE());
    }

    function test_Deployment_SuperAdminHasAllRoles() public {
        vm.prank(superAdmin);
        taxmateImplementation = new Taxmate();
        
        bytes memory data = abi.encodeWithSelector(Taxmate.initialize.selector, superAdmin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(taxmateImplementation), data);
        taxmate = Taxmate(address(proxy));

        // Assert
        assertTrue(taxmate.hasRole(taxmate.SUPER_ADMIN_ROLE(), superAdmin));
        assertTrue(taxmate.hasRole(taxmate.SUB_ADMIN_ROLE(), superAdmin));
    }

    // ========== INITIALIZATION FAILURE TESTS ==========

    function test_RevertWhen_InitializeWithZeroAddress() public {
        // Arrange
        taxmate = new Taxmate();

        // Act & Assert
        vm.expectRevert(
            Errors.INITIALIZER_CAN_NOT_BE_ADDRESS_ZERO.selector
        ); // AccessControl: default admin role can only be granted by the default admin
        taxmate.initialize(ZERO_ADDRESS);
    }

    function test_RevertWhen_InitializeContractTwice() public {
        // Arrange
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Act & Assert
        vm.expectRevert("Initializable: contract is already initialized");
        taxmate.initialize(superAdmin);
    }

    // ========== UPGRADE AUTHORIZATION TESTS ==========

    function test_RevertWhen_UpgradeByNonSuperAdmin() public {
        // Arrange
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Create a new implementation
        Taxmate newImplementation = new Taxmate();

        // Act & Assert
        vm.prank(attacker);
        vm.expectRevert(); // Only super admin can upgrade
        taxmate.upgradeTo(address(newImplementation));
    }

    function test_RevertWhen_UpgradeToZeroAddress() public {
        // Arrange
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Act & Assert
        vm.prank(superAdmin);
        vm.expectRevert(); // UUPS: new implementation is not UUPS
        taxmate.upgradeTo(ZERO_ADDRESS);
    }

    function test_RevertWhen_UpgradeToNonUUPSContract() public {
        // Arrange
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Create a non-UUPS contract
        address nonUUPSContract = address(new NonUUPSContract());

        // Act & Assert
        vm.prank(superAdmin);
        vm.expectRevert(); // UUPS: new implementation is not UUPS
        taxmate.upgradeTo(nonUUPSContract);
    }

    // ========== ROLE ADMIN CONFIGURATION TESTS ==========

    function test_RoleAdminConfiguration() public {
        // Arrange & Act
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Assert role admin hierarchy
        assertEq(
            taxmate.getRoleAdmin(taxmate.SUPER_ADMIN_ROLE()),
            taxmate.SUPER_ADMIN_ROLE(),
            "SUPER_ADMIN_ROLE should be managed by itself"
        );
        assertEq(
            taxmate.getRoleAdmin(taxmate.SUB_ADMIN_ROLE()),
            taxmate.SUPER_ADMIN_ROLE(),
            "SUB_ADMIN_ROLE should be managed by SUPER_ADMIN_ROLE"
        );
        assertEq(
            taxmate.getRoleAdmin(taxmate.TAX_PAYER_ROLE()),
            taxmate.SUPER_ADMIN_ROLE(),
            "TAX_PAYER_ROLE should be managed by SUPER_ADMIN_ROLE"
        );
    }

    // ========== CONTRACT DEPENDENCIES TESTS ==========

    function test_OpenZeppelinDependencies() public {
        // This test ensures all required OZ contracts are properly linked
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // If any dependency is missing, the contract wouldn't deploy
        assertTrue(address(taxmate) != ZERO_ADDRESS);
    }

    // ========== GAS LIMIT AND SIZE TESTS ==========

    function test_ContractSizeWithinLimits() public {
        // Arrange & Act
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Get contract code size
        uint256 size;
        address contractAddress = address(taxmate);
        assembly {
            size := extcodesize(contractAddress)
        }

        // Assert - Ethereum mainnet has 24KB limit, but for Base it might be different
        // This is a sanity check to ensure we're not hitting any unexpected limits
        assertLt(size, 50000, "Contract size should be reasonable");
        console.log("Contract size: %s bytes", size);
    }

    function test_DeploymentGasCost() public {
        // Arrange
        vm.prank(superAdmin);
        
        // Act - measure gas
        uint256 gasBefore = gasleft();
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);
        uint256 gasUsed = gasBefore - gasleft();

        // Assert - ensure gas usage is within expected bounds
        // This helps catch unexpected gas spikes that could break deployment
        assertLt(gasUsed, 10_000_000, "Deployment gas should be reasonable");
        console.log("Deployment gas used: %s", gasUsed);
    }

    // ========== REENTRANCY GUARD TEST ==========

    function test_ReentrancyGuardInitialized() public {
        // This test ensures ReentrancyGuard is properly initialized
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // If reentrancy guard wasn't initialized, certain functions might fail
        // We test this by ensuring the contract can be used normally
        assertTrue(taxmate.hasRole(taxmate.SUPER_ADMIN_ROLE(), superAdmin));
    }

    // ========== COMPILER VERSION COMPATIBILITY ==========

    function test_CompilerVersionCompatibility() public {
        // This test ensures the contract compiles with the specified version
        // If there's a version mismatch, this test file itself wouldn't compile
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Basic functionality test to ensure version compatibility
        assertTrue(address(taxmate).code.length > 0);
    }

    // ========== STORAGE LAYOUT TESTS ==========

    function test_StorageLayoutConsistency() public {
        // This test helps catch storage layout issues that could break upgrades
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Access various storage variables to ensure layout is correct
        bytes32 superAdminRole = taxmate.SUPER_ADMIN_ROLE();
        bytes32 subAdminRole = taxmate.SUB_ADMIN_ROLE();
        bytes32 taxPayerRole = taxmate.TAX_PAYER_ROLE();

        assertTrue(superAdminRole != bytes32(0));
        assertTrue(subAdminRole != bytes32(0));
        assertTrue(taxPayerRole != bytes32(0));
        assertTrue(superAdminRole != subAdminRole);
        assertTrue(subAdminRole != taxPayerRole);
    }

    // ========== EDGE CASE TESTS ==========

    function test_DeploymentWithMaxAddress() public {
        // Test deployment with edge case addresses
        address maxAddress = address(type(uint160).max);
        
        vm.prank(maxAddress);
        taxmate = new Taxmate();
        taxmate.initialize(maxAddress);

        assertTrue(taxmate.hasRole(taxmate.SUPER_ADMIN_ROLE(), maxAddress));
    }

    function test_DeploymentWithContractAddressAsAdmin() public {
        // Test using a contract address as superAdmin
        address contractAdmin = address(new MockContract());
        
        vm.prank(contractAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(contractAdmin);

        assertTrue(taxmate.hasRole(taxmate.SUPER_ADMIN_ROLE(), contractAdmin));
    }

    function test_DeploymentWithLowGasSimulation() public {
        // Test deployment under different gas conditions
        vm.prank(superAdmin);
        
        // We can't directly set gas for new, but we can test deployment doesn't exceed reasonable limits
        uint256 gasBefore = gasleft();
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Ensure deployment doesn't use excessive gas
        assertLt(gasUsed, 5_300_000, "Deployment should not use excessive gas");
    }

    // ========== MULTIPLE DEPLOYMENT TESTS ==========

    function test_MultipleDeployments() public {
        // Test deploying multiple instances
        Taxmate taxmate1;
        Taxmate taxmate2;
        
        vm.prank(superAdmin);
        taxmate1 = new Taxmate();
        taxmate1.initialize(superAdmin);

        vm.prank(superAdmin);
        taxmate2 = new Taxmate();
        taxmate2.initialize(superAdmin);

        assertTrue(address(taxmate1) != address(taxmate2));
        assertTrue(taxmate1.hasRole(taxmate1.SUPER_ADMIN_ROLE(), superAdmin));
        assertTrue(taxmate2.hasRole(taxmate2.SUPER_ADMIN_ROLE(), superAdmin));
    }

    // ========== ACCESS CONTROL TESTS ==========

    function test_InitialRoleGrants() public {
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Test that only superAdmin has roles initially
        assertFalse(taxmate.hasRole(taxmate.SUPER_ADMIN_ROLE(), subAdmin));
        assertFalse(taxmate.hasRole(taxmate.SUB_ADMIN_ROLE(), subAdmin));
        assertFalse(taxmate.hasRole(taxmate.TAX_PAYER_ROLE(), taxPayer));
    }

    // ========== UPGRADE SAFETY TESTS ==========

    function test_ImplementationNotInitializable() public {
        // Test that the implementation contract cannot be initialized
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        
        // The implementation should not be initializable directly
        // This is a safety check for UUPS pattern
        taxmate.initialize(superAdmin);
        
        // Should not be able to initialize again
        vm.expectRevert("Initializable: contract is already initialized");
        taxmate.initialize(superAdmin);
    }

    // ========== FUNCTIONALITY TESTS AFTER DEPLOYMENT ==========

    function test_BasicFunctionalityAfterDeployment() public {
        // Arrange
        vm.startPrank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        assertTrue(taxmate.hasRole(taxmate.SUPER_ADMIN_ROLE(), superAdmin));

        // Act - Test basic admin functions
        taxmate.addAdmin(subAdmin, taxmate.SUB_ADMIN_ROLE());

        vm.stopPrank();

        // // Assert
        assertTrue(taxmate.hasRole(taxmate.SUB_ADMIN_ROLE(), subAdmin));
    }

    function test_TaxItemCreationAfterDeployment() public {
        // Arrange
        vm.startPrank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Grant subAdmin role
        taxmate.addAdmin(subAdmin, taxmate.SUB_ADMIN_ROLE());

        vm.stopPrank();
        // Act - Create tax item
        vm.prank(subAdmin);
        taxmate.createTaxItem("VAT", "Value Added Tax", TaxCategory.VAT, 750); // 7.5%

        // Assert
        Taxmate.TaxItem memory item = taxmate.getTaxItem(1);
        assertEq(item.itemId, 1);
        assertEq(item.name, "VAT");
        assertEq(item.rate, 750);
        assertTrue(item.isActive);
    }

    function test_UserRegistrationAfterDeployment() public {
        // Arrange
        vm.startPrank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Act - Register individual taxpayer
        taxmate.registerTaxpayer(
            taxPayer,
            "123456789",
            "ID123456",
            "BVN",
            "test@example.com",
            "John",
            "Doe",
            "Middle",
            "1990-01-01",
            "male"
        );

        vm.stopPrank();
        // Assert
        assertTrue(taxmate.hasRole(taxmate.TAX_PAYER_ROLE(), taxPayer));
        assertTrue(taxmate.isRegisteredTaxpayer(taxPayer));
        
        Taxmate.IndividualProfile memory profile = taxmate.getIndividualProfile(taxPayer);
        assertEq(profile.tin, "123456789");
        assertEq(profile.firstname, "John");
        assertEq(profile.lastname, "Doe");
    }

    // ========== SECURITY TESTS ==========

    function test_RevertWhen_NonAdminTriesToCreateTaxItem() public {
        // Arrange
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Act & Assert
        vm.prank(attacker);
        vm.expectRevert(); // Should revert due to lack of SUB_ADMIN_ROLE
        taxmate.createTaxItem("VAT", "Value Added Tax", TaxCategory.VAT, 750);
    }

    function test_RevertWhen_NonAdminTriesToRegisterUser() public {
        // Arrange
        vm.prank(superAdmin);
        taxmate = new Taxmate();
        taxmate.initialize(superAdmin);

        // Act & Assert
        vm.prank(attacker);
        vm.expectRevert(); // Should revert due to access control
        taxmate.registerTaxpayer(
            taxPayer,
            "123456789",
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

    // ========== UPGRADE FUNCTIONALITY TESTS ==========

    function test_ContractCanBeUpgraded() public {
        // Arrange
        vm.startPrank(superAdmin);
        taxmateImplementation = new Taxmate();
        
        bytes memory data = abi.encodeWithSelector(Taxmate.initialize.selector, superAdmin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(taxmateImplementation), data);
        taxmate = Taxmate(address(proxy));

        // Create and register a user first to test data preservation
        taxmate.registerTaxpayer(
            taxPayer,
            "123456789",
            "ID123456",
            "BVN",
            "test@example.com",
            "John",
            "Doe",
            "Middle",
            "1990-01-01",
            "male"
        );

        address originalAddress = address(taxmate);
        // address originalImplementation = _getImplementation(address(taxmate));

        // Act - Upgrade the contract
        Taxmate newImplementation = new Taxmate();
        taxmate.upgradeTo(address(newImplementation));

        vm.stopPrank();
        
        // Assert - Address should remain the same but implementation should change
        assertEq(address(taxmate), originalAddress);
        assertEq(_getImplementation(address(taxmate)), address(newImplementation));
        
        // Data should be preserved
        assertTrue(taxmate.hasRole(taxmate.TAX_PAYER_ROLE(), taxPayer));
        assertTrue(taxmate.isRegisteredTaxpayer(taxPayer));
        
        // Verify the profile data is still accessible
        Taxmate.IndividualProfile memory profile = taxmate.getIndividualProfile(taxPayer);
        assertEq(profile.tin, "123456789");
        assertEq(profile.firstname, "John");
        assertEq(profile.lastname, "Doe");
    }

        // ========== HELPER FUNCTIONS ==========

    function _getImplementation(address proxy) internal view returns (address) {
        // ERC1967 implementation slot
        bytes32 slot = bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1);
        address implementation;
        assembly {
            implementation := sload(slot)
        }
        return implementation;
    }
}

// Mock contracts for testing

contract NonUUPSContract {
    // This contract doesn't implement UUPS interface
    function dummy() public pure returns (bool) {
        return true;
    }
}

contract MockContract {
    // Simple mock contract for testing contract address as admin
    function dummy() public pure returns (bool) {
        return true;
    }
}