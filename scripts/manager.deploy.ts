import { ethers } from 'hardhat'

const main = async () => {
  const Manager = await ethers.getContractFactory("Manager");
  const manager = await Manager.deploy();

  await manager.deployed();

  console.log(
    `Manager contract deployed to ${manager.address}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
