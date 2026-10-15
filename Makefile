# Foundry binaries (also works when ~/.foundry/bin is not in the shell PATH)
export PATH := $(HOME)/.foundry/bin:$(PATH)
FORGE := $(HOME)/.foundry/bin/forge
CAST  := $(HOME)/.foundry/bin/cast
ANVIL := $(HOME)/.foundry/bin/anvil

ANVIL_PORT ?= 8545
ANVIL_RPC  := http://127.0.0.1:$(ANVIL_PORT)
ACCOUNT    ?= account1
DEPLOY     := deployment/DeployHbaduel42Token.s.sol

.DEFAULT_GOAL := help

.PHONY: all install foundry deps build test anvil node deploy-bsc deploy-bsc-token fmt clean help account

all: install test

help:
	@echo "make all              install + test"
	@echo "make install          Install Foundry (if missing) and dependencies, then build"
	@echo "make build            Compile contracts"
	@echo "make test             Run all tests (forge test -vvv)"
	@echo "make anvil            Start a local Anvil chain, run both demos, then stop it"
	@echo "make node             Start Anvil in the foreground (for manual cast commands)"
	@echo "make account          Import $(ACCOUNT) (override with ACCOUNT=<name>) into Foundry keystore if missing"
	@echo "make deploy-bsc       Deploy MultiSig42 + Hbaduel42Token on BSC Testnet and verify (needs .env)"
	@echo "make deploy-bsc-token Deploy Hbaduel42Token alone on BSC Testnet and verify (needs .env)"
	@echo "make fmt              Format Solidity files"
	@echo "make clean            Remove build artifacts"

install: foundry deps build

foundry:
	@test -x $(FORGE) || { \
		echo "Installing Foundry..."; \
		curl -L https://foundry.paradigm.xyz | bash; \
		$(HOME)/.foundry/bin/foundryup; \
	}
	@$(FORGE) --version | head -1

deps:
	git submodule update --init --recursive

build:
	$(FORGE) build

test:
	$(FORGE) test -vvv

anvil: build
	@if $(CAST) chain-id --rpc-url $(ANVIL_RPC) > /dev/null 2>&1; then \
		echo "Port $(ANVIL_PORT) already in use (an Anvil is running?). Stop it or use ANVIL_PORT=<port>."; \
		exit 1; \
	fi
	@$(ANVIL) --port $(ANVIL_PORT) > /dev/null 2>&1 & ANVIL_PID=$$!; \
	trap "kill $$ANVIL_PID" EXIT; \
	for i in $$(seq 50); do $(CAST) chain-id --rpc-url $(ANVIL_RPC) > /dev/null 2>&1 && break; sleep 0.2; done; \
	RPC=$(ANVIL_RPC) ./deployment/demo-anvil-token.sh && \
	RPC=$(ANVIL_RPC) ./deployment/demo-anvil-multisig.sh

node:
	$(ANVIL) --port $(ANVIL_PORT)

# Imports $(ACCOUNT) into Foundry's encrypted keystore if missing (asks private key + password, hidden)
account:
	@if $(CAST) wallet list 2> /dev/null | grep -q "^$(ACCOUNT) "; then \
		echo "Account '$(ACCOUNT)' found in Foundry keystore."; \
	else \
		echo "Account '$(ACCOUNT)' not found in Foundry keystore, importing it."; \
		$(CAST) wallet import $(ACCOUNT) --interactive; \
	fi

deploy-bsc: account
	$(FORGE) script $(DEPLOY) --sig "run(bool)" true --rpc-url bsc_testnet --account $(ACCOUNT) --broadcast --verify --legacy

deploy-bsc-token: account
	$(FORGE) script $(DEPLOY) --sig "run(bool)" false --rpc-url bsc_testnet --account $(ACCOUNT) --broadcast --verify --legacy

fmt:
	$(FORGE) fmt --check

clean:
	$(FORGE) clean
