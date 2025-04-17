#!/bin/sh

# Exit on any error
set -e

CONSUMER_ID="op-stack-bob-808813-000"

# Create directories for consumer-eotsmanager and consumer-fp
mkdir -p .testnets/consumer-eotsmanager
mkdir -p .testnets/consumer-fp

# Copy configuration files to the respective directories
cp artifacts/consumer-eotsd.conf .testnets/consumer-eotsmanager/eotsd.conf
cp artifacts/consumer-fpd.conf .testnets/consumer-fp/fpd.conf

# Set permissions for the directories
chmod -R 777 .testnets

# Start the consumer finality provider and EOTS manager
echo "Starting consumer finality provider and EOTS manager..."
sudo docker compose -f artifacts/docker-compose.yml up -d

sleep 5

# Get finality provider EOTS public key
fp_btc_pk=$(sudo docker exec consumer-eotsmanager /bin/sh -c "cat /home/finality-provider/.eotsd/pubkey.hex")
echo "Consumer finality provider EOTS public key: $fp_btc_pk"

# Get finality provider address
fp_bbn_addr=$(sudo docker exec consumer-fp /bin/sh -c "/bin/fpd keys list --output json | jq -r '.[] | select(.name==\"finality-provider\") | .address'")
echo "Consumer finality provider Babylon address: $fp_bbn_addr"

# fund consumer finality provider account on Babylon
echo "Funding consumer finality provider account on Babylon using the faucet..."
curl https://faucet-euphrates.devnet.babylonlabs.io/claim \
    -H "Content-Type: multipart/form-data" \
    -d "{\"address\": \"$fp_bbn_addr\"}"
echo "Consumer finality provider account $fp_bbn_addr funded"

# create consumer finality provider on Babylon
echo "Creating consumer finality provider on Babylon..."
sudo docker exec consumer-fp /bin/sh -c "
    /bin/fpd cfp --key-name finality-provider \
        --chain-id $CONSUMER_ID \
        --eots-pk $fp_btc_pk \
        --commission-rate 0.05 \
        --moniker \"BOB finality provider\"
"
echo "Consumer finality provider created"

# Restart the finality provider containers so that key creation command above
# takes effect and finality provider is start communication with the chain.
echo 'Restarting consumer chain finality provider...'
sudo docker restart consumer-fp
echo 'Consumer chain finality provider restarted'
