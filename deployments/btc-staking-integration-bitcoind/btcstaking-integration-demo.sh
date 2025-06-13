#!/bin/bash

BBN_CHAIN_ID="chain-test"

echo "Waiting for relayer to recover keys..."
while true; do
    # Check if both keys are recovered by querying them
    BABYLON_ADDRESS=$(docker exec ibcsim-bcd /bin/sh -c "rly --home /data/relayer keys list babylon 2>/dev/null" | cut -d' ' -f3)
    BCD_ADDRESS=$(docker exec ibcsim-bcd /bin/sh -c "rly --home /data/relayer keys list bcd 2>/dev/null" | cut -d' ' -f3)

    if [ -n "$BABYLON_ADDRESS" ] && [ -n "$BCD_ADDRESS" ]; then
        echo "Successfully recovered keys for both chains"
        break
    else
        echo "Waiting for key recovery... (babylon: $BABYLON_ADDRESS, bcd: $BCD_ADDRESS)"
        sleep 5
    fi
done

###############################################
#    Create IBC Light Clients and Connection  #
###############################################

echo "Creating IBC light clients on Babylon and bcd"
docker exec ibcsim-bcd /bin/sh -c "rly --home /data/relayer tx clients bcd"
[ $? -eq 0 ] && echo "Created IBC light clients successfully!" || echo "Error creating IBC light clients"

sleep 10

# Query client ID registered in Babylon node, as consumer ID
echo "Querying client ID registered in Babylon node..."
CONSUMER_ID=$(docker exec babylondnode0 babylond query ibc client states -o json | jq -r '.client_states[0].client_id')
[ -n "$CONSUMER_ID" ] && echo "Found client ID: $CONSUMER_ID" || echo "Error: Could not find client ID"

echo "Creating IBC connection between Babylon and bcd"
docker exec ibcsim-bcd /bin/sh -c "rly --home /data/relayer tx connection bcd"
[ $? -eq 0 ] && echo "Created IBC connection successfully!" || echo "Error creating IBC connection"

########################################
#    Create IBC Channel for IBC transfer #
########################################

echo "Creating IBC channel for IBC transfer"
docker exec ibcsim-bcd /bin/sh -c "rly --home /data/relayer tx channel bcd --src-port transfer --dst-port transfer --order unordered --version ics20-1"
[ $? -eq 0 ] && echo "Created IBC transfer channel successfully!" || echo "Error creating IBC transfer channel"

###############################
#    Register the consumer    #
###############################

echo "Registering the consumer"
docker exec babylondnode0 /bin/sh -c "/bin/babylond --home /babylondhome tx btcstkconsumer register-consumer $CONSUMER_ID consumer-name consumer-description 2 --from test-spending-key --chain-id $BBN_CHAIN_ID --keyring-backend test --fees 100000ubbn -y"

# The IBC client ID is the consumer ID
echo "Fetched IBC client ID $CONSUMER_ID. This will be used as consumer ID in Babylon"
while true; do
    # Consumer should be automatically registered in Babylon via IBC, query registered consumers
    CONSUMER_REGISTERS=$(docker exec babylondnode0 /bin/sh -c "/bin/babylond query btcstkconsumer registered-consumers -o json | jq -r '.consumer_registers'")

    # Check if there's exactly one consumer ID and it matches the expected CONSUMER_ID
    if [ $(echo "$CONSUMER_REGISTERS" | jq '. | length') -eq 1 ] && [ $(echo "$CONSUMER_REGISTERS" | jq -r '.[0].consumer_id') = "$CONSUMER_ID" ]; then
        echo "Verification successful: Exactly one consumer registered in Babylon with the expected ID."
        break
    else
        echo "Verification failed: Consumer ID not found in Babylon"
        echo "Expected consumer with ID: $CONSUMER_ID"
        echo "Found: $CONSUMER_REGISTERS"
        echo "Retrying in 10 seconds..."
        sleep 10
    fi
done

##############################################
#    Create IBC Channel for ZoneConcierge    #
##############################################

# Query contract address from ibcsim-bcd container
# TODO: query babylon module for getting the contract address
CONTRACT_ADDRESS=$(docker exec ibcsim-bcd /bin/sh -c 'bcd query wasm list-contract-by-code 1 -o json | jq -r ".contracts[0]"')
CONTRACT_PORT="wasm.$CONTRACT_ADDRESS"

# Create IBC channel for ZoneConcierge
echo "Creating IBC channel for zoneconcierge"
docker exec ibcsim-bcd /bin/sh -c "rly --home /data/relayer tx channel bcd --src-port zoneconcierge --dst-port $CONTRACT_PORT --order ordered --version zoneconcierge-1"
[ $? -eq 0 ] && echo "Created zoneconcierge IBC channel successfully!" || echo "Error creating zoneconcierge IBC channel"

sleep 20

########################################
#    Start the relayer                  #
########################################

echo "Starting the relayer..."
docker exec ibcsim-bcd /bin/sh -c "nohup rly --home /data/relayer start bcd --debug-addr '' --flush-interval 30s > /data/relayer/relayer.log 2>&1 &"
echo "Relayer started, logs at /data/relayer/relayer.log in the container"

