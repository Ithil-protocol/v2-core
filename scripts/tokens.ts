import { type AcceptedAsset, type MinimalToken } from './types'

export const tokens: MinimalToken[] = [
  {
    name: 'USDC',
    coingeckoId: 'usd-coin',
    iconName: 'usdc',
    decimals: 6,
    tokenAddress: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
  },
  {
    name: 'USDT',
    coingeckoId: 'tether',
    iconName: 'usdt',
    decimals: 6,
    tokenAddress: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
  },
  {
    name: 'WETH',
    coingeckoId: 'ethereum',
    iconName: 'eth',
    decimals: 18,
    tokenAddress: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
  },
  {
    name: 'WBTC',
    coingeckoId: 'btc',
    iconName: 'btc',
    decimals: 8,
    tokenAddress: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
  },
]

export const tokenMap = Object.fromEntries(tokens.map((token) => [token.name, token])) as Record<
  AcceptedAsset,
  MinimalToken
>
