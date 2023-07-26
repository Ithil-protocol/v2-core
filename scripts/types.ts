export type Address = `0x${string}`

export type AcceptedAsset = 'USDC' | 'USDT' | 'DAI' | 'WETH' | 'WBTC'
// the minimal intersection of LendingToken and ServiceAsset
export interface MinimalToken {
  name: AcceptedAsset
  coingeckoId: string
  iconName: string
  decimals: number
  tokenAddress: Address
  oracleAddress: Address
}

export interface LendingToken extends MinimalToken {
  vaultAddress: Address
}

export interface Replacement {
  slot: number
  from: number
  to: number
  value: string
}

export type JsonObject = Record<string, any>