# Wait until the IBC channels are ready
echo "Waiting for IBC channels to be ready..."
while true; do
    # Fetch the port ID and channel ID from the Consumer IBC channel list
    channelInfoJson=$(docker exec ibcsim-bcd /bin/sh -c "bcd query ibc channel channels -o json")

    # Check if there are any channels available
    channelsLength=$(echo $channelInfoJson | jq -r '.channels | length')
    if [ "$channelsLength" -gt 1 ]; then
        # Print all channel port/ids
        echo "Found channels:"
        echo "$channelInfoJson" | jq -r '.channels[] | "Port ID: \(.port_id), Channel ID: \(.channel_id)"'
        # Store second channel info for later use
        portId=$(echo "$channelInfoJson" | jq -r '.channels[1].port_id')
        channelId=$(echo "$channelInfoJson" | jq -r '.channels[1].channel_id')
        break
    else
        echo "Found only $channelsLength channels, retrying in 10 seconds..."
        sleep 10
    fi
done

echo "Integration between Babylon and bcd is ready!"
echo "Now we will try out BTC staking on the consumer chain..."

# Get the BTC staking contract address from the list-contract-by-code query
btcStakingContractAddr=$(docker exec ibcsim-bcd /bin/sh -c 'bcd q wasm list-contract-by-code 3 -o json | jq -r ".contracts[0]"')
btcFinalityContractAddr=$(docker exec ibcsim-bcd /bin/sh -c 'bcd q wasm list-contract-by-code 4 -o json | jq -r ".contracts[0]"')

