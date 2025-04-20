const { ethers } = require("hardhat");

async function main() {
  // Deploy DAOCore Implementation
  const DAOCore = await ethers.getContractFactory("DAOCore");
  const daoCore = await DAOCore.deploy();
  await daoCore.deployed();
  console.log("DAOCore Implementation deployed to:", daoCore.address);

  // Deploy Governance Implementation
  const Governance = await ethers.getContractFactory("Governance");
  const governance = await Governance.deploy();
  await governance.deployed();
  console.log("Governance Implementation deployed to:", governance.address);

  // Deploy Treasury Implementation
  const Treasury = await ethers.getContractFactory("Treasury");
  const treasury = await Treasury.deploy();
  await treasury.deployed();
  console.log("Treasury Implementation deployed to:", treasury.address);

  // Deploy ForgeToken
  const ForgeToken = await ethers.getContractFactory("ForgeToken");
  const forgeToken = await ForgeToken.deploy();
  await forgeToken.deployed();
  console.log("ForgeToken deployed to:", forgeToken.address);

  // Deploy DAOFactory
  const DAOFactory = await ethers.getContractFactory("DAOFactory");
  const daoFactory = await DAOFactory.deploy();
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
