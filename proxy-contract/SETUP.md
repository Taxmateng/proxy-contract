# Taxmate Project Setup Guide

## Project Overview

Taxmate is a decentralized tax payment system built on Base chain using upgradeable smart contracts with Hardhat 3. This project implements a comprehensive tax management system with role-based access control, taxpayer registration, and payment tracking.

## Prerequisites

### System Requirements
- **Node.js**: Version 18 or higher
- **npm**: Version 8 or higher
- **Git**: For version control
- **Hardhat**: Ethereum development environment

### Recommended Development Environment
- **VS Code** with Solidity extension
- **Git** for version control
- **MetaMask** for testing

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/Taxmateng/proxy-contract.git
cd proxy-contract
```

### 2. Install Dependencies

```bash
npm install
```

### 3. Environment Setup

Create a `.env` file in the root directory:

```env
# Network URLs
MAINNET_RPC_URL=your_mainnet_rpc_url
SEPOLIA_RPC_URL=your_sepolia_rpc_url
BASE_MAINNET_RPC_URL=your_base_mainnet_rpc_url
BASE_SEPOLIA_RPC_URL=your_base_sepolia_rpc_url

# Private Keys (for testing - use test accounts only)
PRIVATE_KEY=your_test_private_key
SUPER_ADMIN_PRIVATE_KEY=your_super_admin_private_key

# API Keys (optional)
ETHERSCAN_API_KEY=your_etherscan_api_key
BASESCAN_API_KEY=your_basescan_api_key
COINMARKETCAP_API_KEY=your_coinmarketcap_api_key

# Deployment Configuration
SUPER_ADMIN_ADDRESS=0xYourSuperAdminAddress
```

### 4. Verify Installation

```bash
npx hardhat --version
npx hardhat compile
```

## Project Structure

```
proxy-contract/
├── contracts/
│   ├── Taxmate.sol                 # Main contract
│   └── lib/
│       ├── Errors.sol              # Custom error library
│       ├── Events.sol              # Event definitions
│       └── TaxTypes.sol            # Enums and data types
├── scripts/
│   ├── deploy.js                   # Deployment script
│   └── upgrade.js                  # Upgrade script
├── test/
│   ├── Deployment.t.sol            # Deployment tests
│   ├── Registration.t.sol          # Registration tests
│   ├── TaxItem.t.sol               # Tax item tests
│   ├── TaxPayment.t.sol            # Payment tests
│   └── GetterFunctions.t.sol       # View function tests
├── hardhat.config.js               # Hardhat configuration
└── package.json                    # Dependencies
```

## Configuration

### Hardhat Configuration (hardhat.config.js)

The project is configured for multiple networks:

```javascript
module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {
      chainId: 1337
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 1337
    },
    base_sepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 84532
    },
    base_mainnet: {
      url: process.env.BASE_MAINNET_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 8453
    }
  },
  etherscan: {
    apiKey: {
      base_sepolia: process.env.BASESCAN_API_KEY || "",
      base: process.env.BASESCAN_API_KEY || ""
    }
  }
};
```

## Development Workflow

### 1. Local Development

Start a local Hardhat node:

```bash
npx hardhat node
```

In a separate terminal, deploy to local network:

```bash
npx hardhat run scripts/deploy.js --network localhost
```

### 2. Running Tests

Run all tests:

```bash
npx hardhat test
```

Run specific test suites:

```bash
npx hardhat test --grep "Deployment"
npx hardhat test --grep "Registration"
npx hardhat test --grep "TaxItem"
npx hardhat test --grep "TaxPayment"
```

Run tests with gas reporting:

```bash
npx hardhat test --gas
```

Run tests with detailed output:

```bash
npx hardhat test -vvv
```

### 3. Code Coverage

```bash
npx hardhat coverage
```

### 4. Code Linting

```bash
npm run lint
```

## Deployment

### 1. Local Deployment

```bash
npx hardhat run scripts/deploy.js --network localhost
```

### 2. Testnet Deployment (Base Sepolia)

```bash
npx hardhat run scripts/deploy.js --network base_sepolia
```

### 3. Mainnet Deployment (Base Mainnet)

```bash
npx hardhat run scripts/deploy.js --network base_mainnet
```

### Deployment Script Details

The deployment script handles:
- Implementation contract deployment
- Proxy contract deployment
- Initialization with super admin
- Verification of setup

## Contract Verification

### 1. Verify on Basescan

```bash
npx hardhat verify --network base_sepolia <CONTRACT_ADDRESS> <SUPER_ADMIN_ADDRESS>
```

### 2. Verify with Constructor Arguments

```bash
npx hardhat verify --network base_sepolia <CONTRACT_ADDRESS> --constructor-args arguments.js
```

## Key Features

### 1. Upgradeable Contract Architecture
- UUPS proxy pattern
- Gas-efficient upgrades
- Data preservation during upgrades

### 2. Role-Based Access Control
- SUPER_ADMIN_ROLE: Full system control
- SUB_ADMIN_ROLE: Operational management
- TAX_PAYER_ROLE: Automatic assignment

### 3. Taxpayer Management
- Individual and business registration
- TIN (Tax Identification Number) system
- Profile management

### 4. Tax Item Management
- Flexible tax categories
- Rate management in basis points
- Active/inactive status control

### 5. Payment System
- Secure payment recording
- Receipt hash storage (IPFS)
- Payment history tracking

## Testing Strategy

### Test Categories

1. **Deployment Tests**
   - Contract initialization
   - Role setup
   - Upgrade functionality

2. **Registration Tests**
   - Individual taxpayer registration
   - Business registration
   - Error handling

3. **Tax Item Tests**
   - Tax item creation
   - Status updates
   - Access control

4. **Payment Tests**
   - Payment recording
   - Security measures
   - Data integrity

5. **Getter Tests**
   - View function testing
   - Data retrieval
   - Edge cases

### Running Specific Tests

```bash
# Run only deployment tests
npx hardhat test --grep "DeploymentTest"

