#!/usr/bin/env bash
# Rôle         : base de données primaire (bdd1)
# Responsable  : ingénieur données
# Reçoit       : DB_NAME, DB_USER, DB_PASSWORD, REPLICATION_USER, REPLICATION_PASSWORD
# Produit      : PostgreSQL à l'écoute sur 0.0.0.0:5432, table resultats
#                (matricule, nom, serie, moyenne, admis) de 50 000 lignes,
#                réplication autorisée depuis bdd2
# Vérification : depuis app1, SELECT count(*) FROM resultats renvoie 50000 ;
#                rejouer ne change rien
set -euo pipefail

echo "[bdd] à implémenter"
