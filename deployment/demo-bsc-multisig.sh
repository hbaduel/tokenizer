#!/usr/bin/env bash
# Demo of MultiSig42 owning Hbaduel42Token on BSC Testnet (real transactions, paid in tBNB).
#
# Prerequisites:
#   - contracts deployed with `make deploy-bsc` (addresses read from broadcast/),
#     or MULTISIG_ADDRESS / TOKEN_ADDRESS set in the environment
#   - SIGNER_A and SIGNER_B: two multisig signers imported in Foundry's keystore
#     (default: account1, account2; imported here if missing)
#   - DEMO_RECIPIENT: any address that is NOT a signer (e.g. MetaMask account 4)
#
# Usage: ./deployment/demo-bsc-multisig.sh   (asks the recipient if DEMO_RECIPIENT is not set)

set -euo pipefail
cd "$(dirname "$0")/.."

RPC=bsc_testnet
EXPLORER=https://testnet.bscscan.com
SIGNER_A=${SIGNER_A:-account1}
SIGNER_B=${SIGNER_B:-account2}
BROADCAST_DIR=broadcast/DeployHbaduel42Token.s.sol/97

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m    OK: %s\033[0m\n' "$1"; }
die()  { printf '\033[31m    ERROR: %s\033[0m\n' "$1" >&2; exit 1; }

set -a
[ -f .env ] && source .env
# Reference addresses committed in the repo (environment variables still take precedence)
while IFS='=' read -r key value; do
    case "$key" in ''|\#*) continue ;; esac
    [ -z "${!key:-}" ] && [ -n "$value" ] && export "$key=$value"
done < deployment/bsc-testnet.env
set +a

# --- Contract addresses ---------------------------------------------------------
# Latest successful `make deploy-bsc` run (one that deployed MultiSig42)
deployed() {
    local run
    for run in $(ls -r "$BROADCAST_DIR"/run-[0-9]*.json 2> /dev/null); do
        if jq -e '(.receipts | length > 0) and any(.transactions[]; .contractName == "MultiSig42")' "$run" > /dev/null; then
            jq -r --arg n "$1" '[.transactions[] | select(.contractName == $n)][-1].contractAddress' "$run"
            return
        fi
    done
}
if [ -z "${MULTISIG_ADDRESS:-}" ] || [ -z "${TOKEN_ADDRESS:-}" ]; then
    MULTISIG_ADDRESS=$(deployed MultiSig42)
    TOKEN_ADDRESS=$(deployed Hbaduel42Token)
    [ -n "$MULTISIG_ADDRESS" ] || die "no deployment found: run \`make deploy-bsc\` or set MULTISIG_ADDRESS and TOKEN_ADDRESS"
fi
MS=$MULTISIG_ADDRESS
TOKEN=$TOKEN_ADDRESS
# Demo recipient: any non-signer address (e.g. MetaMask account 4); asked if not set
if [ -z "${DEMO_RECIPIENT:-}" ]; then
    read -r -p "Demo recipient address (non-signer, e.g. MetaMask account 4): " DEMO_RECIPIENT
fi
DEMO_RECIPIENT=$(cast to-check-sum-address "$DEMO_RECIPIENT" 2> /dev/null) || die "invalid address"

# --- Signers: import if missing, ask each password once -------------------------
KEYSTORES=$HOME/.foundry/keystores
PASSWORD_DIR=$(mktemp -d)
trap 'rm -rf "$PASSWORD_DIR"' EXIT

for signer in "$SIGNER_A" "$SIGNER_B"; do
    if [ ! -f "$KEYSTORES/$signer" ]; then
        echo "Keystore '$signer' not found, importing it (private key + password):"
        cast wallet import "$signer" --interactive
    fi
    read -r -s -p "Password for $signer: " password; echo
    printf '%s' "$password" > "$PASSWORD_DIR/$signer"
    chmod 600 "$PASSWORD_DIR/$signer"
done
unset password

wallet() { echo --keystore "$KEYSTORES/$1" --password-file "$PASSWORD_DIR/$1"; }
address_of() { cast wallet address $(wallet "$1"); }
ADDR_A=$(address_of "$SIGNER_A")
ADDR_B=$(address_of "$SIGNER_B")

# --- Helpers --------------------------------------------------------------------
# Real transaction signed by a signer; prints the BscScan link
send_as() {
    local signer=$1; shift
    local hash
    hash=$(cast send "$@" $(wallet "$signer") --rpc-url "$RPC" --legacy | awk '/^transactionHash/ {print $2}')
    ok "$EXPLORER/tx/$hash"
}

# Free simulation (eth_call) of a call that must revert; prints the decoded error
expect_revert_from() {
    local from=$1; shift
    local output
    if output=$(cast call --from "$from" "$@" --rpc-url "$RPC" 2>&1); then
        die "call should have reverted"
    fi
    ok "reverted -> $(grep -o '[A-Za-z0-9_]*([^()]*)$' <<< "$output" | tail -1)"
}

balance() { cast call "$TOKEN" "balanceOf(address)" "$1" --rpc-url "$RPC" | cast --from-wei; }
last_tx_id() { echo $(( $(cast call "$MS" "getTransactionCount()(uint256)" --rpc-url "$RPC" | awk '{print $1}') - 1 )); }

# --- Demo -----------------------------------------------------------------------
step "Setup"
echo "    multisig:     $MS ($EXPLORER/address/$MS)"
echo "    token:        $TOKEN ($EXPLORER/address/$TOKEN)"
echo "    signers:      $(cast call "$MS" "getOwners()(address[])" --rpc-url "$RPC")"
echo "    threshold:    $(cast call "$MS" "nbConfirmationsRequired()(uint256)" --rpc-url "$RPC")"
echo "    token owner:  $(cast call "$TOKEN" "owner()(address)" --rpc-url "$RPC")"
echo "    treasury:     $(balance "$MS") HFT"
echo "    demo signers: $SIGNER_A ($ADDR_A), $SIGNER_B ($ADDR_B)"
echo "    recipient:    $DEMO_RECIPIENT ($(balance "$DEMO_RECIPIENT") HFT)"

# Signer B needs a little tBNB to pay its own transactions
if [ "$(cast balance "$ADDR_B" --rpc-url "$RPC")" -lt 500000000000000 ]; then
    step "Funding $SIGNER_B with 0.001 tBNB from $SIGNER_A"
    send_as "$SIGNER_A" "$ADDR_B" --value 0.001ether
fi

[ "$(cast call "$MS" "isOwner(address)(bool)" "$DEMO_RECIPIENT" --rpc-url "$RPC")" = "false" ] \
    || die "recipient $DEMO_RECIPIENT is a multisig signer: use a non-signer address"

MINT_DATA=$(cast calldata "mint(address,uint256)" "$DEMO_RECIPIENT" 1000e18)

step "A signer alone tries to mint directly on the token (simulation)"
expect_revert_from "$ADDR_A" "$TOKEN" "mint(address,uint256)" "$DEMO_RECIPIENT" 1000e18

step "A non-signer tries to submit a transaction (simulation)"
expect_revert_from "$DEMO_RECIPIENT" "$MS" "submitTransaction(address,bytes)" "$TOKEN" "$MINT_DATA"

step "$SIGNER_A submits: mint 1000 HFT to recipient"
send_as "$SIGNER_A" "$MS" "submitTransaction(address,bytes)" "$TOKEN" "$MINT_DATA"
TX=$(last_tx_id)
ok "transaction #$TX"

step "$SIGNER_A confirms #$TX"
send_as "$SIGNER_A" "$MS" "confirmTransaction(uint256)" "$TX"

step "Execute #$TX with only 1 confirmation (simulation)"
expect_revert_from "$ADDR_A" "$MS" "executeTransaction(uint256)" "$TX"

step "$SIGNER_B confirms #$TX, then $SIGNER_A executes"
send_as "$SIGNER_B" "$MS" "confirmTransaction(uint256)" "$TX"
send_as "$SIGNER_A" "$MS" "executeTransaction(uint256)" "$TX"
ok "recipient balance: $(balance "$DEMO_RECIPIENT") HFT"

step "Execute #$TX again (simulation)"
expect_revert_from "$ADDR_A" "$MS" "executeTransaction(uint256)" "$TX"

step "Treasury: transfer 500 HFT from the multisig to recipient"
TRANSFER_DATA=$(cast calldata "transfer(address,uint256)" "$DEMO_RECIPIENT" 500e18)
send_as "$SIGNER_B" "$MS" "submitTransaction(address,bytes)" "$TOKEN" "$TRANSFER_DATA"
TX=$(last_tx_id)
ok "transaction #$TX"
send_as "$SIGNER_A" "$MS" "confirmTransaction(uint256)" "$TX"
send_as "$SIGNER_B" "$MS" "confirmTransaction(uint256)" "$TX"
send_as "$SIGNER_B" "$MS" "executeTransaction(uint256)" "$TX"
ok "treasury: $(balance "$MS") HFT"
ok "recipient: $(balance "$DEMO_RECIPIENT") HFT"
