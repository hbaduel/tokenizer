#!/usr/bin/env bash
# Demo of Hbaduel42Token alone (mandatory part) on BSC Testnet (real transactions, paid in tBNB).
#
# Prerequisites:
#   - token deployed with `make deploy-bsc-token` (address read from broadcast/),
#     or TOKEN_ONLY_ADDRESS set in the environment
#   - OWNER: keystore of the token owner, which must also be the receiver of the initial
#     supply (default: account1; imported here if missing)
#   - DEMO_RECIPIENT: any address other than the owner (e.g. MetaMask account 4)
#
# Usage: ./deployment/demo-bsc-token.sh   (asks the recipient if DEMO_RECIPIENT is not set)

set -euo pipefail
cd "$(dirname "$0")/.."

RPC=bsc_testnet
EXPLORER=https://testnet.bscscan.com
OWNER=${OWNER:-account1}
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

# --- Token address --------------------------------------------------------------
# Latest successful `make deploy-bsc-token` run (one that deployed the token without MultiSig42)
deployed_token_only() {
    local run
    for run in $(ls -r "$BROADCAST_DIR"/run-[0-9]*.json 2> /dev/null); do
        if jq -e '(.receipts | length > 0) and all(.transactions[]; .contractName != "MultiSig42")' "$run" > /dev/null; then
            jq -r '[.transactions[] | select(.contractName == "Hbaduel42Token")][-1].contractAddress' "$run"
            return
        fi
    done
}
TOKEN=${TOKEN_ONLY_ADDRESS:-$(deployed_token_only)}
[ -n "$TOKEN" ] || die "no token-only deployment found: run \`make deploy-bsc-token\` or set TOKEN_ONLY_ADDRESS"
# Demo recipient: any non-owner address (e.g. MetaMask account 4); asked if not set
if [ -z "${DEMO_RECIPIENT:-}" ]; then
    read -r -p "Demo recipient address (non-owner, e.g. MetaMask account 4): " DEMO_RECIPIENT
fi
DEMO_RECIPIENT=$(cast to-check-sum-address "$DEMO_RECIPIENT" 2> /dev/null) || die "invalid address"

# --- Owner wallet: import if missing, ask password once -------------------------
KEYSTORE=$HOME/.foundry/keystores/$OWNER
PASSWORD_DIR=$(mktemp -d)
trap 'rm -rf "$PASSWORD_DIR"' EXIT

if [ ! -f "$KEYSTORE" ]; then
    echo "Keystore '$OWNER' not found, importing it (private key + password):"
    cast wallet import "$OWNER" --interactive
fi
read -r -s -p "Password for $OWNER: " password; echo
printf '%s' "$password" > "$PASSWORD_DIR/password"
chmod 600 "$PASSWORD_DIR/password"
unset password

WALLET="--keystore $KEYSTORE --password-file $PASSWORD_DIR/password"
OWNER_ADDR=$(cast wallet address $WALLET)

# --- Helpers --------------------------------------------------------------------
# Real transaction signed by the owner; prints the BscScan link
send() {
    local hash
    hash=$(cast send "$@" $WALLET --rpc-url "$RPC" --legacy | awk '/^transactionHash/ {print $2}')
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
supply()  { cast call "$TOKEN" "totalSupply()" --rpc-url "$RPC" | cast --from-wei; }

# --- Demo -----------------------------------------------------------------------
step "Token info"
echo "    address:     $TOKEN ($EXPLORER/token/$TOKEN)"
echo "    name:        $(cast call "$TOKEN" "name()(string)" --rpc-url "$RPC")"
echo "    symbol:      $(cast call "$TOKEN" "symbol()(string)" --rpc-url "$RPC")"
echo "    decimals:    $(cast call "$TOKEN" "decimals()(uint8)" --rpc-url "$RPC")"
echo "    totalSupply: $(supply) HFT"
echo "    MAX_SUPPLY:  $(cast call "$TOKEN" "MAX_SUPPLY()" --rpc-url "$RPC" | cast --from-wei) HFT"
echo "    owner:       $(cast call "$TOKEN" "owner()(address)" --rpc-url "$RPC")"
echo "    $OWNER:    $OWNER_ADDR ($(balance "$OWNER_ADDR") HFT)"
echo "    recipient:   $DEMO_RECIPIENT ($(balance "$DEMO_RECIPIENT") HFT)"

[ "$(cast call "$TOKEN" "owner()(address)" --rpc-url "$RPC" | tr 'A-F' 'a-f')" = "$(tr 'A-F' 'a-f' <<< "$OWNER_ADDR")" ] \
    || die "$OWNER is not the token owner"
[ "$(tr 'A-F' 'a-f' <<< "$DEMO_RECIPIENT")" != "$(tr 'A-F' 'a-f' <<< "$OWNER_ADDR")" ] \
    || die "recipient is the token owner: use another address"

if [ "$(cast call "$TOKEN" "balanceOf(address)(uint256)" "$OWNER_ADDR" --rpc-url "$RPC" | awk '{print $1}')" != "0" ]; then
    step "Owner transfers 100 HFT to recipient"
    send "$TOKEN" "transfer(address,uint256)" "$DEMO_RECIPIENT" 100e18
    ok "recipient balance: $(balance "$DEMO_RECIPIENT") HFT"
fi

step "Owner mints 1000 HFT to recipient"
send "$TOKEN" "mint(address,uint256)" "$DEMO_RECIPIENT" 1000e18
ok "recipient balance: $(balance "$DEMO_RECIPIENT") HFT, totalSupply: $(supply) HFT"

step "Recipient (not owner) tries to mint (simulation)"
expect_revert_from "$DEMO_RECIPIENT" "$TOKEN" "mint(address,uint256)" "$DEMO_RECIPIENT" 1000e18

MAX=$(cast call "$TOKEN" "MAX_SUPPLY()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
SUPPLY=$(cast call "$TOKEN" "totalSupply()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
ABOVE_CAP=$(bc <<< "$MAX - $SUPPLY + 1")
step "Owner tries to mint 1 unit more than what is left before MAX_SUPPLY (simulation)"
expect_revert_from "$OWNER_ADDR" "$TOKEN" "mint(address,uint256)" "$DEMO_RECIPIENT" "$ABOVE_CAP"

RECIPIENT_BALANCE=$(cast call "$TOKEN" "balanceOf(address)(uint256)" "$DEMO_RECIPIENT" --rpc-url "$RPC" | awk '{print $1}')
TOO_MUCH=$(bc <<< "$RECIPIENT_BALANCE + 10^18")
step "Recipient tries to transfer its balance + 1 HFT (simulation)"
expect_revert_from "$DEMO_RECIPIENT" "$TOKEN" "transfer(address,uint256)" "$OWNER_ADDR" "$TOO_MUCH"
