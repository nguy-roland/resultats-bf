#!/usr/bin/env bash
# Rôle         : socle commun, exécuté sur toutes les machines avant le script du rôle
# Responsable  : architecte réseau
# Reçoit       : /vagrant/config/noeuds.yml
# Produit      : paquets de base installés en une seule fois,
#                noms des machines résolus via /etc/hosts
# Vérification : depuis app1, ping -c1 bdd1 répond ; rejouer ne change rien
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

NOEUDS=${NOEUDS:-/vagrant/config/noeuds.yml}
HOSTS=${HOSTS:-/etc/hosts}

# --- 1. Paquets de base : un seul apt-get, et seulement s'il manque quelque chose ---
PAQUETS="curl ca-certificates iputils-ping"
manquants=""
for p in $PAQUETS; do
  dpkg -s "$p" >/dev/null 2>&1 || manquants="$manquants $p"
done
if [ -n "$manquants" ]; then
  apt-get update -qq
  apt-get install -y -qq $manquants   # sans guillemets : une liste de paquets
fi

# --- 2. Noms des machines : bloc /etc/hosts engendré depuis noeuds.yml ---
# tr -d '\r' : le fichier peut avoir des fins de ligne Windows
BLOC=$(tr -d '\r' < "$NOEUDS" | awk '
  BEGIN { print "# BEGIN resultats-bf (genere depuis noeuds.yml)" }
  /^- nom:/ { nom = $3 }
  /^  ip:/  { print $2, nom }
  END   { print "# END resultats-bf" }')

NOUVEAU=$(mktemp)
# l'ancien bloc est retiré, puis le nouveau est ajouté : le résultat est toujours le même
sed '/^# BEGIN resultats-bf/,/^# END resultats-bf/d' "$HOSTS" > "$NOUVEAU"
if [ -s "$NOUVEAU" ] && [ -n "$(tail -c1 "$NOUVEAU")" ]; then echo >> "$NOUVEAU"; fi
printf '%s\n' "$BLOC" >> "$NOUVEAU"

if cmp -s "$NOUVEAU" "$HOSTS"; then
  echo "[commun] /etc/hosts déjà à jour"
else
  cat "$NOUVEAU" > "$HOSTS"
  echo "[commun] /etc/hosts mis à jour"
fi
rm -f "$NOUVEAU"