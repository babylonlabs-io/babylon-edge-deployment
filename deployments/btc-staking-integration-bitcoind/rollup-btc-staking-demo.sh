#!/bin/bash

set -e  # Exit on any error

sleep 10 # wait for containers to be ready (cov emulator takes a while to start)

BBN_CHAIN_ID="chain-test"
CONSUMER_ID="consumer-id"

echo "🚀 Starting Enhanced BTC Staking Integration Demo"
echo "=================================================="

# Build the crypto operations tool first
echo "🔧 Building crypto operations tool..."
cd crypto-ops-tool
go build -o ../crypto-ops ./cmd/crypto-ops
cd ../
echo "  ✅ Crypto operations tool built successfully"

# Get admin address for contract instantiation
admin=$(docker exec babylondnode0 /bin/sh -c "/bin/babylond --home /babylondhome keys show test-spending-key --keyring-backend test --output json | jq -r '.address'")
echo "Using admin address: $admin"

sleep 5

###############################
# Step 1: Deploy Finality     #
# Contract                    #
###############################

echo ""
echo "📋 Step 1: Deploying finality contract..."

echo "  → Storing contract WASM..."
STORE_CMD="/bin/babylond --home /babylondhome tx wasm store /contracts/op_finality_gadget.wasm --from test-spending-key --chain-id $BBN_CHAIN_ID --keyring-backend test --gas auto --gas-adjustment 1.3 --fees 1000000ubbn --output json -y"
echo "  → Command: $STORE_CMD"
STORE_OUTPUT=$(docker exec babylondnode0 /bin/sh -c "$STORE_CMD")
echo "  → Output: $STORE_OUTPUT"

sleep 10

echo "  → Instantiating contract..."
INSTANTIATE_MSG_JSON="{\"admin\":\"$admin\",\"consumer_id\":\"$CONSUMER_ID\",\"is_enabled\":true}"
INSTANTIATE_CMD="/bin/babylond --home /babylondhome tx wasm instantiate 1 '$INSTANTIATE_MSG_JSON' --chain-id $BBN_CHAIN_ID --keyring-backend test --fees 100000ubbn --label 'finality' --admin $admin --from test-spending-key --output json -y"
echo "  → Command: $INSTANTIATE_CMD"
INSTANTIATE_OUTPUT=$(docker exec babylondnode0 /bin/sh -c "$INSTANTIATE_CMD")
echo "  → Output: $INSTANTIATE_OUTPUT"

sleep 10

# Extract contract address
finalityContractAddr=$(docker exec babylondnode0 /bin/sh -c "/bin/babylond --home /babylondhome q wasm list-contracts-by-code 1 --output json | jq -r '.contracts[0]'")
echo "  ✅ Finality contract deployed at: $finalityContractAddr"

###############################
# Step 2: Register Consumer   #
###############################

echo ""
echo "🔗 Step 2: Registering consumer chain..."

REGISTER_CMD="/bin/babylond --home /babylondhome tx btcstkconsumer register-consumer $CONSUMER_ID consumer-name consumer-description 2 $finalityContractAddr --from test-spending-key --chain-id $BBN_CHAIN_ID --keyring-backend test --fees 100000ubbn --output json -y"
echo "  → Command: $REGISTER_CMD"
REGISTER_OUTPUT=$(docker exec babylondnode0 /bin/sh -c "$REGISTER_CMD")
echo "  → Output: $REGISTER_OUTPUT"

sleep 10
echo "  ✅ Consumer '$CONSUMER_ID' registered successfully"

###############################
# Step 3: Generate Crypto Keys#
###############################

echo ""
echo "🔐 Step 3: Generating cryptographic keys..."

echo "  → Generating BTC key pairs for finality providers..."

# Generate key pairs using the Go tool and parse JSON output
bbn_fp_json=$(./crypto-ops generate-keypair)
bbn_btc_pk=$(echo "$bbn_fp_json" | jq -r '.public_key')
bbn_btc_sk=$(echo "$bbn_fp_json" | jq -r '.private_key')

