#/bin/bash
set -e

if [[ " $@ " =~ " --help " ]]; then
  echo "Usage: ./local-network.sh [--setup]"
  echo "                                   "
  echo "       --setup: setup the local network state. starts network from scratch and deploys contracts"
  exit 0
fi

if [[ " $@ " =~ " --setup " ]]; then
  rm -f devnetwork.state
  killall anvil || true

  anvil \
    -f https://arb-mainnet.g.alchemy.com/v2/it4Um4ecMPP87zNShCGV2GhoFJvxulF8 \
    --fork-block-number 69410517 \
    --state devnetwork.state &
  NETWORK_PID=$!
  echo "Waiting 5 seconds..."
  sleep 5
  bash lending-page.sh
  bash strategy-page.sh
  echo "Waiting 1 second..."
  sleep 1
  kill -SIGINT $NETWORK_PID
fi

anvil \
  -f https://arb-mainnet.g.alchemy.com/v2/it4Um4ecMPP87zNShCGV2GhoFJvxulF8 \
  --chain-id 1337 \
  --state devnetwork.state
