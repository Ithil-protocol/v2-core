import { ethers } from 'hardhat'

import { type Manager } from '../typechain-types'
import { type Address } from './types'

export const deployIthil = async (governance: Address) => {
  const Ithil = await ethers.getContractFactory('Ithil')
  const ithil = await Ithil.deploy(governance)

  await ithil.deployed()
  return ithil
}

export const deployOracle = async () => {
  const PriceConverter = await ethers.getContractFactory('PriceConverter')

  const priceConverter = await PriceConverter.deploy()

  await priceConverter.deployed()
  const Oracle = await ethers.getContractFactory('Oracle', {
    libraries: { PriceConverter: priceConverter.address },
  })
  const oracle = await Oracle.deploy()

  await oracle.deployed()
  return oracle
}

export const createVault = async (manager: Manager, token: Address) => {
  await manager.create(token)
  const address = await manager.vaults(token)
  return address as Address
}

export const deployAave = async (manager: Manager, aavePool: Address) => {
  const AaveService = await ethers.getContractFactory('AaveService')
  const oneMonth = 3600n * 24n * 30n // 30 days expressed in seconds
  const aaveService = await AaveService.deploy(manager.address, aavePool, oneMonth)

  await aaveService.deployed()
  return aaveService
}

export const deployGmx = async (manager: Manager, gmxRouter: Address, gmxRouterV2: Address) => {
  const GmxService = await ethers.getContractFactory('GmxService')
  const oneMonth = 3600n * 24n * 30n // 30 days expressed in seconds
  const gmxService = await GmxService.deploy(manager.address, gmxRouter, gmxRouterV2, oneMonth)

  await gmxService.deployed()
  return gmxService
}

export const deployFeeCollectorService = async (
  manager: Manager,
  weth: Address,
  feePercentage: bigint,
  oracle: string,
  dex: Address,
) => {
  const FeeCollectorService = await ethers.getContractFactory('FeeCollectorService')
  const feeCollectorService = await FeeCollectorService.deploy(manager.address, weth, feePercentage, oracle, dex)

  await feeCollectorService.deployed()
  return feeCollectorService
}

export const deployCallOptionService = async (
  manager: Manager,
  treasury: Address,
  ithil: string,
  initialPrice: bigint,
  halvingTime: number,
  underlying: Address,
) => {
  const SeniorCallOption = await ethers.getContractFactory('SeniorCallOption')

  const seniorCallOption = await SeniorCallOption.deploy(
    manager.address,
    treasury,
    ithil,
    initialPrice,
    halvingTime,
    underlying,
    { gasLimit: 50_000_000 },
  )

  await seniorCallOption.deployed()
  return seniorCallOption
}

export const deploySeniorFixedYieldService = async (
  name: string,
  symbol: string,
  manager: Manager,
  yieldNumber: bigint,
  deadline: number,
) => {
  const SeniorFixedYieldService = await ethers.getContractFactory('SeniorFixedYieldService')
  const seniorFixedYieldService = await SeniorFixedYieldService.deploy(
    name,
    symbol,
    manager.address,
    yieldNumber,
    deadline,
  )

  await seniorFixedYieldService.deployed()
  return seniorFixedYieldService
}

// Configuration

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
