#!/bin/bash
set -euo pipefail

# check if L1 is running
echo "Checking if L1 is running..."
L1_CHAIN_ID=$(curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"jsonrpc": "2.0", "method": "eth_chainId", "params": [], "id": 1}' \
    http://localhost:8545 | jq -r '.result' | xargs printf '%d\n')
echo "L1 chain id: $L1_CHAIN_ID"

# check if L2 op-geth is running
echo "Checking if L2 op-geth is running..."
L2_CHAIN_ID=$(curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"jsonrpc": "2.0", "method": "eth_chainId", "params": [], "id": 1}' \
    http://localhost:9545 | jq -r '.result' | xargs printf '%d\n')
echo "L2 chain id: $L2_CHAIN_ID"

# check if L2 op-node is running
echo "Checking if L2 op-node is running..."
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' \
    http://localhost:7545 | \
    jq '.result | {
        head_l1_number: .head_l1.number,
        safe_l1_number: .safe_l1.number,
        finalized_l1_number: .finalized_l1.number,
        unsafe_l2_number: .unsafe_l2.number,
        safe_l2_number: .safe_l2.number,
        finalized_l2_number: .finalized_l2.number
    }'
echo