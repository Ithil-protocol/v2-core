import { resolve } from 'path'

export const getFrontendDir = () => {
  const { FRONTEND_PATH } = process.env
  const projectDir = resolve(__dirname, '..')
  let frontendDir: null | string = null
  if (FRONTEND_PATH == null || FRONTEND_PATH.length === 0) {
    console.warn('No FRONTEND_PATH found in .env.hardhat, will not produce JSON files')
  } else {
    frontendDir = resolve(projectDir, FRONTEND_PATH)
  }

  return frontendDir
}

export const promiseDelay = async (ms: number) => await new Promise((resolve) => setTimeout(resolve, ms))
