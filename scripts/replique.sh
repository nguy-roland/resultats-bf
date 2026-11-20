#!/usr/bin/env bash
# Rôle         : base de données réplique (bdd2)
# Responsable  : ingénieur données
# Reçoit       : DB_NAME, DB_USER, REPLICATION_USER, REPLICATION_PASSWORD
# Produit      : PostgreSQL en réplique en flux de bdd1 (pg_basebackup -R), prête à être
#                promue ; application autorisée dans pg_hba.conf après une bascule
# Vérification : sur bdd2, SELECT pg_is_in_recovery() renvoie t ;
#                une ligne insérée sur bdd1 apparaît sur bdd2 ; rejouer ne refait pas la copie

set -euo pipefail

: "${DB_NAME:?DB_NAME manquant}"
: "${DB_USER:?DB_USER manquant}"
: "${REPLICATION_USER:?REPLICATION_USER manquant}"
: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD manquant}"

export DEBIAN_FRONTEND=noninteractive

log() { echo "[replique.sh] $*"; }

# 1. Installation de PostgreSQL, seulement s'il est absent
if dpkg -s postgresql python3-yaml >/dev/null 2>&1; then
  log "PostgreSQL déjà installé"
else
  log "Installation de PostgreSQL"
  apt-get update -qq
  apt-get install -y -qq postgresql python3-yaml
fi

PG_VERSION="$(ls /usr/lib/postgresql | sort -V | tail -n 1)"
PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
CONF_D="${PG_CONF_DIR}/conf.d"
HBA="${PG_CONF_DIR}/pg_hba.conf"
DATADIR="/var/lib/postgresql/${PG_VERSION}/main"
MARQUEUR="/var/lib/postgresql/replique-initialisee"

# 2. Adresse de bdd1 lue dans la table des nœuds (même source que bdd.sh)
FICHIER_NOEUDS=/vagrant/config/noeuds.yml
IP_BDD1="$(python3 -c "import sys, yaml; print(next(n['ip'] for n in yaml.safe_load(open(sys.argv[1])) if n['role'] == 'bdd'))" "$FICHIER_NOEUDS")"
RESEAU_PRIVE="${IP_BDD1%.*}.0/24"

# 3. Configuration serveur : identique à bdd1, pour que bdd2 se comporte pareil une fois promue
mkdir -p "$CONF_D"
tmp_conf="$(mktemp)"
cat > "$tmp_conf" <<'EOF'
# Géré par scripts/replique.sh : ne pas modifier à la main
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
EOF

NEED_RESTART=0
if ! cmp -s "$tmp_conf" "${CONF_D}/10-resultats-bf.conf" 2>/dev/null; then
  install -o postgres -g postgres -m 644 "$tmp_conf" "${CONF_D}/10-resultats-bf.conf"
  NEED_RESTART=1
  log "Configuration serveur mise à jour"
fi
rm -f "$tmp_conf"

# 4. pg_hba.conf : mêmes autorisations que bdd1 pour l'application (bloc balisé, jamais de doublon)
DEBUT="# >>> resultats-bf >>>"
FIN="# <<< resultats-bf <<<"
tmp_hba="$(mktemp)"
sed "/^${DEBUT}\$/,/^${FIN}\$/d" "$HBA" > "$tmp_hba"
cat >> "$tmp_hba" <<EOF
${DEBUT}
host    ${DB_NAME}      ${DB_USER}           ${RESEAU_PRIVE}   scram-sha-256
${FIN}
EOF

NEED_RELOAD=0
if ! cmp -s "$tmp_hba" "$HBA"; then
  install -o postgres -g postgres -m 640 "$tmp_hba" "$HBA"
  NEED_RELOAD=1
  log "pg_hba.conf mis à jour"
fi
rm -f "$tmp_hba"

# 5. Copie depuis bdd1, seulement si bdd2 n'est pas déjà une réplique.
# standby.signal = déjà une réplique. Le marqueur évite d'effacer une réplique
# déjà promue (elle n'a plus standby.signal mais contient les données).
if [ -f "${DATADIR}/standby.signal" ]; then
  log "bdd2 est déjà une réplique, rien à refaire"
elif [ -f "$MARQUEUR" ]; then
  log "bdd2 a déjà été copiée puis promue : aucune copie refaite"
else
  log "Attente de bdd1 (${IP_BDD1})"
  pret=0
  for _ in $(seq 1 60); do
    if pg_isready -q -h "$IP_BDD1" -p 5432; then pret=1; break; fi
    sleep 2
  done
  if [ "$pret" -ne 1 ]; then
    log "ERREUR : bdd1 ne répond pas sur ${IP_BDD1}:5432"
    exit 1
  fi

  log "Copie depuis bdd1 (pg_basebackup)"
  systemctl stop postgresql
  find "$DATADIR" -mindepth 1 -delete
  PGPASSWORD="$REPLICATION_PASSWORD" sudo --preserve-env=PGPASSWORD -u postgres \
    pg_basebackup -h "$IP_BDD1" -p 5432 -U "$REPLICATION_USER" -D "$DATADIR" -R -X stream -w
  touch "$MARQUEUR"
  systemctl start postgresql
  NEED_RESTART=0
  NEED_RELOAD=0
fi

if [ "$NEED_RESTART" -eq 1 ]; then
  systemctl restart postgresql
elif [ "$NEED_RELOAD" -eq 1 ]; then
  systemctl reload postgresql
fi

for _ in $(seq 1 30); do
  sudo -u postgres pg_isready -q && break
  sleep 1
done

log "Terminé : pg_is_in_recovery() = $(sudo -u postgres psql -At -c 'SELECT pg_is_in_recovery()')"
