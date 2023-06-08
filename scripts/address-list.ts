import { type Address } from './types'

export const accountsPrivates = [
  '0x3ac07c9999a7876def6cb8efc762c38f022d95b19ef831ca7e57f6f3309e5eaf',
  '0xccb16f429788e18b295c4175f1bc77da077c1790b153b6c86b16fb845bf308d4',
  '0x02b24c18e5e904e0a83d41d5ac8ec177d6072be4870f2c707005f1f0875f6ca5',
]

export const privateKeyToAddress: Record<string, Address> = {
  '0x3ac07c9999a7876def6cb8efc762c38f022d95b19ef831ca7e57f6f3309e5eaf': '0x7778f7b568023379697451da178326D27682ADb8',
  '0xccb16f429788e18b295c4175f1bc77da077c1790b153b6c86b16fb845bf308d4': '0xed7E824e52858de72208c5b9834c18273Ebb9D3b',
  '0x02b24c18e5e904e0a83d41d5ac8ec177d6072be4870f2c707005f1f0875f6ca5': '0x7Ce7DdE0b26a4ABe2fBBCF5c0ff9785dbFB9A72c',
}

export const depositorList: Array<{ privateKey: string; address: Address }> = [
  {
    privateKey: accountsPrivates[2],
    address: privateKeyToAddress[accountsPrivates[2]],
  },
]

export const faucetList: Address[] = [
  // these addresses are from test seed phrase
  '0x7778f7b568023379697451da178326D27682ADb8',
  '0xed7E824e52858de72208c5b9834c18273Ebb9D3b',
  '0x7Ce7DdE0b26a4ABe2fBBCF5c0ff9785dbFB9A72c',
]
