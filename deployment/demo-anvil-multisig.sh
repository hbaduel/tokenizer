#!/usr/bin/env bash
# Local demo of MultiSig42 owning Hbaduel42Token (bonus part) on Anvil.
# Prerequisite: `anvil` running in another terminal.
# Usage: ./deployment/demo-anvil-multisig.sh

set -euo pipefail
cd "$(dirname "$0")/.."

RPC=${RPC:-http://127.0.0.1:8545}

# Anvil default accounts (public keys, local use only)
# Accounts 0, 1, 2 = multisig signers (from .env.anvil), account 3 = outsider
PK0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
PK1=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
PK3=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
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
    ok "reverted -> $(grep -o '[A-Za-z]*([^()]*)$' <<< "$output" | tail -1)"
}

balance() { cast call "$TOKEN" "balanceOf(address)" "$1" --rpc-url "$RPC" | cast --from-wei; }
last_tx_id() { echo $(( $(cast call "$MS" "getTransactionCount()(uint256)" --rpc-url "$RPC" | awk '{print $1}') - 1 )); }

cast chain-id --rpc-url "$RPC" > /dev/null 2>&1 || { echo "Anvil is not running: start it with \`anvil\`" >&2; exit 1; }

set -a; source .env.anvil; set +a

step "Deploy MultiSig42 ($NB_CONFIRMATIONS_REQUIRED confirmations) + Hbaduel42Token (owner = receiver = multisig)"
DEPLOY_OUTPUT=$(forge script deployment/DeployHbaduel42Token.s.sol --sig "run(bool)" true \
    --rpc-url "$RPC" --private-key "$PK0" --broadcast 2>&1)
MS=$(grep "MultiSig42 deployed at:" <<< "$DEPLOY_OUTPUT" | awk '{print $NF}')
TOKEN=$(grep "Hbaduel42Token deployed at:" <<< "$DEPLOY_OUTPUT" | awk '{print $NF}')
ok "multisig at $MS"
ok "token at $TOKEN"

step "Setup"
echo "    signers:        $(cast call "$MS" "getOwners()(address[])" --rpc-url "$RPC")"
echo "    threshold:      $(cast call "$MS" "nbConfirmationsRequired()(uint256)" --rpc-url "$RPC")"
echo "    token owner:    $(cast call "$TOKEN" "owner()(address)" --rpc-url "$RPC")"
echo "    multisig bal:   $(balance "$MS") HFT (treasury)"

step "A signer alone tries to mint directly on the token"
expect_revert "$TOKEN" "mint(address,uint256)" "$ACCOUNT3" 1000e18 --private-key "$PK0"

step "An outsider tries to submit a transaction"
MINT_DATA=$(cast calldata "mint(address,uint256)" "$ACCOUNT3" 1000e18)
expect_revert "$MS" "submitTransaction(address,bytes)" "$TOKEN" "$MINT_DATA" --private-key "$PK3"

step "Signer 0 submits: mint 1000 HFT to account 3"
send "$MS" "submitTransaction(address,bytes)" "$TOKEN" "$MINT_DATA" --private-key "$PK0"
TX=$(last_tx_id)
ok "transaction #$TX submitted"

step "Signer 0 confirms, then tries to execute with 1 confirmation"
send "$MS" "confirmTransaction(uint256)" "$TX" --private-key "$PK0"
expect_revert "$MS" "executeTransaction(uint256)" "$TX" --private-key "$PK0"

step "Signer 1 confirms (2/2), then execute"
send "$MS" "confirmTransaction(uint256)" "$TX" --private-key "$PK1"
send "$MS" "executeTransaction(uint256)" "$TX" --private-key "$PK0"
ok "account 3 balance: $(balance "$ACCOUNT3") HFT"

step "Execute the same transaction again"
expect_revert "$MS" "executeTransaction(uint256)" "$TX" --private-key "$PK0"

step "Treasury: transfer 500 HFT from the multisig to account 3"
TRANSFER_DATA=$(cast calldata "transfer(address,uint256)" "$ACCOUNT3" 500e18)
send "$MS" "submitTransaction(address,bytes)" "$TOKEN" "$TRANSFER_DATA" --private-key "$PK1"
TX=$(last_tx_id)
send "$MS" "confirmTransaction(uint256)" "$TX" --private-key "$PK0"
send "$MS" "confirmTransaction(uint256)" "$TX" --private-key "$PK1"
send "$MS" "executeTransaction(uint256)" "$TX" --private-key "$PK1"
ok "multisig balance: $(balance "$MS") HFT"
ok "account 3 balance: $(balance "$ACCOUNT3") HFT"
