import { deployManager } from '../contracts'

async function deployManagerContract() {
  const manager = await deployManager()
  console.log(`Manager contract deployed to ${manager.address}`)
}

// Use if (require.main === module) to check if the file is the main entry point
if (require.main === module) {
  // If it's the main entry point, execute the deployManagerContract function
  void deployManagerContract().catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}

export { deployManagerContract }
