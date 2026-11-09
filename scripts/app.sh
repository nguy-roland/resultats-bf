#!/usr/bin/env bash
# Rôle         : serveur applicatif (app1 … appN)
# Responsable  : ingénieur applicatif
# Reçoit       : DB_NAME, DB_USER, DB_PASSWORD ; code dans /vagrant/app ;
#                adresse de bdd1 et port de l'application dans noeuds.yml
# Produit      : service systemd sans état, à l'écoute sur 0.0.0.0:<port>,
#                avec GET /resultat, /sante (200 ou 503) et /info (nom d'hôte) ;
#                démarre même si la base est absente, et réessaie
# Vérification : curl http://<ip>:<port>/sante renvoie 200 si bdd1 répond, 503 sinon ;
#                rejouer ne change rien
set -euo pipefail

echo "[app] à implémenter"
