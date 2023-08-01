import { getDataDir, getFrontendDir, getJsonProperty } from './command-helpers'

export const WETH = '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1'
export const AAVE_POOL_ON_ARBITRUM = '0x794a61358D6845594F94dc1DB02A252b5b4814aD'
export const GMX_ROUTER = '0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1'
export const GMX_ROUTER_V2 = '0xB95DB5B167D75e6d04227CfFFA61069348d271F5'
export const WIZARDEX = '0xa05B704E88D43260F71861BB69C1851Fe77b63fD'
export const GOVERNANCE = '0x7778f7b568023379697451da178326D27682ADb8'

export const oneMonth = 3600n * 24n * 30n // 30 days expressed in seconds
export const oneDay = 24n * 60n * 60n // in seconds
export const oneHour = 3600n // in seconds
export const oneMinute = 60n // in seconds
export const oneSecond = 1n // in seconds

export const DEFAULT_MANAGER_CAPACITY = 10n ** 18n
export const DEFAULT_MANAGER_CAP = 10n ** 36n

export const contractJsonDir = getDataDir('contracts.json')
export const frontendContractJsonDir = getFrontendDir('contracts.json')
export const vaultsJsonDir = getDataDir('assets.json')
export const frontendVaultsJsonDir = getFrontendDir('assets.json')
export const currentAaveServiceAddress = getJsonProperty(contractJsonDir, 'aaveService')
export const currentGmxServiceAddress = getJsonProperty(contractJsonDir, 'gmxService')
export const currentIthilAddress = getJsonProperty(contractJsonDir, 'ithil')
export const currentManagerAddress = getJsonProperty(contractJsonDir, 'manager')
export const currentOracleAddress = getJsonProperty(contractJsonDir, 'oracle')
export const currentFeeCollectorServiceAddress = getJsonProperty(contractJsonDir, 'feeCollectorService')
export const currentFixedYieldServiceAddress = getJsonProperty(contractJsonDir, 'fixedYieldService')

export const valueNumbers = {
  MILLION: 1000000n,
  THOUSAND: 1000n,
  HUNDRED: 100n,
  TEN: 10n,
}
