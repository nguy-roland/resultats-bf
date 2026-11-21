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

: "${DB_NAME:?DB_NAME manquant}"
: "${DB_USER:?DB_USER manquant}"
: "${DB_PASSWORD:?DB_PASSWORD manquant}"

export DEBIAN_FRONTEND=noninteractive

log() { echo "[app.sh] $*"; }

FICHIER_NOEUDS=/vagrant/config/noeuds.yml
DEST=/opt/resultats-bf
CONF=/etc/resultats-bf
SERVICE=resultats-bf
changement=0

# 1. Dépendances : paquets apt, installés seulement s'ils manquent
manquants=()
for paquet in python3-psycopg2 python3-yaml gunicorn; do
  dpkg-query -W -f='${Status}' "$paquet" 2>/dev/null | grep -q "install ok installed" || manquants+=("$paquet")
done
if [ "${#manquants[@]}" -gt 0 ]; then
  log "Installation de : ${manquants[*]}"
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends "${manquants[@]}"
else
  log "Dépendances déjà installées"
fi

# 2. Adresse de bdd1 et port de cette machine, lus dans la table des nœuds (aucune adresse en dur)
lecture="$(python3 - "$FICHIER_NOEUDS" "$(hostname)" << 'PYTHON'
import sys, yaml
with open(sys.argv[1]) as fichier:
    noeuds = yaml.safe_load(fichier)
bdd = next(noeud for noeud in noeuds if noeud["nom"] == "bdd1")
moi = next(noeud for noeud in noeuds if noeud["nom"] == sys.argv[2])
print(bdd["ip"], moi["port"])
PYTHON
)"
read -r DB_HOST APP_PORT <<< "$lecture"

# Copie $1 vers $2 (droits $3) seulement si le contenu diffère, et note le changement.
deposer() {
  if ! cmp -s "$1" "$2"; then
    install -m "$3" "$1" "$2"
    changement=1
  fi
}
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# 3. Utilisateur système, code de l'application (copié hors de /vagrant, qui peut ne pas être monté au démarrage)
id resultats >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin resultats
install -d -m 755 "$DEST" "$CONF"
deposer /vagrant/app/server.py "$DEST/server.py" 644

# 4. Variables du service : fichier en droits 600, jamais dans le dépôt
chmod 600 "$tmp"
cat > "$tmp" << CONFIG
DB_HOST=$DB_HOST
DB_PORT=5432
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
CONFIG
deposer "$tmp" "$CONF/app.env" 600

# 5. Unité systemd
cat > "$tmp" << CONFIG
[Unit]
Description=Service HTTP RESULTATS-BF
After=network-online.target
Wants=network-online.target

[Service]
User=resultats
EnvironmentFile=$CONF/app.env
WorkingDirectory=$DEST
ExecStart=/usr/bin/gunicorn --bind 0.0.0.0:$APP_PORT --workers 2 --timeout 15 server:application
Restart=always
RestartSec=2
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
CONFIG
deposer "$tmp" "/etc/systemd/system/$SERVICE.service" 644

# 6. Démarrage : redémarrage seulement si quelque chose a changé
systemctl daemon-reload
systemctl enable --quiet "$SERVICE"
if [ "$changement" -eq 1 ]; then
  systemctl restart "$SERVICE"
  log "Service mis à jour et redémarré"
else
  systemctl start "$SERVICE"
  log "Service inchangé"
fi

# 7. Vérification : /info doit répondre (la base, elle, peut être absente)
for _ in $(seq 1 10); do
  curl -fs "http://127.0.0.1:$APP_PORT/info" >/dev/null && break
  sleep 1
done
if ! curl -fs "http://127.0.0.1:$APP_PORT/info" >/dev/null; then
  journalctl -u "$SERVICE" -n 20 --no-pager
  echo "[app.sh] ERREUR : le service ne répond pas sur le port $APP_PORT" >&2
  exit 1
fi
log "$(hostname) : service actif sur 0.0.0.0:$APP_PORT (bdd1 = $DB_HOST)"