# Run with gas reporting
REPORT_GAS=true npx hardhat test

# Run with detailed traces
npx hardhat test --verbose
```

## Security Considerations

### 1. Access Control
- All sensitive functions are protected with role-based access
- Super admin has exclusive upgrade rights
- Automatic role assignment for taxpayers

### 2. Input Validation
- Comprehensive parameter validation
- Custom error messages for gas efficiency
- Reentrancy protection

### 3. Upgrade Safety
- Only super admin can authorize upgrades
- Storage layout compatibility checks
- Comprehensive upgrade testing

## Common Commands Reference

### Development
```bash
npx hardhat compile          # Compile contracts
npx hardhat clean           # Clean artifacts
npx hardhat node           # Start local node
npx hardhat console        # Interactive console
```

### Testing
```bash
npx hardhat test           # Run all tests
npx hardhat test --grep "pattern"  # Run specific tests
npx hardhat coverage       # Generate coverage report
```

### Deployment
```bash
npx hardhat run scripts/deploy.js --network localhost
npx hardhat run scripts/deploy.js --network base_sepolia
npx hardhat run scripts/deploy.js --network base_mainnet
```

### Verification
```bash
npx hardhat verify --network base_sepolia <address> <args>
```

## Troubleshooting

### Common Issues

1. **Compilation Errors**
   - Ensure Node.js version 18+
   - Run `npm install` to update dependencies
   - Check Solidity version compatibility

2. **Test Failures**
   - Verify .env file configuration
   - Check network connectivity for testnets
   - Ensure sufficient test ETH on testnet

3. **Deployment Issues**
   - Verify RPC URL in .env file
   - Check private key format
   - Ensure sufficient gas funds

4. **Verification Issues**
   - Confirm constructor arguments
   - Check network configuration
   - Verify API keys

### Getting Help

1. Check the project issues on GitHub
2. Review Hardhat documentation
3. Check test cases for usage examples
4. Verify environment configuration

## Contributing

### Development Process

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

### Code Standards

- Follow Solidity style guide
- Write comprehensive tests
- Include NatSpec comments
- Update documentation

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support and questions:
- Create an issue on GitHub
- Check existing documentation
- Review test cases for usage examples

---

**Note**: This project uses upgradeable contracts. Always test upgrades on testnets before mainnet deployment and ensure proper access control measures are in place.