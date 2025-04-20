const DAOCore = artifacts.require("DAOCore");
const DAOFactory = artifacts.require("DAOFactory");
const ForgeToken = artifacts.require("ForgeToken");
const Governance = artifacts.require("Governance");
const Treasury = artifacts.require("Treasury");

module.exports = async function (deployer) {
  await deployer.deploy(DAOCore);
  const daoCore = await DAOCore.deployed();

  await deployer.deploy(Governance);
  const governance = await Governance.deployed();

  await deployer.deploy(Treasury);
  const treasury = await Treasury.deployed();

  await deployer.deploy(ForgeToken);
  const forgeToken = await ForgeToken.deployed();

  await deployer.deploy(DAOFactory);
  const daoFactory = await DAOFactory.deployed();

  // Add templates to factory
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
  // const [deployer] = await ethers.getSigners(); // This line is not needed in Truffle
  const accounts = await web3.eth.getAccounts(); // Get accounts in Truffle
  await daoFactory.createDAO(
    0,
    "My DAO",
    forgeToken.address,
    604800, // 1 week voting period
    51, // 51% quorum
    web3.utils.toWei("1000", "ether"), // 1000 tokens to create proposal
    [accounts[0], accounts[0]], // Initial members
    [0, 0] // Member roles
  );
};
