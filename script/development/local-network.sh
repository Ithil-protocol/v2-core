#/bin/bash
set -e

if [[ " $@ " =~ " --help " ]]; then
  echo "Usage: ./local-network.sh [--clean]"
  echo "                                   "
  echo "       --clean: clean up the local network state. starts network from scratch"
  exit 0
fi

if [[ " $@ " =~ " --clean " ]]; then
  rm devnetwork.state || true
fi

anvil \
  -f https://arb-mainnet.g.alchemy.com/v2/it4Um4ecMPP87zNShCGV2GhoFJvxulF8 \
  --fork-block-number 69410517 \
  --chain-id 1337 \
  --state devnetwork.state
