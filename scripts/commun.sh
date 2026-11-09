#!/usr/bin/env bash
# Rôle         : socle commun, exécuté sur toutes les machines avant le script du rôle
# Responsable  : architecte réseau
# Reçoit       : /vagrant/config/noeuds.yml
# Produit      : paquets de base installés en une seule fois,
#                noms des machines résolus via /etc/hosts
# Vérification : depuis app1, ping -c1 bdd1 répond ; rejouer ne change rien
set -euo pipefail

echo "[commun] à implémenter"
