# Hbaduel42Token (HFT)

Token BEP-20 sur le **BNB Smart Chain Testnet**, contrôlé par un multisig 2 sur 3 (`MultiSig42`).

| | |
|---|---|
| Nom / ticker | `Hbaduel42Token` / `HFT` |
| Décimales | 18 |
| Supply | 1 000 000 HFT au déploiement, plafond 10 000 000 HFT |
| Réseau | BNB Smart Chain Testnet (chain ID 97) |

## Contrats déployés

Vérifiés sur [BscScan](https://testnet.bscscan.com). Adresses aussi dans [`deployment/bsc-testnet.env`](deployment/bsc-testnet.env).

| Déploiement | Contrat | Adresse |
|---|---|---|
| Bonus (`make deploy-bsc`) | `MultiSig42` | [`0xC8B5413704B7b30AeBf3c22Bf93EA6f87cC91108`](https://testnet.bscscan.com/address/0xC8B5413704B7b30AeBf3c22Bf93EA6f87cC91108) |
| | `Hbaduel42Token` (owner : le multisig) | [`0x2A78D9394a3a710F9677129011CFfD0bC4E969BF`](https://testnet.bscscan.com/token/0x2A78D9394a3a710F9677129011CFfD0bC4E969BF) |
| Obligatoire (`make deploy-bsc-token`) | `Hbaduel42Token` (owner : un wallet) | [`0x3c154Cc8B5fb06E0563164BBB9F4A6E0aC0F85E6`](https://testnet.bscscan.com/token/0x3c154Cc8B5fb06E0563164BBB9F4A6E0aC0F85E6) |

| Rôle | Adresse |
|---|---|
| Signataires du multisig (seuil 2) | `0x5e3a497D5DA4FC6bc326D01A056ef8c52e64e9DA`, `0x1a81a51cB92ba3265E92f6b1D3ad733cc17e60d6`, `0xb4e6Bee4ce724869C66177566027eec3C456A24A` |
| Owner du token seul | `0x5e3a497D5DA4FC6bc326D01A056ef8c52e64e9DA` |
| Receiver de la supply initiale du token seul | `0x8558624a967087D7491EF02481Cf4A66C6A36f4C` |

## Choix

**BNB Smart Chain** : projet en partenariat avec BNB Chain, compatible EVM (mêmes outils qu'Ethereum), frais faibles,
testnet gratuit. BEP-20 est l'interface ERC-20 appliquée à BSC.

**Solidity + OpenZeppelin** : le token hérite d'`ERC20` et `Ownable`, audités et éprouvés. Seule la logique propre
au projet est écrite à la main : le mint réservé à l'owner et le plafond.

**Foundry** : tests en Solidity, sans JavaScript. `forge` compile, teste et déploie ; `cast` interagit avec les
contrats ; `anvil` simule une blockchain locale.

**Mint plafonné** : l'owner peut créer des tokens, mais jamais au-delà de `MAX_SUPPLY` (constante, contrat non
upgradable), pour protéger les détenteurs de la dilution. Pas de burn : non requis, une fonction de moins à sécuriser.

**Owner et receiver séparés** : l'adresse qui peut minter n'est pas celle qui reçoit la supply initiale. Une clé
volée ne donne pas les deux pouvoirs.

## Bonus : multisig

Dans la partie obligatoire, l'owner est une clé unique : si elle est volée, le voleur peut minter. Le bonus confie
l'ownership **et** la supply initiale à `MultiSig42` : toute action passe par 3 étapes,
`submitTransaction` → `confirmTransaction` (2 signataires sur 3) → `executeTransaction`.

- **2 sur 3** : résiste à une clé volée (seule, elle ne suffit pas) et à une clé perdue (les deux autres suffisent).
- **Seuil et signataires immuables** : aucune fonction ne permet de les changer, donc personne ne peut affaiblir les règles.
- **`execute` séparé** : on peut encore révoquer une confirmation avant l'exécution, et réessayer après un échec.
- **Checks-Effects-Interactions** : la transaction est marquée exécutée avant l'appel externe, contre la réentrance.
- **Cible obligatoirement un contrat** : un appel vers un wallet réussirait sans rien faire ; une adresse erronée est
  donc refusée dès le `submit`.
- **Pas de BNB** : le multisig ne sert qu'à piloter le token, il n'envoie ni ne reçoit de BNB (moins de surface d'attaque).

## Structure

```
code/            contrats : Hbaduel42Token.sol, MultiSig42.sol
test/            tests Foundry des deux contrats
deployment/      script de déploiement, scripts de démo, adresses déployées
documentation/   fonctionnement et utilisation du token et du multisig
```

## Utilisation

```bash
make install      # installe Foundry si absent, télécharge les dépendances (submodules), compile
make test         # lance tous les tests
make anvil        # démo complète sur une blockchain locale (aucune clé ni tBNB requis)
make help         # liste toutes les commandes
```

**Sur le BSC Testnet** (un compte avec un peu de tBNB, obtenu via un faucet) :

```bash
cp .env.example .env       # à remplir : adresses, clé API BscScan
make deploy-bsc            # déploie et vérifie MultiSig42 + Hbaduel42Token
make deploy-bsc-token      # déploie et vérifie le token seul
make demo-bsc              # démo du multisig sur les contrats déployés
make demo-bsc-token        # démo du token seul
```

Aucune clé privée n'est dans le repo : elle est importée une fois dans le keystore chiffré de Foundry
(`cast wallet import`, demandé automatiquement), puis débloquée par mot de passe à chaque utilisation.
