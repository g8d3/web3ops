const { ethers } = require("ethers");
const fs = require("fs");

async function main() {
  // Read contract ABIs and bytecodes
  const DAOCoreABI = JSON.parse(fs.readFileSync("artifacts/DAOCore.json")).abi;
  const DAOCoreBytecode = fs.readFileSync("artifacts/DAOCore.json").bytecode;

  const GovernanceABI = JSON.parse(fs.readFileSync("artifacts/Governance.json")).abi;
  const GovernanceBytecode = fs.readFileSync("artifacts/Governance.json").bytecode;

  const TreasuryABI = JSON.parse(fs.readFileSync("artifacts/Treasury.json")).abi;
  const TreasuryBytecode = fs.readFileSync("artifacts/Treasury.json").bytecode;

  const ForgeTokenABI = JSON.parse(fs.readFileSync("artifacts/ForgeToken.json")).abi;
  const ForgeTokenBytecode = fs.readFileSync("artifacts/ForgeToken.json").bytecode;

  const DAOFactoryABI = JSON.parse(fs.readFileSync("artifacts/DAOFactory.json")).abi;
  const DAOFactoryBytecode = fs.readFileSync("artifacts/DAOFactory.json").bytecode;

  // Set up provider and signer
  const provider = new ethers.providers.JsonRpcProvider("http://localhost:8545"); // Replace with your provider URL
  const signer = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4cdb30563e7c3cfbf5f118a056330b71ca4aa246", provider); // Replace with your private key

  // Deploy DAOCore Implementation
  const DAOCoreFactory = new ethers.ContractFactory(DAOCoreABI, DAOCoreBytecode, signer);
  const daoCore = await DAOCoreFactory.deploy();
  await daoCore.deployed();
  console.log("DAOCore Implementation deployed to:", daoCore.address);

  // Deploy Governance Implementation
  const GovernanceFactory = new ethers.ContractFactory(GovernanceABI, GovernanceBytecode, signer);
  const governance = await GovernanceFactory.deploy();
  await governance.deployed();
  console.log("Governance Implementation deployed to:", governance.address);

  // Deploy Treasury Implementation
  const TreasuryFactory = new ethers.ContractFactory(TreasuryABI, TreasuryBytecode, signer);
  const treasury = await TreasuryFactory.deploy();
  await treasury.deployed();
  console.log("Treasury Implementation deployed to:", treasury.address);

  // Deploy ForgeToken
  const ForgeTokenFactory = new ethers.ContractFactory(ForgeTokenABI, ForgeTokenBytecode, signer);
  const forgeToken = await ForgeTokenFactory.deploy();
  await forgeToken.deployed();
  console.log("ForgeToken deployed to:", forgeToken.address);

  // Deploy DAOFactory
  const DAOFactoryFactory = new ethers.ContractFactory(DAOFactoryABI, DAOFactoryBytecode, signer);
  const daoFactory = await DAOFactoryFactory.deploy();
  await daoFactory.deployed();
  console.log("DAOFactory deployed to:", daoFactory.address);

  // Add Templates to Factory
  // Replace with actual addresses
  console.log("Adding templates to DAOFactory...");
  await daoFactory.addTemplate(
    0,
    "Investment DAO",
    "Template for investment DAOs",
    daoCore.address,
    governance.address,
    treasury.address
  );
  await daoFactory.addTemplate(
    1,
    "Service DAO",
    "Template for service DAOs",
    daoCore.address,
    governance.address,
    treasury.address
  );
  await daoFactory.addTemplate(
    2,
    "Social DAO",
    "Template for social DAOs",
    daoCore.address,
    governance.address,
    treasury.address
  );
  await daoFactory.addTemplate(
    3,
    "Protocol DAO",
    "Template for protocol DAOs",
    daoCore.address,
    governance.address,
    treasury.address
  );

  // Create a DAO
  // Replace with actual parameters
  console.log("Creating a DAO...");
  const [deployer] = await ethers.getSigners();
  await daoFactory.createDAO(
    0,
    "My DAO",
    forgeToken.address,
    604800, // 1 week voting period
    51, // 51% quorum
    ethers.utils.parseEther("1000"), // 1000 tokens to create proposal
    [deployer.address, deployer.address], // Initial members
    [0, 0] // Member roles
  );

  console.log("Deployment script complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