# create FP for Babylon
echo ""
echo "Creating 1 Babylon finality provider..."
bbn_btc_pk=$(docker exec eotsmanager /bin/sh -c "
    /bin/eotsd keys add finality-provider --keyring-backend=test --rpc-client "0.0.0.0:15813" --output=json | jq -r '.pubkey_hex'
")
bbn_fp_output=$(docker exec finality-provider /bin/sh -c "
    /bin/fpd cfp \
        --key-name finality-provider \
        --chain-id $BBN_CHAIN_ID \
        --eots-pk $bbn_btc_pk \
        --commission-rate 0.05 \
        --commission-max-rate 0.20 \
        --commission-max-change-rate 0.01 \
        --moniker \"Babylon finality provider\" 2>&1"
)

# Filter out the text message and parse only the JSON part
bbn_btc_pk=$(echo "$bbn_fp_output" | grep -v "Your finality provider is successfully created" | jq -r '.finality_provider.btc_pk_hex')

echo "Created 1 Babylon finality provider"
echo "BTC PK of Babylon finality provider: $bbn_btc_pk"

# Restart the finality provider containers so that key creation command above
# takes effect and finality provider is start communication with the chain.
echo "Restarting Babylon finality provider..."
docker restart finality-provider
echo "Babylon finality provider restarted"

# create FPs for the consumer chain
echo ""
echo "Creating a consumer chain finality provider"
consumer_btc_pk=$(docker exec consumer-eotsmanager /bin/sh -c "
    /bin/eotsd keys add finality-provider --keyring-backend=test --rpc-client "0.0.0.0:15813" --output=json | jq -r '.pubkey_hex'
")
consumer_fp_output=$(docker exec consumer-fp /bin/sh -c "
    /bin/fpd cfp \
        --key-name finality-provider \
        --chain-id $CONSUMER_ID \
        --eots-pk $consumer_btc_pk \
        --commission-rate 0.05 \
        --commission-max-rate 0.20 \
        --commission-max-change-rate 0.01 \
        --moniker \"Consumer finality Provider\" 2>&1"
)

# Filter out the text message and parse only the JSON part
consumer_btc_pk=$(echo "$consumer_fp_output" | grep -v "Your finality provider is successfully created" | jq -r '.finality_provider.btc_pk_hex')

echo "Created 1 consumer chain finality provider"
echo "BTC PK of consumer chain finality provider: $consumer_btc_pk"

# Restart the finality provider containers so that key creation command above
# takes effect and finality provider is start communication with the chain.
echo "Restarting consumer chain finality provider..."
docker restart consumer-fp
echo "Consumer chain finality provider restarted"

# Query contract state and check the count of finality providers
echo ""
echo "Check if contract has stored the finality providers..."
while true; do
    # Get the finality providers count from the contract state
    finalityProvidersCount=$(docker exec ibcsim-bcd /bin/sh -c "bcd q wasm contract-state smart $btcStakingContractAddr '{\"finality_providers\":{}}' -o json | jq '.data.fps | length'")

    echo "Finality provider count in contract store: $finalityProvidersCount"

    if [ "$finalityProvidersCount" -eq "1" ]; then
        echo "The number of finality providers in contract matches the expected count."
        break
    else
        sleep 10
    fi
done

# ensure finality providers are committing public randomness
echo ""
echo "Ensuring all finality providers have committed public randomness..."
while true; do
    pr_commit_info=$(docker exec ibcsim-bcd /bin/sh -c "bcd query wasm contract-state smart $btcFinalityContractAddr '{\"last_pub_rand_commit\":{\"btc_pk_hex\":\"$consumer_btc_pk\"}}' -o json")
    if [[ "$(echo "$pr_commit_info" | jq '.data')" == *"null"* ]]; then
        echo "The finality provider $consumer_btc_pk hasn't committed any public randomness yet"
        sleep 10
    else
        echo "The finality provider $consumer_btc_pk has committed public randomness"
        break
    fi
done

# Make BTC delegations to the finality providers
echo ""
echo "Make a delegation to each of the finality providers from a dedicated BTC address"
sleep 10
# Get the available BTC addresses for delegations
delAddrs=($(docker exec btc-staker /bin/sh -c '/bin/stakercli dn list-outputs | jq -r ".outputs[].address" | sort | uniq'))
stakingTime=10000
echo "Delegating 1 million Satoshis from BTC address ${delAddrs[i]} to Finality Provider with CZ finality provider $consumer_btc_pk and Babylon finality provider $bbn_btc_pk for $stakingTime BTC blocks"

btcTxHash=$(docker exec btc-staker /bin/sh -c \
    "/bin/stakercli dn stake --staker-address ${delAddrs[i]} --staking-amount 1000000 --finality-providers-pks $bbn_btc_pk --finality-providers-pks $consumer_btc_pk --staking-time $stakingTime | jq -r '.tx_hash'")
echo "Delegation was successful; staking tx hash is $btcTxHash"
echo "Made a delegation to each of the finality providers"

# Query babylon and check if the delegations are active
echo ""
echo "Wait a few minutes for the delegations to become active..."
while true; do
    # Get the active delegations count from Babylon
    activeDelegations=$(docker exec babylondnode0 /bin/sh -c 'babylond q btcstaking btc-delegations active -o json | jq ".btc_delegations | length"')

    echo "Active delegations count in Babylon: $activeDelegations"

    if [ "$activeDelegations" -eq 1 ]; then
        echo "All delegations have become active"
        break
    else
        sleep 10
    fi
done

# Query contract state and check the count of delegations
echo ""
echo "Check if contract has stored the delegations..."
while true; do
    # Get the delegations count from the contract state
    delegationsCount=$(docker exec ibcsim-bcd /bin/sh -c "bcd q wasm contract-state smart $btcStakingContractAddr '{\"delegations\":{}}' -o json | jq '.data.delegations | length'")

    echo "Delegations count in contract store: $delegationsCount"

    if [ "$delegationsCount" -eq 1 ]; then
        echo "The number of delegations in contract matches the expected count."
        break
    else
        sleep 10
    fi
done

echo ""
echo "Ensuring all finality providers have voting power"...
while true; do
    fp_by_info=$(docker exec ibcsim-bcd /bin/sh -c "bcd query wasm contract-state smart $btcStakingContractAddr '{\"finality_providers_by_power\":{}}' -o json")

    if [ $(echo "$fp_by_info" | jq '.data.fps | length') -ne 1 ]; then
        echo "There are less than 1 finality provider"
        sleep 10
    elif jq -e '.data.fps[].power | select(. <= 0)' <<<"$fp_by_info" >/dev/null; then
        echo "Some finality providers have zero voting power"
        sleep 10
    else
        echo "All finality providers have positive voting power"
        break
    fi
done

echo ""
echo "Ensuring all finality providers have submitted finality signatures..."
last_block_height=$(docker exec ibcsim-bcd /bin/sh -c "bcd query blocks --query \"block.height > 1\" --page 1 --limit 1 --order_by desc -o json | jq -r '.blocks[0].header.height'")
last_block_height=$((last_block_height + 1))
while true; do
    finality_sig_info=$(docker exec ibcsim-bcd /bin/sh -c "bcd query wasm contract-state smart $btcFinalityContractAddr '{\"finality_signature\":{\"btc_pk_hex\":\"$consumer_btc_pk\",\"height\":$last_block_height}}' -o json")
    if [ $(echo "$finality_sig_info" | jq '.data | length') -ne "1" ]; then
        echo "The finality provider $consumer_btc_pk hasn't submitted finality signature to $last_block_height yet"
        sleep 10
    else
        echo "The finality provider $consumer_btc_pk has submitted finality signature to $last_block_height"
        break
    fi
done

sleep 5

echo ""
echo "Ensuring the block on the consumer chain is finalised by BTC staking..."
while true; do
    indexed_block=$(docker exec ibcsim-bcd /bin/sh -c "bcd query wasm contract-state smart $btcFinalityContractAddr '{\"block\":{\"height\":$last_block_height}}' -o json")
    finalized=$(echo "$indexed_block" | jq -r '.data.finalized')
    if [ -z "$finalized" ]; then
        echo "Error: Unable to determine if the block at height $last_block_height is finalised"
        sleep 10
    elif [ "$finalized" != "true" ]; then
        echo "The block at height $last_block_height is not finalised yet"
        sleep 10
    else
        echo "The block at height $last_block_height is finalised!"
        break
    fi
done
