import { ethers } from 'hardhat'

import { CreditService, DebitService, type Manager } from '../typechain-types'
import { DEFAULT_MANAGER_CAP, DEFAULT_MANAGER_CAPACITY, GOVERNANCE } from './config'
import { tokens } from './tokens'
import { type Address, MinimalToken } from './types'

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
  let address: Address
  const previousVaultAddress = (await manager.vaults(token)) as Address
  // if the address is not zero, it already has been created
  const isAlreadyCreated = previousVaultAddress !== ethers.constants.AddressZero
  if (isAlreadyCreated) {
    console.error(`***Warning: The vault for token ${token} is already created by this manager ${manager.address}`)
    address = previousVaultAddress
  } else {
    await manager.create(token)
    address = (await manager.vaults(token)) as Address
    console.log(`Created a vault for this token: ${token}`)
  }

  return address
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

interface ConfigDebitServiceProps {
  manager: Manager
  service: DebitService
  serviceTokens?: MinimalToken[]
  governance?: Address
  capacity?: bigint
  cap?: bigint
  isWhitelistEnabled?: boolean
}

export const configDebitService = async ({
  manager,
  service,
  serviceTokens = tokens,
  governance = GOVERNANCE,
  capacity = DEFAULT_MANAGER_CAPACITY,
  cap = DEFAULT_MANAGER_CAP,
  isWhitelistEnabled = false,
}: ConfigDebitServiceProps) => {
  await Promise.all(
    serviceTokens.map(async (token) => await manager.setCap(service.address, token.tokenAddress, capacity, cap)),
  )
  console.log(`Set capacity for ${serviceTokens.length} tokens for this service: ${service.address}`)

  await serviceToggleWhitelist(service, isWhitelistEnabled)
  console.log(`changed whitelist state to ${isWhitelistEnabled ? 'ON' : 'OFF'} on this service: ${service.address}`)

  await service.transferOwnership(governance)
  console.log(`transferred this service: ${service.address} ownership to ${governance}`)
}

interface ConfigCreditServiceProps {
  manager: Manager
  service: CreditService
  serviceTokens?: MinimalToken[]
  governance?: Address
  capacity?: bigint
  cap?: bigint
}
export const configCreditService = async ({
  manager,
  service,
  serviceTokens = tokens,
  governance = GOVERNANCE,
  capacity = DEFAULT_MANAGER_CAPACITY,
  cap = DEFAULT_MANAGER_CAP,
}: ConfigCreditServiceProps) => {
  await Promise.all(
    serviceTokens.map(async (token) => await manager.setCap(service.address, token.tokenAddress, capacity, cap)),
  )
  console.log(`Set capacity for ${serviceTokens.length} tokens for this service: ${service.address}`)

  await service.transferOwnership(governance)
  console.log(`transferred aaveService ownership to ${governance}`)
}