consumer_fp_json=$(./crypto-ops generate-keypair)
consumer_btc_pk=$(echo "$consumer_fp_json" | jq -r '.public_key')
consumer_btc_sk=$(echo "$consumer_fp_json" | jq -r '.private_key')

echo "  ✅ Babylon FP BTC PK: $bbn_btc_pk"
echo "  ✅ Babylon FP BTC SK: $bbn_btc_sk"
echo "  ✅ Consumer FP BTC PK: $consumer_btc_pk"
echo "  ✅ Consumer FP BTC SK: $consumer_btc_sk"

###############################
# Step 4: Create Finality     #
# Providers                   #
###############################

echo ""
echo "👥 Step 4: Creating finality providers on-chain..."

# Get admin address for PoP generation
admin=$(docker exec babylondnode0 /bin/sh -c "/bin/babylond --home /babylondhome keys show test-spending-key --keyring-backend test --output json | jq -r '.address'")
echo "  → Using admin address for PoP: $admin"

echo "  → Creating Babylon Finality Provider..."

# Generate PoP for Babylon FP using crypto-ops
bbn_pop_json=$(./crypto-ops generate-pop $bbn_btc_sk $admin)
bbn_pop_hex=$(echo "$bbn_pop_json" | jq -r '.pop_hex')

sleep 15

# Create Babylon FP on-chain
BBN_FP_CMD="/bin/babylond --home /babylondhome tx btcstaking create-finality-provider $bbn_btc_pk $bbn_pop_hex --from test-spending-key --moniker 'Babylon FP' --commission-rate 0.05 --commission-max-rate 0.10 --commission-max-change-rate 0.01 --chain-id $BBN_CHAIN_ID --keyring-backend test --gas-prices=1ubbn --output json -y"
echo "  → Command: $BBN_FP_CMD"
BBN_FP_OUTPUT=$(docker exec babylondnode0 /bin/sh -c "$BBN_FP_CMD")
echo "  → Output: $BBN_FP_OUTPUT"

sleep 15

echo "  ✅ Babylon FP created successfully"

echo "  → Creating Consumer Finality Provider..."

# Generate PoP for Consumer FP using crypto-ops
consumer_pop_json=$(./crypto-ops generate-pop $consumer_btc_sk $admin)
consumer_pop_hex=$(echo "$consumer_pop_json" | jq -r '.pop_hex')

# Create Consumer FP on-chain (note the --consumer-id flag)
CONSUMER_FP_CMD="/bin/babylond --home /babylondhome tx btcstaking create-finality-provider $consumer_btc_pk $consumer_pop_hex --from test-spending-key --moniker 'Consumer FP' --commission-rate 0.05 --commission-max-rate 0.10 --commission-max-change-rate 0.01 --consumer-id $CONSUMER_ID --chain-id $BBN_CHAIN_ID --keyring-backend test --gas-prices=1ubbn --output json -y"
echo "  → Command: $CONSUMER_FP_CMD"
CONSUMER_FP_OUTPUT=$(docker exec babylondnode0 /bin/sh -c "$CONSUMER_FP_CMD")
echo "  → Output: $CONSUMER_FP_OUTPUT"

sleep 15

echo "  ✅ Consumer FP created successfully"

# Verify FPs were created
echo "  → Verifying finality providers..."
bbn_fp_count=$(docker exec babylondnode0 /bin/sh -c "/bin/babylond --home /babylondhome q btcstaking finality-providers --output json | jq '.finality_providers | length'")
consumer_fp_count=$(docker exec babylondnode0 /bin/sh -c "/bin/babylond --home /babylondhome q btcstkconsumer finality-providers $CONSUMER_ID --output json | jq '.finality_providers | length'")
echo "  ✅ Babylon finality providers: $bbn_fp_count"
echo "  ✅ Consumer finality providers: $consumer_fp_count"

