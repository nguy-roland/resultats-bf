#!/usr/bin/env bash
# Rôle         : répartiteur de charge (lb1)
# Responsable  : architecte réseau
# Reçoit       : nœuds de rôle app (ip, port) dans /vagrant/config/noeuds.yml
# Produit      : HAProxy à l'écoute sur 0.0.0.0:80, configuration engendrée depuis
#                noeuds.yml, sonde GET /sante, serveur défaillant écarté en moins de 5 s
# Vérification : 20 appels à http://localhost:8080/info depuis l'hôte
#                montrent tous les appN ; rejouer ne change rien
set -euo pipefail

echo "[lb] à implémenter"
