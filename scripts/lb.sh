#!/usr/bin/env bash
# Rôle         : répartiteur de charge (lb1)
# Responsable  : architecte réseau
# Reçoit       : nœuds de rôle app (ip, port) dans /vagrant/config/noeuds.yml
# Produit      : HAProxy à l'écoute sur 0.0.0.0:80, configuration engendrée depuis
#                noeuds.yml, sonde GET /sante, serveur défaillant écarté en moins de 5 s
#                avec E1 : keepalived partage l'adresse virtuelle avec l'autre répartiteur
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

# Métriques au format Prometheus, lues par la machine obs (E2).
frontend metriques
    bind 0.0.0.0:8405
    http-request use-service prometheus-exporter if { path /metrics }
    no log

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



# Extension E1 : keepalived partage l'adresse virtuelle entre lb1 et lb2 (VRRP).
# Tout est lu dans la ligne de cette machine dans la table des nœuds.
eval "$(python3 - "$FICHIER_NOEUDS" "$(hostname)" << 'PYTHON'
import sys, yaml
with open(sys.argv[1]) as fichier:
    noeuds = yaml.safe_load(fichier)
moi = next(noeud for noeud in noeuds if noeud["nom"] == sys.argv[2])
repartiteurs = [noeud for noeud in noeuds if noeud["role"] == "lb"]
priorite_max = max(noeud.get("priorite", 0) for noeud in repartiteurs)
print(f"MON_IP={moi['ip']}")
print(f"ADRESSE_VIRTUELLE={moi.get('vip', '')}")
print(f"PRIORITE={moi.get('priorite', '')}")
print(f"ETAT={'MASTER' if moi.get('priorite') == priorite_max else 'BACKUP'}")
print(f"PAIRS='{' '.join(noeud['ip'] for noeud in repartiteurs if noeud['nom'] != moi['nom'])}'")
PYTHON
)"

if [ -z "$ADRESSE_VIRTUELLE" ]; then
  # E1 désactivée : keepalived arrêté s'il avait été installé.
  if command -v keepalived > /dev/null; then
    systemctl disable --quiet --now keepalived
  fi
  echo "[lb] E1 désactivée"
  exit 0
fi

if ! command -v keepalived > /dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq keepalived
fi

# Interface du réseau privé : celle qui porte l'adresse de cette machine.
INTERFACE=$(ip -o -4 addr show | awk -v ip="$MON_IP" '{ split($4, adresse, "/"); if (adresse[1] == ip) print $2 }')
# Identifiant VRRP unique par groupe : le troisième octet du réseau (58).
ID_ROUTEUR=$(echo "$MON_IP" | cut -d. -f3)
LIGNES_PAIRS=$(for pair in $PAIRS; do echo "        $pair"; done)

CONFIG_KEEPALIVED_TEMPORAIRE=$(mktemp)
trap 'rm -f "$CONFIG_TEMPORAIRE" "$CONFIG_KEEPALIVED_TEMPORAIRE"' EXIT

cat > "$CONFIG_KEEPALIVED_TEMPORAIRE" << CONFIG
global_defs {
    router_id $(hostname)
    enable_script_security
    script_user root
}

# Si HAProxy ne tourne plus ici, ce répartiteur abandonne l'adresse virtuelle.
vrrp_script haproxy_actif {
    script "/usr/bin/systemctl is-active --quiet haproxy"
    interval 1
    fall 2
    rise 2
}

vrrp_instance resultats {
    state ${ETAT}
    interface ${INTERFACE}
    virtual_router_id ${ID_ROUTEUR}
    priority ${PRIORITE}
    advert_int 1
    unicast_src_ip ${MON_IP}
    unicast_peer {
${LIGNES_PAIRS}
    }
    virtual_ipaddress {
        ${ADRESSE_VIRTUELLE}/24 dev ${INTERFACE}
    }
    track_script {
        haproxy_actif
    }
}
CONFIG

keepalived -t -f "$CONFIG_KEEPALIVED_TEMPORAIRE"
if cmp -s "$CONFIG_KEEPALIVED_TEMPORAIRE" /etc/keepalived/keepalived.conf; then
  echo "[lb] keepalived inchangé"
else
  install -m 644 "$CONFIG_KEEPALIVED_TEMPORAIRE" /etc/keepalived/keepalived.conf
  systemctl reload-or-restart keepalived
  echo "[lb] keepalived mis à jour : $(hostname) en ${ETAT}, priorité ${PRIORITE}"
fi
systemctl enable --quiet keepalived
systemctl is-active --quiet keepalived || systemctl start keepalived