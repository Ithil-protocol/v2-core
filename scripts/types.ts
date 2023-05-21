export type Address = `0x${string}`

// the minimal intersection of LendingToken and ServiceAsset
export interface MinimalToken {
  name: string
  coingeckoId: string
  iconName: string
  decimals: number
  tokenAddress: Address
}

export interface LendingToken extends MinimalToken {
  vaultAddress: Address
}
