#!/usr/bin/env bash
# Rôle         : bascule de la base, lancée depuis l'hôte : promeut bdd2 en base principale
# Responsable  : ingénieur données
# Reçoit       : rien en argument ; lit config/noeuds.yml ; bdd2 doit tourner (bdd1 peut être éteinte)
# Produit      : bdd2 principale (pg_is_in_recovery() = f), adresse de bdd2 dans config/primaire,
#                durée totale affichée en secondes
# Vérification : sur bdd2, SELECT pg_is_in_recovery() renvoie f ;
#                relancer le script répond que bdd2 est déjà principale, sans erreur

set -euo pipefail

# Le script se place lui-même à la racine du dépôt, d'où qu'il soit lancé
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RACINE"

log() { echo "[bascule] $*"; }
erreur() { echo "[bascule] ERREUR : $*" >&2; exit 1; }

# Heure en millisecondes (repli sur les secondes si date ne sait pas faire)
maintenant_ms() {
  local t
  t="$(date +%s%3N 2>/dev/null || true)"
  case "$t" in
    ""|*[!0-9]*) t=$(( $(date +%s) * 1000 )) ;;
  esac
  echo "$t"
}

# Adresse du nœud de rôle "replique" dans config/noeuds.yml (sans python : l'hôte n'en a pas forcément)
ip_replique() {
  awk '
    /^- / {
      if (role == "replique" && ip != "") { fini = 1; exit }
      ip = ""; role = ""
    }
    {
      ligne = $0
      sub(/^- /, "  ", ligne)
    }
    ligne ~ /^  ip:/   { v = ligne; sub(/^  ip:[ \t]*/, "", v);   gsub(/["\r]/, "", v); ip = v }
    ligne ~ /^  role:/ { v = ligne; sub(/^  role:[ \t]*/, "", v); gsub(/["\r]/, "", v); role = v }
    END { if (role == "replique" && ip != "") print ip }
  ' config/noeuds.yml
}

# Exécute une requête SQL sur bdd2 et renvoie la réponse sans espaces ni retours à la ligne
sur_bdd2() {
  vagrant ssh bdd2 -c "sudo -u postgres psql -At -c \"$1\"" 2>/dev/null | tr -d '[:space:]'
}

ecrire_primaire() {
  mkdir -p config
  printf '%s\n' "$IP_BDD2" > config/primaire
  log "Adresse de la base principale écrite dans config/primaire : ${IP_BDD2}"
}

debut="$(maintenant_ms)"

[ -f Vagrantfile ] || erreur "Vagrantfile introuvable dans ${RACINE}"
[ -f config/noeuds.yml ] || erreur "config/noeuds.yml absent : lance d'abord une commande vagrant (par exemple vagrant status)"

IP_BDD2="$(ip_replique)"
[ -n "$IP_BDD2" ] || erreur "adresse de bdd2 introuvable dans config/noeuds.yml"

# 1. bdd2 est-elle bien une réplique ?
log "Vérification de l'état de bdd2 (${IP_BDD2})"
if ! etat="$(sur_bdd2 'SELECT pg_is_in_recovery()')"; then
  erreur "bdd2 injoignable : est-elle démarrée (vagrant up bdd2) ?"
fi

case "$etat" in
  t) ;;
  f)
    log "bdd2 est déjà la base principale : rien à faire"
    [ -f config/primaire ] || ecrire_primaire
    exit 0
    ;;
  *) erreur "réponse inattendue de bdd2 : '${etat}'" ;;
esac

# 2. Promotion
log "Promotion de bdd2"
if ! res="$(sur_bdd2 'SELECT pg_promote()')"; then
  erreur "la commande de promotion a échoué"
fi
[ "$res" = "t" ] || erreur "pg_promote() a renvoyé '${res}' au lieu de t"

# 3. Attendre que bdd2 sorte du mode réplique (60 s au plus)
etat="t"
for _ in $(seq 1 120); do
  etat="$(sur_bdd2 'SELECT pg_is_in_recovery()' || true)"
  if [ "$etat" = "f" ]; then break; fi
  sleep 0.5
done
[ "$etat" = "f" ] || erreur "bdd2 est toujours en réplique après 60 secondes"

# 4. Dire aux serveurs applicatifs où est la base principale
ecrire_primaire

# 5. Durée totale
fin="$(maintenant_ms)"
duree="$(awk -v d="$(( fin - debut ))" 'BEGIN { printf "%.1f", d / 1000 }')"
log "bdd2 est maintenant la base principale"
log "Durée totale de la bascule : ${duree} s"
