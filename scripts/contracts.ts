import { ethers } from 'hardhat'

import { type AaveService, type Manager } from '../typechain-types'
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

// Aave

export const deployAave = async (manager: Manager, aavePool: Address) => {
  const AaveService = await ethers.getContractFactory('AaveService')
  const oneMonth = 3600n * 24n * 30n // 30 days expressed in seconds
  const aaveService = await AaveService.deploy(manager.address, aavePool, oneMonth)

  await aaveService.deployed()
  return aaveService
}

export const aaveSetCapacity = async (
  manager: Manager,
  aaveService: AaveService,
  token: Address,
  capacity: bigint = 10n ** 18n,
) => {
  await manager.setCap(aaveService.address, token, capacity)
}

export const aaveToggleWhitelist = async (aaveService: AaveService, value: boolean) => {
  const isWhitelistEnabled = await aaveService.enabled()

  if (isWhitelistEnabled === value) return
  await aaveService.toggleWhitelistFlag()
}

// GMX

export const deployGmx = async (manager: Manager, gmxRouter: Address, gmxRouterV2: Address) => {
  const GmxService = await ethers.getContractFactory('GmxService')
  const oneMonth = 3600n * 24n * 30n // 30 days expressed in seconds
  const gmxService = await GmxService.deploy(manager.address, gmxRouter, gmxRouterV2, oneMonth)

  await gmxService.deployed()
  return gmxService
}

export const setCapacity = async (
  manager: Manager,
  address: string,
  token: Address,
  capacity: bigint = 10n ** 18n,
  cap: bigint = 10n ** 36n,
) => {
  await manager.setCap(address, token, capacity, cap)
}

export const serviceToggleWhitelist = async (service: any, value: boolean) => {
  const isWhitelistEnabled = await service.enabled()

  if (isWhitelistEnabled === value) return
  await service.toggleWhitelistFlag()
}
