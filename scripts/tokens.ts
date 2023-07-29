import { type AcceptedAsset, type MinimalToken } from './types'

export const tokens: MinimalToken[] = [
  {
    name: 'USDC',
    coingeckoId: 'usd-coin',
    iconName: 'usdc',
    decimals: 6,
    tokenAddress: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
    oracleAddress: '0x50834f3163758fcc1df9973b6e91f0f0f0434ad3',
    initialPriceForIthil: '400000',
    vaultAddress: '0x',
    callOptionAddress: '0x',
  },
  {
    name: 'USDT',
    coingeckoId: 'tether',
    iconName: 'usdt',
    decimals: 6,
    tokenAddress: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
    oracleAddress: '0x3f3f5df88dc9f13eac63df89ec16ef6e7e25dde7',
    initialPriceForIthil: '400000',
    vaultAddress: '0x',
    callOptionAddress: '0x',
  },
  {
    name: 'WETH',
    coingeckoId: 'ethereum',
    iconName: 'eth',
    decimals: 18,
    tokenAddress: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    oracleAddress: '0x639fe6ab55c921f74e7fac1ee960c0b6293ba612',
    initialPriceForIthil: '220000000000000',
    vaultAddress: '0x',
    callOptionAddress: '0x',
  },
  {
    name: 'WBTC',
    coingeckoId: 'btc',
    iconName: 'btc',
    decimals: 8,
    tokenAddress: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
    oracleAddress: '0xd0c7101eacbb49f3decccc166d238410d6d46d57',
    initialPriceForIthil: '1363',
    vaultAddress: '0x',
    callOptionAddress: '0x',
  },
]

export const tokenMap = Object.fromEntries(tokens.map((token) => [token.name, token])) as Record<
  AcceptedAsset,
  MinimalToken
>