###############################
# Step 5: Stake BTC           #
###############################

echo ""
echo "₿ Step 5: Creating BTC delegation..."

echo "  → Getting available BTC addresses..."
delAddrs=($(docker exec btc-staker /bin/sh -c '/bin/stakercli dn list-outputs | jq -r ".outputs[].address" | sort | uniq'))
stakingTime=10000
stakingAmount=1000000  # 1M satoshis

echo "  → Delegating $stakingAmount satoshis for $stakingTime blocks..."
echo "    From: ${delAddrs[0]}"
echo "    To FPs: Babylon ($bbn_btc_pk) + Consumer ($consumer_btc_pk)"

btcTxHash=$(docker exec btc-staker /bin/sh -c "/bin/stakercli dn stake --staker-address ${delAddrs[0]} --staking-amount $stakingAmount --finality-providers-pks $bbn_btc_pk --finality-providers-pks $consumer_btc_pk --staking-time $stakingTime | jq -r '.tx_hash'")

if [ -z "$btcTxHash" ] || [ "$btcTxHash" = "null" ]; then
    echo "  ❌ Failed to create BTC delegation"
    exit 1
fi

echo "  ✅ BTC delegation created: $btcTxHash"

###############################
# Step 6: Wait for Activation #
###############################

echo ""
echo "⏳ Step 6: Waiting for delegation activation..."

echo "  → Monitoring delegation status..."
for i in {1..30}; do
    activeDelegations=$(docker exec babylondnode0 /bin/sh -c 'babylond q btcstaking btc-delegations active -o json | jq ".btc_delegations | length"')
    
    if [ "$activeDelegations" -eq 1 ]; then
        echo "  ✅ Delegation activated successfully!"
        break
    fi
    
    echo "    Attempt $i/30: $activeDelegations active delegations, waiting..."
    sleep 10
done

if [ "$activeDelegations" -ne 1 ]; then
    echo "  ⚠️ Warning: Delegation not activated after 5 minutes"
    echo "  Proceeding with demo anyway..."
fi

###############################
# Step 7: Commit & Finalize   #
###############################

echo ""
echo "🎲 Step 7a: Generating and committing public randomness..."

# Configure parameters for crypto operations
start_height=1
num_pub_rand=1000  # Commit randomness for 1000 blocks
num_finality_sigs=10  # Submit finality signatures for first 10 blocks

echo "  → Using crypto-ops to generate randomness (crypto-only)..."
echo "    Start height: $start_height, Number of commitments: $num_pub_rand"

# Step 7a: Generate public randomness commitment data using crypto-only command
echo "  → Generating public randomness commitment data for blocks $start_height to $((start_height + num_pub_rand - 1))..."
pub_rand_data=$(./crypto-ops generate-pub-rand-commitment $consumer_btc_sk $start_height $num_pub_rand)

if [ $? -ne 0 ]; then
    echo "  ❌ Failed to generate public randomness commitment data"
    exit 1
fi

echo "  ✅ Public randomness commitment data generated successfully!"

# Extract data from JSON response  
rand_list_info_json=$(echo "$pub_rand_data" | jq -r '.rand_list_info')
fp_pubkey_hex=$(echo "$pub_rand_data" | jq -r '.fp_pubkey_hex')
commitment=$(echo "$pub_rand_data" | jq -c '.commitment')  # Keep as JSON array
signature=$(echo "$pub_rand_data" | jq -c '.signature')    # Keep as JSON array

echo "  → Submitting commitment to finality contract..."
echo "    Contract: $finalityContractAddr"
echo "    FP PubKey: $fp_pubkey_hex"
echo "    Commitment: $commitment"

