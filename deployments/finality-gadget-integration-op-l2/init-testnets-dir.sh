#!/bin/bash
set -euo pipefail

# Only run if .testnets directory does not exist
if [ ! -d ".testnets" ]; then
  # Create new directory that will hold node and services' configuration
  mkdir -p .testnets && chmod -R 777 .testnets

  if [[ "$BITCOIN_NETWORK" == "regtest" ]]; then
    FINALIZATION_TIMEOUT=2
    CONFIRMATION_DEPTH=1
    BASE_HEADER=0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4adae5494dffff7f2002000000
    BASE_HEADER_HEIGHT=0
  elif [[ "$BITCOIN_NETWORK" == "signet" ]]; then
    FINALIZATION_TIMEOUT=20
    CONFIRMATION_DEPTH=1
    # Get the next target difficulty adjustment height
    NEXT_RETARGET_HEIGHT=$(curl -sSL "https://mempool.space/signet/api/v1/difficulty-adjustment" | jq -r '.nextRetargetHeight')
    echo "Next retarget height: $NEXT_RETARGET_HEIGHT"

    # Calculate the previous difficulty adjustment height
    # Each 2016-block interval is known as a difficulty epoch
    BASE_HEADER_HEIGHT=$((NEXT_RETARGET_HEIGHT - 2016))
    echo "Base header height: $BASE_HEADER_HEIGHT"

    # Get the base header hash and header
    BASE_HEIGHT_HASH=$(curl -sSL "https://mempool.space/signet/api/block-height/$BASE_HEADER_HEIGHT")
    BASE_HEADER=$(curl -sSL "https://mempool.space/signet/api/block/$BASE_HEIGHT_HASH/header")
    
    if [ -z "$BASE_HEADER" ]; then
      echo "Error: Failed to retrieve base header"
      exit 1
    fi
    
    echo "Base header: $BASE_HEADER"
  else
    echo "Unsupported bitcoin network: $BITCOIN_NETWORK"
    exit 1
  fi
  echo

  # Initialize files for a babylon testnet
  # `covenant-pks` should be updated if `covenant-keyring` dir is changed` 
  # TODO: --min-staking-amount-sat and --max-staking-time-blocks can be a ENV variable
  docker run --rm -v $(pwd)/.testnets:/data babylonlabs/babylond:a98269d178879f22b136760701950d8929cc2093 \
      babylond testnet init-files --v 2 -o /data \
      --starting-ip-address 192.168.10.2 \
      --keyring-backend=test \
      --chain-id $BABYLON_CHAIN_ID \
      --epoch-interval 10 \
      --btc-finalization-timeout $FINALIZATION_TIMEOUT \
      --btc-confirmation-depth $CONFIRMATION_DEPTH \
      --minimum-gas-prices 0.000006ubbn \
      --btc-base-header $BASE_HEADER \
      --btc-base-header-height $BASE_HEADER_HEIGHT \
      --btc-network $BITCOIN_NETWORK \
      --additional-sender-account \
      --slashing-pk-script $SLASHING_PK_SCRIPT \
      --slashing-rate 0.1 \
      --min-commission-rate 0.05 \
      --covenant-quorum 1 \
      --covenant-pks "2d4ccbe538f846a750d82a77cd742895e51afcf23d86d05004a356b783902748" \
      --min-staking-amount-sat 10000 \
      --max-staking-time-blocks 50000

  sudo chown -R $(whoami):$(whoami) .testnets
  sudo chmod -R 777 .testnets

  # TODO: we need to decouple the babylon system and our finality system.
  #   only put the configs that are needed for the babylon system in the .testnets dir
  #   and for the finality gadget system in a separate dir.
  #   it might also make sense to split this script into two.
  # Create separate subpaths for each component and copy relevant configuration
  mkdir -p .testnets/vigilante/bbnconfig
  mkdir -p .testnets/btc-staker
  mkdir -p .testnets/eotsmanager
  mkdir -p .testnets/finality-provider
  mkdir -p .testnets/finality-gadget
  mkdir -p .testnets/consumer-eotsmanager
  mkdir -p .testnets/consumer-finality-provider
  mkdir -p .testnets/covenant-emulator
  mkdir -p .testnets/node0/babylond/covenant-emulator/keyring-test
  echo "Successfully created separate subpaths for each component"

  # for btc-staker, replace placeholders with env variables
  cp artifacts/stakerd.conf .testnets/btc-staker/stakerd.conf
  sed -i.bak "s|\${BITCOIN_NETWORK}|$BITCOIN_NETWORK|g" .testnets/btc-staker/stakerd.conf
  sed -i.bak "s|\${BITCOIN_RPC_PORT}|$BITCOIN_RPC_PORT|g" .testnets/btc-staker/stakerd.conf
  sed -i.bak "s|\${WALLET_PASS}|$WALLET_PASS|g" .testnets/btc-staker/stakerd.conf
  sed -i.bak "s|\${BABYLON_CHAIN_ID}|$BABYLON_CHAIN_ID|g" .testnets/btc-staker/stakerd.conf
  rm .testnets/btc-staker/stakerd.conf.bak

  # for vigilante, replace placeholders with env variables
  cp artifacts/vigilante.yml .testnets/vigilante/vigilante.yml
  sed -i.bak "s|\${BITCOIN_NETWORK}|$BITCOIN_NETWORK|g" .testnets/vigilante/vigilante.yml
  sed -i.bak "s|\${BITCOIN_RPC_PORT}|$BITCOIN_RPC_PORT|g" .testnets/vigilante/vigilante.yml
  sed -i.bak "s|\${WALLET_PASS}|$WALLET_PASS|g" .testnets/vigilante/vigilante.yml
  rm .testnets/vigilante/vigilante.yml.bak

  cp artifacts/eotsd.conf .testnets/eotsmanager/eotsd.conf
  cp artifacts/fpd.conf .testnets/finality-provider/fpd.conf
  sed -i.bak "s|\${BITCOIN_NETWORK}|$BITCOIN_NETWORK|g" .testnets/finality-provider/fpd.conf
  rm .testnets/finality-provider/fpd.conf.bak

  cp artifacts/opfgd.toml .testnets/finality-gadget/opfgd.toml
  sed -i.bak "s|\${BITCOIN_RPC_PORT}|$BITCOIN_RPC_PORT|g" .testnets/finality-gadget/opfgd.toml
  rm .testnets/finality-gadget/opfgd.toml.bak

  cp artifacts/consumer-eotsd.conf .testnets/consumer-eotsmanager/eotsd.conf
  cp artifacts/consumer-fpd.conf .testnets/consumer-finality-provider/fpd.conf
  sed -i.bak "s|\${BITCOIN_NETWORK}|$BITCOIN_NETWORK|g" .testnets/consumer-finality-provider/fpd.conf
  rm .testnets/consumer-finality-provider/fpd.conf.bak

  cp artifacts/covd.conf .testnets/covenant-emulator/covd.conf
  sed -i.bak "s|\${BITCOIN_NETWORK}|$BITCOIN_NETWORK|g" .testnets/covenant-emulator/covd.conf
  rm .testnets/covenant-emulator/covd.conf.bak

  cp -R artifacts/covenant-keyring .testnets/covenant-emulator/keyring-test
  cp .testnets/covenant-emulator/keyring-test/* .testnets/node0/babylond/covenant-emulator/keyring-test/
  echo "Successfully copied configuration files for each component"

  chmod -R 777 .testnets
  echo
fi

# Only run if .bitcoin directory does not exist
if [ ! -d ".bitcoin" ]; then
  echo "Creating .bitcoin directory..."
  mkdir -p .bitcoin && chmod -R 777 .bitcoin
fi
