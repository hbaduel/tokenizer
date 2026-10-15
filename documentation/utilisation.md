# Utilisation

Adresses des contrats : voir le [README](../README.md#contrats-déployés). Réseau : BNB Smart Chain Testnet (chain ID 97).

## 1. MetaMask

**Ajouter le réseau** (*Réseaux → Ajouter un réseau manuellement*) :

| Champ | Valeur |
|---|---|
| Nom | BNB Smart Chain Testnet |
| RPC | `https://data-seed-prebsc-1-s1.bnbchain.org:8545` |
| Chain ID | `97` |
| Symbole | `tBNB` |
| Explorateur | `https://testnet.bscscan.com` |

**Obtenir des tBNB** (pour payer le gas) : un faucet BNB testnet. Le faucet officiel exige un peu de BNB sur le
mainnet ; https://ghostchain.io/faucet/bnb-testnet n'a pas cette condition.

**Afficher HFT** : *Tokens → Importer un token*, coller l'adresse du token. Symbole et décimales se remplissent seuls.

## 2. Le token `Hbaduel42Token`

| Fonction | Qui | Effet |
|---|---|---|
| `name()`, `symbol()`, `decimals()` | lecture | `Hbaduel42Token`, `HFT`, `18` |
| `totalSupply()`, `MAX_SUPPLY()` | lecture | supply actuelle, supply maximale |
| `balanceOf(compte)` | lecture | solde d'un compte |
| `owner()` | lecture | adresse autorisée à minter |
| `transfer(to, amount)` | tout détenteur | envoie ses HFT |
| `approve(spender, amount)` | tout détenteur | autorise `spender` à dépenser jusqu'à `amount` de ses HFT |
| `allowance(owner, spender)` | lecture | autorisation restante |
| `transferFrom(from, to, amount)` | le `spender` autorisé | envoie des HFT de `from`, dans la limite de l'autorisation |
| `mint(to, amount)` | owner | crée des HFT, sans dépasser `MAX_SUPPLY` |
| `transferOwnership(newOwner)`, `renounceOwnership()` | owner | transmet ou abandonne le rôle d'owner |

Les montants sont en unités de base : **1 HFT = 10¹⁸**. Pour 1000 HFT, saisir `1000000000000000000000`
(dans BscScan, le bouton `+` à côté du champ propose d'ajouter les zéros).

Erreurs propres au projet : `ExceedsMaximumSupply(dépassement, MAX_SUPPLY)`. Les autres viennent d'OpenZeppelin
(`OwnableUnauthorizedAccount`, `ERC20InsufficientBalance`, `ERC20InsufficientAllowance`, `ERC20InvalidReceiver`…).

## 3. Le multisig `MultiSig42`

| Fonction | Qui | Effet |
|---|---|---|
| `getOwners()`, `nbConfirmationsRequired()` | lecture | signataires, seuil |
| `getTransactionCount()`, `transactions(i)` | lecture | nombre de transactions, détail de la n° `i` |
| `isConfirmed(i, signataire)` | lecture | ce signataire a-t-il confirmé `i` ? |
| `submitTransaction(to, data)` | signataire | propose l'appel `data` sur le contrat `to` |
| `confirmTransaction(i)` | signataire | confirme `i` (une fois par signataire) |
| `revokeConfirmation(i)` | signataire | retire sa confirmation, tant que `i` n'est pas exécutée |
| `executeTransaction(i)` | signataire | exécute `i` si le seuil est atteint |

`data` est l'appel encodé (ABI) : sélecteur de la fonction (4 octets) suivi des arguments. Pour le produire :

```bash
cast calldata "mint(address,uint256)" <destinataire> 1000e18
cast calldata "transfer(address,uint256)" <destinataire> 500e18
```

### Minter via le multisig, depuis BscScan

1. Générer `data` avec `cast calldata` (ci-dessus).
2. Page du multisig → *Contract* → *Write Contract* → *Connect to Web3* (MetaMask, compte signataire).
3. `submitTransaction` : `to` = adresse du token, `data` = la valeur générée. L'index `i` apparaît dans l'event
   `TransactionSubmitted` (ou `getTransactionCount() - 1`).
4. Deux signataires appellent `confirmTransaction(i)`.
5. Un signataire appelle `executeTransaction(i)`.

Même chose en ligne de commande :

```bash
cast send <multisig> "submitTransaction(address,bytes)" <token> <data> --account <signataire> --rpc-url bsc_testnet --legacy
cast send <multisig> "confirmTransaction(uint256)" <i>              --account <signataire> --rpc-url bsc_testnet --legacy
cast send <multisig> "executeTransaction(uint256)" <i>              --account <signataire> --rpc-url bsc_testnet --legacy
```

### Erreurs du multisig

| Erreur | Cause |
|---|---|
| `NotAnOwner` | l'appelant n'est pas signataire |
| `TransactionDoesNotExist` | index inconnu |
| `TransactionToZeroAddress`, `TransactionToNonContractAddress` | la cible n'est pas un contrat |
| `TransactionAlreadyConfirmed`, `TransactionNotConfirmed` | double confirmation, ou révocation sans confirmation |
| `NotEnoughConfirmations` | seuil pas encore atteint |
| `TransactionAlreadyExecuted` | transaction déjà exécutée |
| `TransactionExecutionFailed` | l'appel a échoué côté token (ex : `ExceedsMaximumSupply`) ; rien n'est modifié, on peut réessayer |

## 4. Vérifier sur BscScan

| Où | Ce qu'on y voit |
|---|---|
| Token → *Transfers* | chaque transfert ; un mint apparaît comme un transfert depuis `0x0000…0000` |
| Token → *Holders* | répartition des HFT |
| Multisig → *Events* | `TransactionSubmitted`, `TransactionConfirmed` (avec le signataire), `TransactionRevoked`, `TransactionExecuted` |
| *Read Contract* des deux contrats | état actuel : soldes, supply, `transactions(i)`, `isConfirmed` |
