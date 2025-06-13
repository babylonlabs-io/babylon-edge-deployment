ifeq ($(BITCOIN_CORE_VERSION),)
	BITCOINDSIM_TAG := latest
else
	BITCOINDSIM_BUILD_ARG := --build-arg BITCOIN_CORE_VERSION=$(BITCOIN_CORE_VERSION)
	BITCOINDSIM_TAG := $(BITCOIN_CORE_VERSION)
endif

all: bitcoinsim

bitcoindsim:
	docker build --platform "linux/amd64" --tag babylonlabs-io/bitcoindsim:$(BITCOINDSIM_TAG) -f bitcoindsim/Dockerfile \
		$(shell git rev-parse --show-toplevel)/contrib/images/bitcoindsim $(BITCOINDSIM_BUILD_ARG)

ibcsim-gaia:
	docker build --tag babylonlabs-io/ibcsim-gaia -f ibcsim-gaia/Dockerfile \
		$(shell git rev-parse --show-toplevel)/contrib/images/ibcsim-gaia

ibcsim-bcd:
	docker build --tag babylonlabs-io/ibcsim-bcd -f ibcsim-bcd/Dockerfile \
		$(shell git rev-parse --show-toplevel)/contrib/images/ibcsim-bcd

btcdsim-rmi:
	docker rmi babylonlabs-io/btcdsim 2>/dev/null; true

bitcoindsim-rmi:
	docker rmi babylonlabs-io/bitcoindsim 2>/dev/null; true

ibcsim-gaia-rmi:
	docker rmi babylonlabs-io/ibcsim-gaia 2>/dev/null; true

ibcsim-bcd-rmi:
	docker rmi babylonlabs-io/ibcsim-bcd 2>/dev/null; true

tmkms:
	docker build --platform "linux/amd64" --tag babylonlabs-io/tmkms:latest -f tmkms/Dockerfile \
		$(shell git rev-parse --show-toplevel)/contrib/images/tmkms

.PHONY: all btcdsim btcdsim-rmi bitcoindsim bitcoindsim-rmi ibcsim-gaia ibcsim-gaia-rmi ibcsim-bcd ibcsim-bcd-rmi tmkms