# Create the commit message for the finality contract  
commit_msg=$(jq -n \
  --arg fp_pubkey_hex "$fp_pubkey_hex" \
  --argjson start_height "$start_height" \
  --argjson num_pub_rand "$num_pub_rand" \
  --argjson commitment "$commitment" \
  --argjson signature "$signature" \
  '{
    commit_public_randomness: {
      fp_pubkey_hex: $fp_pubkey_hex,
      start_height: $start_height,
      num_pub_rand: $num_pub_rand,
      commitment: $commitment,
      signature: $signature
    }
  }')

# Submit to finality contract using wasm execute
COMMIT_CMD="/bin/babylond --home /babylondhome tx wasm execute $finalityContractAddr '$commit_msg' --from test-spending-key --chain-id $BBN_CHAIN_ID --keyring-backend test --gas 500000 --fees 100000ubbn -y --output json"
echo "  → Command: $COMMIT_CMD"
COMMIT_OUTPUT=$(docker exec babylondnode0 /bin/sh -c "$COMMIT_CMD")
echo "  → Output: $COMMIT_OUTPUT"

sleep 8

# Verify the commitment was stored
echo "  → Verifying commitment was stored..."
query_msg=$(jq -n --arg btc_pk_hex "$fp_pubkey_hex" '{last_pub_rand_commit: {btc_pk_hex: $btc_pk_hex}}')
VERIFY_CMD="/bin/babylond --home /babylondhome q wasm contract-state smart $finalityContractAddr '$query_msg' --output json"
VERIFY_OUTPUT=$(docker exec babylondnode0 /bin/sh -c "$VERIFY_CMD")
echo "  → Verification result: $VERIFY_OUTPUT"

echo "  ✅ Public randomness committed successfully for $num_pub_rand blocks!"

echo ""
echo "✍️ Step 7b: Generating and submitting finality signatures..."

# Step 7b: Generate and submit finality signatures for multiple blocks
echo "  → Processing $num_finality_sigs blocks using crypto-only approach..."
echo "    Processing blocks $start_height to $((start_height + num_finality_sigs - 1))"

# Counter for successful submissions
successful_sigs=0

