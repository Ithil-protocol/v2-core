import { writeFileSync } from 'fs'

import { createVault, deployManager } from './contracts'
import { tokens } from './tokens'
import { type LendingToken } from './types'

const main = async () => {
  const manager = await deployManager()
  console.log(`Manager contract deployed to ${manager.address}`)

  const vaults = await Promise.all(
    tokens.map(async (token): Promise<LendingToken> => {
      const vaultAddress = await createVault(manager, token.tokenAddress)
      return { ...token, vaultAddress }
    }),
  )

  writeFileSync('manager-address.json', JSON.stringify({ manager: manager.address }, null, 2))
  writeFileSync('vaults.json', JSON.stringify(vaults, null, 2))

  console.log(`Wrote file vaults.json containing ${vaults.length} vaults`)
  console.log('Wrote file manager-address.json containing the manager address')
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
if (require.main === module) {
  // Script invoked directly
  void main().catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}
