#!/usr/bin/env bash
# Rôle         : répartiteur de charge (lb1)
# Responsable  : architecte réseau
# Reçoit       : nœuds de rôle app (ip, port) dans /vagrant/config/noeuds.yml
# Produit      : HAProxy à l'écoute sur 0.0.0.0:80, configuration engendrée depuis
#                noeuds.yml, sonde GET /sante, serveur défaillant écarté en moins de 5 s
# Vérification : 20 appels à http://localhost:8080/info depuis l'hôte
#                montrent tous les appN ; rejouer ne change rien
set -euo pipefail

FICHIER_NOEUDS=/vagrant/config/noeuds.yml
FICHIER_CONFIG=/etc/haproxy/haproxy.cfg

# Installation, une seule fois.
if ! command -v haproxy > /dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq haproxy python3-yaml
fi

# Une ligne "server" par nœud de rôle app, lue dans la table des nœuds.
SERVEURS_APP=$(python3 - "$FICHIER_NOEUDS" << 'PYTHON'
import sys, yaml
with open(sys.argv[1]) as fichier:
    noeuds = yaml.safe_load(fichier)
for noeud in noeuds:
    if noeud["role"] == "app":
        print(f"    server {noeud['nom']} {noeud['ip']}:{noeud['port']} check")
PYTHON
)

# Configuration écrite d'abord dans un fichier temporaire, supprimé en sortie.
CONFIG_TEMPORAIRE=$(mktemp)
trap 'rm -f "$CONFIG_TEMPORAIRE"' EXIT

cat > "$CONFIG_TEMPORAIRE" << CONFIG
global
    log /dev/log local0
    user haproxy
    group haproxy
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    maxconn 2000

defaults
    mode http
    log global
    option httplog
    # Si un serveur ne répond pas, la requête est renvoyée vers un autre.
    option redispatch
    retries 2
    timeout connect 2s
    timeout client 10s
    timeout server 10s
    timeout check 1s

frontend resultats
    bind 0.0.0.0:80
    default_backend applications

# Sonde toutes les secondes : 2 échecs écartent un serveur, 2 succès le réintègrent.
backend applications
    balance roundrobin
    option httpchk GET /sante
    http-check expect status 200
    default-server inter 1s fall 2 rise 2
${SERVEURS_APP}

# Page d'état des serveurs, sur le port 8404 de lb1.
listen statistiques
    bind 0.0.0.0:8404
    stats enable
    stats uri /
    stats refresh 2s
CONFIG

# Validation, puis remplacement et rechargement seulement si la configuration a changé.
haproxy -c -q -f "$CONFIG_TEMPORAIRE"
if cmp -s "$CONFIG_TEMPORAIRE" "$FICHIER_CONFIG"; then
  echo "[lb] configuration inchangée"
else
  install -m 644 "$CONFIG_TEMPORAIRE" "$FICHIER_CONFIG"
  systemctl reload-or-restart haproxy
  echo "[lb] configuration mise à jour : $(grep -c '^    server ' "$FICHIER_CONFIG") serveurs applicatifs"
fi

systemctl enable --quiet haproxy
systemctl is-active --quiet haproxy || systemctl start haproxy