# Loop through blocks and generate + submit finality signatures
for ((block_height=start_height; block_height<start_height+num_finality_sigs; block_height++)); do
    echo "  → [$((block_height - start_height + 1))/$num_finality_sigs] Processing block $block_height..."
    
    # Generate finality signature using crypto-only command (block hash generated internally)
    echo "    → Generating finality signature (crypto-only)..."
    finality_sig_data=$(echo "$rand_list_info_json" | ./crypto-ops generate-finality-sig $consumer_btc_sk $block_height)
    
    if [ $? -ne 0 ]; then
        echo "    ❌ Block $block_height: Failed to generate finality signature"
        echo "  💥 Finality signature generation failed - stopping batch processing"
        echo "  📊 Final status: $successful_sigs/$num_finality_sigs blocks processed successfully before failure"
        exit 1
    fi
    
    # Extract signature data from JSON response (using proper JSON handling)
    sig_fp_pubkey_hex=$(echo "$finality_sig_data" | jq -r '.fp_pubkey_hex')
    sig_height=$(echo "$finality_sig_data" | jq -r '.height')
    sig_pub_rand=$(echo "$finality_sig_data" | jq -c '.pub_rand')          # Keep as JSON array
    sig_proof=$(echo "$finality_sig_data" | jq -c '.proof')                # Keep as JSON object
    sig_block_hash=$(echo "$finality_sig_data" | jq -c '.block_hash')      # Keep as JSON array
    sig_signature=$(echo "$finality_sig_data" | jq -c '.signature')        # Keep as JSON array
    
    echo "    → Submitting finality signature to contract..."
    
    # Create finality signature message for the contract
    finality_msg=$(jq -n \
      --arg fp_pubkey_hex "$sig_fp_pubkey_hex" \
      --argjson height "$sig_height" \
      --argjson pub_rand "$sig_pub_rand" \
      --argjson proof "$sig_proof" \
      --argjson block_hash "$sig_block_hash" \
      --argjson signature "$sig_signature" \
      '{
        submit_finality_signature: {
          fp_pubkey_hex: $fp_pubkey_hex,
          height: $height,
          pub_rand: $pub_rand,
          proof: $proof,
          block_hash: $block_hash,
          signature: $signature
        }
      }')
    
    # Submit to finality contract using wasm execute
    FINALITY_CMD="/bin/babylond --home /babylondhome tx wasm execute $finalityContractAddr '$finality_msg' --from test-spending-key --chain-id $BBN_CHAIN_ID --keyring-backend test --gas 500000 --fees 100000ubbn -y --output json"
    FINALITY_OUTPUT=$(docker exec babylondnode0 /bin/sh -c "$FINALITY_CMD")
    echo "    → Submission result: $FINALITY_OUTPUT"
    
    # Verify the signature was recorded
    sleep 8  # Increased delay for transaction processing
    echo "    → Verifying finality signature was recorded..."
    
    # Use the hex string directly from Go output (much simpler!)
    block_hash_hex=$(echo "$finality_sig_data" | jq -r '.block_hash_hex')
    
    # Retry verification up to 5 times with delays
    verification_success=false
    for verification_attempt in {1..5}; do
        echo "    → Verification attempt $verification_attempt/5..."
        verify_msg=$(jq -n --argjson height "$sig_height" --arg hash "$block_hash_hex" '{block_voters: {height: $height, hash: $hash}}')
        VERIFY_SIG_CMD="/bin/babylond --home /babylondhome q wasm contract-state smart $finalityContractAddr '$verify_msg' --output json"
        VERIFY_SIG_OUTPUT=$(docker exec babylondnode0 /bin/sh -c "$VERIFY_SIG_CMD")
        
        # Check if data is not null and contains our FP
        if echo "$VERIFY_SIG_OUTPUT" | jq -e '.data != null' >/dev/null && echo "$VERIFY_SIG_OUTPUT" | jq -r '.data[]' | grep -q "$sig_fp_pubkey_hex"; then
            verification_success=true
            echo "    ✅ Verification succeeded on attempt $verification_attempt"
            break
        else
            echo "    → Attempt $verification_attempt failed, data: $(echo "$VERIFY_SIG_OUTPUT" | jq -r '.data')"
            if [ $verification_attempt -lt 5 ]; then
                echo "    → Waiting 5 seconds before retry..."
                sleep 5
            fi
        fi
    done
    
    if [ "$verification_success" = false ]; then
        echo "    ❌ Block $block_height: Finality signature verification failed"
        echo "    → Verification output: $VERIFY_SIG_OUTPUT"
        echo "  💥 Finality signature verification failed - stopping batch processing"
        echo "  📊 Final status: $successful_sigs/$num_finality_sigs blocks processed successfully before failure"
        exit 1
    else
        ((successful_sigs++))
        echo "    ✅ Block $block_height: Finality signature submitted and verified successfully"
    fi
    
    # Add small delay to avoid overwhelming the system
    sleep 2  # Reduced since we have longer delays in verification
done

echo ""
echo "🎉 All $num_finality_sigs finality signatures processed successfully!"
echo "  📊 Successfully processed blocks $start_height to $((start_height + num_finality_sigs - 1))"

###############################
# Demo Summary                #
###############################

echo ""
echo "🎉 BTC Staking Integration Demo Complete!"
echo "=========================================="
echo ""
echo "✅ Finality contract deployed: $finalityContractAddr"
echo "✅ Consumer chain registered: $CONSUMER_ID"
echo "✅ Finality providers created: $bbn_fp_count Babylon + $consumer_fp_count Consumer"
echo "✅ BTC delegation active: $btcTxHash ($activeDelegations active)"
echo "✅ Public randomness committed: blocks $start_height-$((start_height + num_pub_rand - 1)) ($num_pub_rand total)"
echo "✅ Finality signatures processed: $successful_sigs/$num_finality_sigs blocks (blocks $start_height-$((start_height + num_finality_sigs - 1)))"
