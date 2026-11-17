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

: "${DB_NAME:?DB_NAME manquant}"
: "${DB_USER:?DB_USER manquant}"
: "${DB_PASSWORD:?DB_PASSWORD manquant}"
: "${REPLICATION_USER:?REPLICATION_USER manquant}"
: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD manquant}"

export DEBIAN_FRONTEND=noninteractive

log() { echo "[bdd.sh] $*"; }

# 1. Installation de PostgreSQL, seulement s'il n'est pas déjà là
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
FICHIER_NOEUDS=/vagrant/config/noeuds.yml
IP_BDD2="$(python3 -c "import sys, yaml; print(next(n['ip'] for n in yaml.safe_load(open(sys.argv[1])) if n['role'] == 'replique'))" "$FICHIER_NOEUDS")/32"
RESEAU_PRIVE="${IP_BDD2%.*}.0/24"

systemctl enable --now postgresql >/dev/null 2>&1

# 2. Configuration serveur dans conf.d (fichier entièrement géré par ce script)
mkdir -p "$CONF_D"
tmp_conf="$(mktemp)"
cat > "$tmp_conf" <<'EOF'
# Géré par scripts/bdd.sh : ne pas modifier à la main
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

# 3. pg_hba.conf : un bloc balisé, remplacé à chaque exécution (jamais de doublon)
DEBUT="# >>> resultats-bf >>>"
FIN="# <<< resultats-bf <<<"
tmp_hba="$(mktemp)"
sed "/^${DEBUT}\$/,/^${FIN}\$/d" "$HBA" > "$tmp_hba"
cat >> "$tmp_hba" <<EOF
${DEBUT}
host    ${DB_NAME}      ${DB_USER}           ${RESEAU_PRIVE}   scram-sha-256
host    replication     ${REPLICATION_USER}  ${IP_BDD2}        scram-sha-256
${FIN}
EOF

NEED_RELOAD=0
if ! cmp -s "$tmp_hba" "$HBA"; then
  install -o postgres -g postgres -m 640 "$tmp_hba" "$HBA"
  NEED_RELOAD=1
  log "pg_hba.conf mis à jour"
fi
rm -f "$tmp_hba"

if [ "$NEED_RESTART" -eq 1 ]; then
  systemctl restart postgresql
elif [ "$NEED_RELOAD" -eq 1 ]; then
  systemctl reload postgresql
fi

# Attendre que le serveur accepte les connexions
for _ in $(seq 1 30); do
  sudo -u postgres pg_isready -q && break
  sleep 1
done

# 4 et 5. Utilisateurs, base, table et données.
# Les mots de passe passent par l'environnement (\getenv), pas par la ligne de commande.
sudo --preserve-env=DB_NAME,DB_USER,DB_PASSWORD,REPLICATION_USER,REPLICATION_PASSWORD \
  -u postgres psql -v ON_ERROR_STOP=1 -q -d postgres -f - <<'SQL'
\getenv db_name DB_NAME
\getenv db_user DB_USER
\getenv db_pass DB_PASSWORD
\getenv repl_user REPLICATION_USER
\getenv repl_pass REPLICATION_PASSWORD

-- Utilisateur applicatif : créé avec son mot de passe, seulement s'il n'existe pas
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_pass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'db_user') \gexec

-- Rôle de réplication : créé avec son mot de passe, seulement s'il n'existe pas
SELECT format('CREATE ROLE %I REPLICATION LOGIN PASSWORD %L', :'repl_user', :'repl_pass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'repl_user') \gexec

-- Base de données
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name') \gexec

\connect :"db_name"

CREATE TABLE IF NOT EXISTS resultats (
  matricule text PRIMARY KEY,
  nom       text NOT NULL,
  serie     text NOT NULL,
  moyenne   numeric(4,2) NOT NULL,
  admis     boolean NOT NULL
);
ALTER TABLE resultats OWNER TO :"db_user";

-- 50 000 lignes, seulement si la table est vide
INSERT INTO resultats (matricule, nom, serie, moyenne, admis)
SELECT 'BF' || lpad(i::text, 6, '0'),
       'Candidat ' || i,
       (ARRAY['A','C','D','E','F'])[1 + i % 5],
       m,
       m >= 10
FROM (
  SELECT i, round(((i * 7919) % 2001) / 100.0, 2) AS m
  FROM generate_series(1, 50000) AS i
) AS t
WHERE NOT EXISTS (SELECT 1 FROM resultats);
SQL

log "Terminé : $(sudo -u postgres psql -At -d "$DB_NAME" -c 'SELECT count(*) FROM resultats') lignes dans resultats"