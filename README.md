# Babylon Edge Deployment

This repository contains artifacts and instructions for setting up and running
a Babylon network locally, using several different deployment scenarios.

## Prerequisites

1. **Docker Desktop**: Install from
   [Docker's official website](https://docs.docker.com/desktop/).

2. **Make**: Required for building service binaries. Installation guide available
   [here](https://sp21.datastructur.es/materials/guides/make-install.html).

3. **Repository Setup**:
   ```shell
   git clone git@github.com:babylonlabs-io/babylon-edge-deployment.git
   git submodule init && git submodule update
   ```

## Deployment Scenarios

Scenarios are located in the [deployments](deployments/) directory:

- [BTC Staking Integration (bitcoind backend)](deployments/btc-staking-integration-bitcoind):
  Babylon network with BTC Staking and Timestamping, using a bitcoind-based BTC
  regression testnet.
- [Finality Gadget Integration with OP chain]: The guides linked below provide
  instructions on how to integrate the Babylon Bitcoin Staking protocol with an
  OP-Stack chain:
  - [Deploy an OP-Stack Chain with finality gadget](https://github.com/Snapchain/op-chain-deployment)
  - [Integrate finality gadget into your OP-Stack Chain](https://github.com/Snapchain/babylon-deployment)
