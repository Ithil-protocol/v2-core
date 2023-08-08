import axios from 'axios'
import * as dotenv from 'dotenv'

dotenv.config({ path: '.env.hardhat' })

const { TENDERLY_USER, TENDERLY_PROJECT, TENDERLY_ACCESS_KEY } = process.env

const TENDERLY_FORK_API = `https://api.tenderly.co/api/v1/account/${TENDERLY_USER!}/project/${TENDERLY_PROJECT!}/fork`
const body = {
  network_id: '42161', // network you wish to fork
  block_number: 116901153,
  chain_config: {
    chain_id: 54789, // chain_id used in the forked environment
  },
}

const getFork = async () => {
  const resp = await axios.post(TENDERLY_FORK_API, body, {
    headers: { 'X-Access-Key': TENDERLY_ACCESS_KEY!, 'Content-Type': 'application/json' },
  })

  return resp
}
getFork()
  .then((res) => console.log(res))
  .catch((err) => console.log(err))
