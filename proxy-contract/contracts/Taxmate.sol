// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Errors } from "./lib/Errors.sol";
import { Events } from "./lib/Events.sol";
import { TaxCategory, Gender, IdType } from "./lib/TaxTypes.sol";

/**
 * @title Decentralized Tax Payment System
 * @dev A smart contract for managing tax payments on Base chain
 * @notice Supports WHT, PAYE, VAT, and other tax types with role-based access control
 */
contract Taxmate is Initializable, UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    // Role definitions
    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant SUB_ADMIN_ROLE = keccak256("SUB_ADMIN_ROLE");
    bytes32 public constant TAX_PAYER_ROLE = keccak256("TAX_PAYER_ROLE");

    // Counters for IDs
    CountersUpgradeable.Counter private _taxItemIds;
    CountersUpgradeable.Counter private _paymentRecordIds;

    // Tax item structure
    struct TaxItem {
        uint256 itemId;
        string name;
        string description;
        TaxCategory category;
        uint256 rate; // Rate in basis points (1% = 100)
        bool isActive;
        uint256 createdAt;
        uint256 updatedAt;
    }

    // Payment record structure
    struct PaymentRecord {
        uint256 recordId;
        address payer;
        string tin;
        uint256 itemId;
        uint256 amountPaid;
        string paymentRef;
        string receiptHash; // IPFS hash
        uint256 timestamp;
        TaxCategory category;
    }

    // IndividualProfile
    struct IndividualProfile {
        address walletAddress;
        string tin;
        string idNumber;
        string idType;
        string email;
        string firstname;
        string lastname;
        string middlename;
        string dob;
        Gender gender;
        bool isActive;
        uint256 registrationDate;
        uint256 lastPaymentDate;
    }

    struct BusinessProfile{
      address walletAddress;
      string tin;
      string rcNumber;
      string companyName;
      string companyType;
      string businessRegistrationDate;
      string branchAddress;
      string companyEmail;
      string city;
      string classification;
      string headOfficeAddress;
      string lga;
      string affiliates;
      string shareCapital;
      string shareCapitalInWords;
      string state;
      bool isActive;
      uint256 taxRegistrationDate;
      uint256 lastPaymentDate;
    }

    // Mappings
    mapping(uint256 => TaxItem) public taxItems;
    mapping(uint256 => PaymentRecord) public paymentRecords;
    mapping(string => address) public tinToAddress;
    mapping(address => string) public addressToTin;
    mapping(address => IndividualProfile) public individualProfiles;
    mapping(address => BusinessProfile) public businessProfiles;
    mapping(address => uint256[]) public taxpayerPaymentHistory;

    // Events
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

    // Modifiers
    modifier onlySuperAdmin() {
        require(hasRole(SUPER_ADMIN_ROLE, msg.sender), Errors.CALLER_IS_NOT_A_SUPER_ADMIN());
        _;
    }

    modifier onlySubAdmin() {
        require(hasRole(SUB_ADMIN_ROLE, msg.sender), Errors.CALLER_IS_NOT_A_SUB_ADMIN());
        _;
    }

    modifier onlyTaxPayer() {
        require(hasRole(TAX_PAYER_ROLE, msg.sender), Errors.CALLER_IS_NOT_A_TAX_PAYER());
        _;
    }

    modifier validTIN(string memory tin) {
        require(bytes(tin).length > 0, Errors.TIN_CAN_NOT_BE_EMPTY());
        _;
    }

    modifier taxItemExists(uint256 itemId) {
        require(taxItems[itemId].itemId != 0, Errors.TAX_ITEM_DOES_NOT_EXIST());
        _;
    }

    modifier taxItemActive(uint256 itemId) {
        require(taxItems[itemId].isActive, Errors.TAX_ITEM_IS_NOT_ACTIVE());
        _;
    }

    /**
     * @dev Initializer function (replaces constructor for upgradeable contracts)
     * @param superAdmin The address of the super admin
     */
    function initialize(address superAdmin) public initializer {
        if (superAdmin == address(0)) {
            revert Errors.INITIALIZER_CAN_NOT_BE_ADDRESS_ZERO();
        }
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _setupRole(SUPER_ADMIN_ROLE, superAdmin);
        _setupRole(SUB_ADMIN_ROLE, superAdmin);
        _setRoleAdmin(SUPER_ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(SUB_ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(TAX_PAYER_ROLE, SUPER_ADMIN_ROLE);
    }

    /**
     * @dev Internal function to authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlySuperAdmin {}

    // ADMIN FUNCTIONS

    /**
     * @dev Add a new admin with specific role
     * @param admin Address of the admin to add
     * @param role Role to assign (SUPER_ADMIN_ROLE or SUB_ADMIN_ROLE)
     */
    function addAdmin(address admin, bytes32 role) external onlySuperAdmin {
        require(role == SUPER_ADMIN_ROLE || role == SUB_ADMIN_ROLE, Errors.INVALID_ROLE(role));
        grantRole(role, admin);
        emit Events.AdminAdded(admin, role);
    }

    /**
     * @dev Remove an admin from a role
     * @param admin Address of the admin to remove
     * @param role Role to remove
     */
    function removeAdmin(address admin, bytes32 role) external onlySuperAdmin {
        revokeRole(role, admin);
        emit Events.AdminRemoved(admin, role);
    }

    /**
     * @dev Register a new taxpayer (called by backend after verification)
     * @param user Address of the taxpayer
     * @param tin Tax Identification Number
     * @param idNumber Id Number
     * string idType; BVN,NIN, CAC for verification
     * @param email  email for verification
     */
    function registerTaxpayer(
        address user,
        string memory tin,
        string memory idNumber,
        string memory idType,
        string memory email,
        string memory firstname,
        string memory lastname,
        string memory middlename,
        string memory dob,
        string memory gender
    ) external validTIN(tin) {
        require(user != address(0), Errors.CANNOT_REGISTER_ADDRESS_ZERO());
        require(tinToAddress[tin] == address(0), Errors.TIN_ALREADY_EXISTS());
        require(individualProfiles[user].walletAddress == address(0), Errors.USER_EXISTS_ALREADY());
        require(businessProfiles[user].walletAddress == address(0), Errors.USER_EXISTS_ALREADY());


        Gender genderEnum;
        if (keccak256(abi.encodePacked(gender)) == keccak256(abi.encodePacked("male"))) {
            genderEnum = Gender.MALE;
        } else if (keccak256(abi.encodePacked(gender)) == keccak256(abi.encodePacked("female"))) {
            genderEnum = Gender.FEMALE;
        } else {
            revert Errors.INVALID_GENDER();
        }

        individualProfiles[user] = IndividualProfile({
          walletAddress: user,
          tin: tin,
          idNumber: idNumber,
          idType: idType,
          email: email,
          firstname: firstname,
          lastname: lastname,
          middlename: middlename,
          dob: dob,
          gender: genderEnum,
          isActive: true,
          registrationDate: block.timestamp,
          lastPaymentDate: 0
        });

        tinToAddress[tin] = user;
        addressToTin[user] = tin;

        _grantRole(TAX_PAYER_ROLE, user);

        emit Events.UserRegistered(user, tin, block.timestamp);
    }

    function registerBusiness(
        address user,
        string memory tin,
        string memory rcNumber,
        string memory companyName,
        string memory companyType,
        string memory registrationDate,
        string memory branchAddress,
        string memory companyEmail,
        string memory city,
        string memory classification,
        string memory headOfficeAddress,
        string memory lga,
        string memory affiliates,
        string memory shareCapital,
        string memory shareCapitalInWords,
        string memory state,
        bool isActive
    ) external validTIN(tin) {
        require(user != address(0), Errors.CANNOT_REGISTER_ADDRESS_ZERO());
        require(tinToAddress[tin] == address(0), Errors.TIN_ALREADY_EXISTS());
        require(businessProfiles[user].walletAddress == address(0), Errors.BUSINESS_EXISTS_ALREADY());
        require(individualProfiles[user].walletAddress == address(0), Errors.BUSINESS_EXISTS_ALREADY());


        businessProfiles[user] = BusinessProfile({
          walletAddress: user,
          tin: tin,
          rcNumber: rcNumber,
          companyName: companyName,
          companyType: companyType,
          companyEmail: companyEmail,
          businessRegistrationDate: registrationDate,
          branchAddress: branchAddress,
          city: city,
          classification: classification,
          headOfficeAddress: headOfficeAddress,
          lga: lga,
          affiliates: affiliates,
          shareCapital: shareCapital,
          shareCapitalInWords: shareCapitalInWords,
          state: state,
          isActive: isActive,
          taxRegistrationDate: block.timestamp,
          lastPaymentDate: 0
        });

        tinToAddress[tin] = user;
        addressToTin[user] = tin;

        _grantRole(TAX_PAYER_ROLE, user);

        emit Events.UserRegistered(user, tin, block.timestamp);
    }

    /**
     * @dev Create a new tax item
     * @param name Name of the tax item
     * @param description Description of the tax item
     * @param category Tax category (WHT, PAYE, VAT, etc.)
     * @param rate Tax rate in basis points (1% = 100)
     */
    function createTaxItem(
        string memory name,
        string memory description,
        TaxCategory category,
        uint256 rate
    ) external onlySubAdmin {
        _taxItemIds.increment();
        uint256 newItemId = _taxItemIds.current();

        require(bytes(name).length > 0, Errors.TAX_ITEM_NAME_CANNOT_BE_EMPTY());
        require(bytes(description).length > 0, Errors.TAX_ITEM_DESCRIPTION_CANNOT_BE_EMPTY());

        taxItems[newItemId] = TaxItem({
            itemId: newItemId,
            name: name,
            description: description,
            category: category,
            rate: rate,
            isActive: true,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        emit TaxItemCreated(newItemId, name, category, rate);
    }

    /**
     * @dev Update tax item status
     * @param itemId ID of the tax item to update
     * @param isActive New active status
     */
    function updateTaxItem(uint256 itemId, bool isActive) 
        external 
        onlySubAdmin 
        taxItemExists(itemId) 
    {
        taxItems[itemId].isActive = isActive;
        taxItems[itemId].updatedAt = block.timestamp;

        emit TaxItemUpdated(itemId, isActive, block.timestamp);
    }

    // TAX PAYER FUNCTIONS

    /**
     * @dev Record a tax payment (called by backend after payment processing)
     * @param payer Address of the taxpayer
     * @param tin Tax Identification Number
     * @param itemId ID of the tax item
     * @param amountPaid Amount paid in USDC (assuming 6 decimals)
     * @param paymentRef Payment reference from payment processor
     * @param receiptHash IPFS hash of the receipt
     */
    function recordTaxPayment(
        address payer,
        string memory tin,
        uint256 itemId,
        uint256 amountPaid,
        string memory paymentRef,
        string memory receiptHash
    ) external onlySubAdmin nonReentrant taxItemExists(itemId) taxItemActive(itemId) {
        require(tinToAddress[tin] == payer, Errors.TIN_AND_ADDRESS_MISMATCH(tin));
        require(amountPaid > 0, Errors.AMOUNT_MUST_BE_GREATER_THAN_ZERO(amountPaid));
        require(bytes(paymentRef).length > 0, Errors.PAYMENT_REFERENCE_REQUIRED());
        require(bytes(receiptHash).length > 0, Errors.RECEIPT_HASH_REQUIRED());

        _paymentRecordIds.increment();
        uint256 newRecordId = _paymentRecordIds.current();

        TaxItem memory item = taxItems[itemId];

        paymentRecords[newRecordId] = PaymentRecord({
            recordId: newRecordId,
            payer: payer,
            tin: tin,
            itemId: itemId,
            amountPaid: amountPaid,
            paymentRef: paymentRef,
            receiptHash: receiptHash,
            timestamp: block.timestamp,
            category: item.category
        });

        taxpayerPaymentHistory[payer].push(newRecordId);

        // Update last payment date for the appropriate profile
        if (individualProfiles[payer].walletAddress != address(0)) {
            individualProfiles[payer].lastPaymentDate = block.timestamp;
        } else if (businessProfiles[payer].walletAddress != address(0)) {
            businessProfiles[payer].lastPaymentDate = block.timestamp;
        }

        emit TaxPaid(
            newRecordId,
            payer,
            tin,
            itemId,
            amountPaid,
            paymentRef,
            receiptHash,
            block.timestamp
        );
    }

    // VIEW FUNCTIONS

    /**
     * @dev Get individual taxpayer profile
     * @param user Address of the taxpayer
     */
    function getIndividualProfile(address user) external view returns (IndividualProfile memory) {
        require(individualProfiles[user].walletAddress != address(0), Errors.INDIVIDUAL_PROFILE_NOT_FOUND(user));
        return individualProfiles[user];
    }

    /**
     * @dev Get business taxpayer profile
     * @param user Address of the taxpayer
     */
    function getBusinessProfile(address user) external view returns (BusinessProfile memory) {
        require(businessProfiles[user].walletAddress != address(0), Errors.BUSINESS_PROFILE_NOT_FOUND(user));
        return businessProfiles[user];
    }

    /**
     * @dev Get tax item details
     * @param itemId ID of the tax item
     */
    function getTaxItem(uint256 itemId) external view taxItemExists(itemId) returns (TaxItem memory) {
        return taxItems[itemId];
    }

    /**
     * @dev Get payment record
     * @param recordId ID of the payment record
     */
    function getPaymentRecord(uint256 recordId) external view returns (PaymentRecord memory) {
        require(paymentRecords[recordId].recordId != 0, Errors.PAYMENT_RECORD_NOT_FOUND(recordId));
        return paymentRecords[recordId];
    }

    /**
     * @dev Get taxpayer payment history
     * @param user Address of the taxpayer
     */
    function getTaxpayerPaymentHistory(address user) external view returns (uint256[] memory) {
        return taxpayerPaymentHistory[user];
    }

    /**
     * @dev Get all active tax items
     */
    function getActiveTaxItems() external view returns (TaxItem[] memory) {
        uint256 activeCount = 0;
        uint256 totalItems = _taxItemIds.current();

        // Count active items
        for (uint256 i = 1; i <= totalItems; i++) {
            if (taxItems[i].isActive) {
                activeCount++;
            }
        }

        // Create and populate array
        TaxItem[] memory activeItems = new TaxItem[](activeCount);
        uint256 currentIndex = 0;

        for (uint256 i = 1; i <= totalItems; i++) {
            if (taxItems[i].isActive) {
                activeItems[currentIndex] = taxItems[i];
                currentIndex++;
            }
        }

        return activeItems;
    }

    /**
     * @dev Check if address is registered taxpayer
     * @param user Address to check
     */
    function isRegisteredTaxpayer(address user) external view returns (bool) {
        return individualProfiles[user].walletAddress != address(0) || 
               businessProfiles[user].walletAddress != address(0);
    }

    /**
     * @dev Get total number of tax items
     */
    function getTotalTaxItems() external view returns (uint256) {
        return _taxItemIds.current();
    }

    /**
     * @dev Get total number of payment records
     */
    function getTotalPaymentRecords() external view returns (uint256) {
        return _paymentRecordIds.current();
    }

    /**
     * @dev Get profile type (individual or business)
     * @param user Address to check
     */
    function getProfileType(address user) external view returns (string memory) {
        if (individualProfiles[user].walletAddress != address(0)) {
            return "individual";
        } else if (businessProfiles[user].walletAddress != address(0)) {
            return "business";
        } else {
            return "none";
        }
    }

    // UTILITY FUNCTIONS

    /**
     * @dev Convert basis points to percentage
     * @param basisPoints Rate in basis points
     */
    function basisPointsToPercentage(uint256 basisPoints) external pure returns (uint256) {
        return basisPoints / 100;
    }

    /**
     * @dev Calculate tax amount
     * @param amount Base amount
     * @param basisPoints Tax rate in basis points
     */
    function calculateTaxAmount(uint256 amount, uint256 basisPoints) external pure returns (uint256) {
        return (amount * basisPoints) / 10000;
    }
}