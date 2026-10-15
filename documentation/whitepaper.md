# Hbaduel42Token (HFT) — Whitepaper

## Objet

HFT est un token **pédagogique**, réalisé dans le cadre du projet Tokenizer de 42. Il est déployé uniquement sur
le BNB Smart Chain Testnet : il n'a aucune valeur et ne fait l'objet d'aucune vente.

## Cas d'usage envisagé

Un token communautaire « pour le fun », par exemple pour un streamer :

- le streamer et deux modérateurs sont les **3 signataires** du multisig ;
- la **trésorerie** (supply initiale) et le **mint** servent à récompenser les viewers (événements, concours) ;
- aucune décision ne dépend d'une seule personne : chaque distribution doit être validée par 2 des 3 signataires ;
- le **plafond** garantit à la communauté que le nombre de tokens ne pourra jamais dépasser 10 000 000.

## Tokenomics

| | |
|---|---|
| Supply initiale | 1 000 000 HFT, détenus par le multisig (trésorerie) |
| Supply maximale | 10 000 000 HFT, inscrite dans le contrat et non modifiable |
| Émission | mint par le multisig uniquement (2 signatures sur 3) |
| Burn | aucun |

## Gouvernance

| Action | Qui |
|---|---|
| Transférer ses propres HFT | tout détenteur |
| Minter, distribuer la trésorerie | le multisig, après 2 confirmations sur 3 |
| Changer les règles (plafond, seuil, signataires) | personne : elles sont fixées au déploiement |

## Limites

- Pas de fonctionnalité au-delà du standard BEP-20 (pas de burn, de pause, de vote).
- Le token ne représente aucun droit ni aucune valeur.
- Les signataires ne peuvent pas être remplacés : en cas de changement d'équipe, il faut déployer un nouveau multisig
  et lui transférer l'ownership et la trésorerie par un vote de l'ancien.
