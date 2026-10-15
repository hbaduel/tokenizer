#!/usr/bin/env bash
# Local demo of Hbaduel42Token alone (mandatory part) on Anvil.
# Prerequisite: `anvil` running in another terminal.
# Usage: ./deployment/demo-anvil-token.sh

set -euo pipefail
cd "$(dirname "$0")/.."

RPC=${RPC:-http://127.0.0.1:8545}

# Anvil default accounts (public keys, local use only)
PK0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
PK1=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
ACCOUNT3=0x90F79bf6EB2c4f870365E785982E1f101E93b906

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m    OK: %s\033[0m\n' "$1"; }

# Send a transaction that must succeed
send() { cast send "$@" --rpc-url "$RPC" > /dev/null; }

# Send a transaction that must revert, and print the decoded error
expect_revert() {
    local output
    if output=$(cast send "$@" --rpc-url "$RPC" 2>&1); then
        echo "    FAIL: transaction should have reverted" >&2
        exit 1
    fi
    ok "reverted -> $(grep -o '[A-Za-z0-9_]*([^()]*)$' <<< "$output" | tail -1)"
}

balance() { cast call "$TOKEN" "balanceOf(address)" "$1" --rpc-url "$RPC" | cast --from-wei; }

cast chain-id --rpc-url "$RPC" > /dev/null 2>&1 || { echo "Anvil is not running: start it with \`anvil\`" >&2; exit 1; }

set -a; source .env.anvil; set +a

step "Deploy Hbaduel42Token (owner = $OWNER_ADDRESS, receiver = $RECEIVER_ADDRESS)"
TOKEN=$(forge script deployment/DeployHbaduel42Token.s.sol --sig "run(bool)" false \
    --rpc-url "$RPC" --private-key "$PK0" --broadcast 2>&1 \
    | grep "Hbaduel42Token deployed at:" | awk '{print $NF}')
ok "token at $TOKEN"

step "Token info"
echo "    name:         $(cast call "$TOKEN" "name()(string)" --rpc-url "$RPC")"
echo "    symbol:       $(cast call "$TOKEN" "symbol()(string)" --rpc-url "$RPC")"
echo "    owner:        $(cast call "$TOKEN" "owner()(address)" --rpc-url "$RPC")"
echo "    totalSupply:  $(cast call "$TOKEN" "totalSupply()" --rpc-url "$RPC" | cast --from-wei)"
echo "    receiver bal: $(balance "$RECEIVER_ADDRESS")"

step "Receiver transfers 100 HFT to account 3"
send "$TOKEN" "transfer(address,uint256)" "$ACCOUNT3" 100e18 --private-key "$PK1"
ok "account 3 balance: $(balance "$ACCOUNT3")"

step "Owner mints 1000 HFT to account 3"
send "$TOKEN" "mint(address,uint256)" "$ACCOUNT3" 1000e18 --private-key "$PK0"
ok "account 3 balance: $(balance "$ACCOUNT3")"

step "Non-owner (receiver) tries to mint"
expect_revert "$TOKEN" "mint(address,uint256)" "$ACCOUNT3" 1000e18 --private-key "$PK1"

step "Owner tries to mint above MAX_SUPPLY (10M)"
expect_revert "$TOKEN" "mint(address,uint256)" "$ACCOUNT3" 9000000e18 --private-key "$PK0"

step "Final totalSupply: $(cast call "$TOKEN" "totalSupply()" --rpc-url "$RPC" | cast --from-wei)"
