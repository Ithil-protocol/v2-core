import { ethers } from 'hardhat'

import type { AaveService, BalancerService, CreditService, GmxService, Manager } from '../typechain-types'
import { DEFAULT_MANAGER_CAP, DEFAULT_MANAGER_CAPACITY, GOVERNANCE } from './config'
import { tokens } from './tokens'
import type { Address, MinimalToken } from './types'

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

// Configuration

export const serviceToggleWhitelist = async (service: any, value: boolean) => {
  const isWhitelistEnabled = await service.enabled()

  if (isWhitelistEnabled === value) return
  await service.toggleWhitelistFlag()
}

interface ConfigDebitServiceProps {
  manager: Manager
  service: AaveService | GmxService | BalancerService
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

  for (const token of serviceTokens) {
    try {
      await service.setRiskParams(token.tokenAddress, BigInt(3e15), BigInt(1e16), BigInt(3 * 86400))
    } catch (error) {
      console.error(`Failed to set risk params for token: ${token.tokenAddress}`, error)
    }
  }

  console.log(`Set Risk for ${serviceTokens.length} tokens for this service: ${service.address}`)

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
  console.log(`transferred this service: ${service.address} ownership to ${governance}`)
}
