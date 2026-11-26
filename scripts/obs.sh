#!/usr/bin/env bash
# Rôle         : supervision (obs), extension E2
# Responsable  : ingénieur essais et observabilité
# Reçoit       : GRAFANA_ADMIN_PASSWORD ; les cibles dans /vagrant/config/noeuds.yml :
#                node_exporter sur le port 9100 de chaque VM,
#                métriques HAProxy sur le port 8405 des répartiteurs (/metrics)
# Produit      : Prometheus qui collecte ces cibles, Grafana sur le port 3000 d'obs,
#                avec un tableau de bord : débit du répartiteur et état de chaque serveur applicatif
# Vérification : pendant une charge, le débit monte sur le tableau de bord ;
#                après vagrant halt app1, app1 passe à l'état DOWN ; rejouer ne change rien
set -euo pipefail

echo "[obs] à implémenter"
