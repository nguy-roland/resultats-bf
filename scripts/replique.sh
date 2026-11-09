#!/usr/bin/env bash
# Rôle         : réplique en flux (bdd2)
# Responsable  : ingénieur données
# Reçoit       : REPLICATION_USER, REPLICATION_PASSWORD ; adresse de bdd1 dans noeuds.yml
# Produit      : PostgreSQL en lecture seule, répliqué en flux depuis bdd1, promouvable
# Vérification : une ligne insérée sur bdd1 est lisible sur bdd2 (R5) ;
#                rejouer ne change rien
set -euo pipefail

echo "[replique] à implémenter"
