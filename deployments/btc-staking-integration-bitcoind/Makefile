DOCKER := $(shell which docker)
GIT_TOPLEVEL := $(shell git rev-parse --show-toplevel)

build-bitcoindsim:
	$(MAKE) -C $(GIT_TOPLEVEL)/contrib/images bitcoindsim

build-ibcsim-bcd:
	$(MAKE) -C $(GIT_TOPLEVEL)/contrib/images ibcsim-bcd

build-babylond:
	$(MAKE) -C $(GIT_TOPLEVEL)/babylon/contrib/images babylond

build-vigilante:
	$(MAKE) -C $(GIT_TOPLEVEL)/vigilante build-docker

build-btc-staker:
	$(MAKE) -C $(GIT_TOPLEVEL)/btc-staker build-docker

build-finality-provider:
	$(MAKE) -C $(GIT_TOPLEVEL)/finality-provider build-docker

build-covenant-emulator:
	$(MAKE) -C $(GIT_TOPLEVEL)/covenant-emulator build-docker

build-covenant-signer:
	$(MAKE) -C $(GIT_TOPLEVEL)/covenant-emulator/covenant-signer build-docker

build-tmkms:
	$(MAKE) -C $(GIT_TOPLEVEL)/contrib/images tmkms

build-deployment-btc-staking-integration-bitcoind: build-babylond build-bitcoindsim build-vigilante build-btc-staker build-finality-provider build-covenant-signer build-covenant-emulator build-ibcsim-bcd build-tmkms

start-deployment-btc-staking-integration-bitcoind: stop-deployment-btc-staking-integration-bitcoind build-deployment-btc-staking-integration-bitcoind
	./pre-deployment.sh
	$(DOCKER) compose -f artifacts/docker-compose.yml up -d
	./post-deployment.sh

stop-deployment-btc-staking-integration-bitcoind:
	$(DOCKER) compose -f artifacts/docker-compose.yml down
	rm -rf $(CURDIR)/.testnets

start-deployment-btc-staking-integration-bitcoind-demo: start-deployment-btc-staking-integration-bitcoind
	./btcstaking-integration-demo.sh

run-rollup-integration-demo: start-deployment-btc-staking-integration-bitcoind
	./rollup-btc-staking-demo.sh