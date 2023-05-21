import { ethers } from 'hardhat'

import { type Manager } from '../typechain-types'
import { type Address } from './types'

export const deployManager = async () => {
  const Manager = await ethers.getContractFactory('Manager')
  const manager = await Manager.deploy()

  await manager.deployed()
  return manager
}

export const createVault = async (manager: Manager, token: Address) => {
  await manager.create(token)
  const address = await manager.vaults(token)
  return address as Address
}
