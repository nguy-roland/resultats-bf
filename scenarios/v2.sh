#!/usr/bin/env bash
# Scénario V2 : panne d'un serveur applicatif (R4)
# Charge continue avec ab sur /resultat ; en cours de route, app1 est arrêtée (vagrant halt app1).
# Mesure les requêtes perdues et la durée de la période dégradée, puis relance app1.
# Attendu : le service reste disponible ; plus aucune erreur au-delà de 5 secondes.
# Usage : scenarios/v2.sh   (ADRESSE=http://192.168.58.10 scenarios/v2.sh pour passer par E1)
# Prérequis : ab (Apache Bench), curl, vagrant et un date GNU (Git Bash, Linux) ;
#             la plateforme est démarrée, avec au moins deux serveurs applicatifs.
set -euo pipefail
cd "$(dirname "$0")/.."

ADRESSE="${ADRESSE:-http://localhost:8080}"
URL="$ADRESSE/resultat?matricule=BF000123"
SERVEUR_ARRETE="app1"
CONCURRENCE=20
# La charge dure DUREE_TOTALE secondes ; la panne survient après DELAI_AVANT_PANNE.
# vagrant halt prend de quelques secondes à plus de vingt : il doit rester du temps de charge après.
DUREE_TOTALE="${DUREE_TOTALE:-75}"
DELAI_AVANT_PANNE="${DELAI_AVANT_PANNE:-15}"
SEUIL_MS=5000
NB_APP=$(cat .vagrant/nb_app 2>/dev/null || echo 2)
HORODATAGE=$(date +%F-%H%M%S)
FICHIER_MESURE="mesures/v2-$HORODATAGE.txt"
FICHIER_AB="mesures/v2-$HORODATAGE-ab.txt"
FICHIER_SONDES="mesures/v2-$HORODATAGE-sondes.txt"

for commande in ab curl vagrant; do
  command -v "$commande" > /dev/null || { echo "ERREUR : $commande est introuvable" >&2; exit 1; }
done
if [ "$NB_APP" -lt 2 ]; then
  echo "ERREUR : V2 exige au moins 2 serveurs applicatifs (NB_APP = $NB_APP)" >&2
  exit 1
fi
if [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$URL")" != "200" ]; then
  echo "ERREUR : $URL ne répond pas 200 avant la panne" >&2
  exit 1
fi
mkdir -p mesures

# Une sonde toutes les 0,1 s : horodatage en millisecondes et code HTTP (000 = pas de réponse).
sonder() {
  while true; do
    code=$(curl -s -o /dev/null -m 1 -w '%{http_code}' "$URL" || true)
    echo "$(date +%s%3N) $code"
    sleep 0.1
  done
}

PID_SONDES=""
PID_AB=""
SERVEUR_ARRETE_PAR_LE_TEST=0
# En sortie, même après une erreur : arrêter la charge et ne jamais laisser le serveur éteint.
nettoyer() {
  [ -n "$PID_SONDES" ] && kill "$PID_SONDES" 2> /dev/null || true
  [ -n "$PID_AB" ] && kill "$PID_AB" 2> /dev/null || true
  if [ "$SERVEUR_ARRETE_PAR_LE_TEST" -eq 1 ]; then
    echo "[v2] relance de $SERVEUR_ARRETE"
    vagrant up "$SERVEUR_ARRETE" > /dev/null 2>&1 || echo "[v2] ATTENTION : vagrant up $SERVEUR_ARRETE a échoué" >&2
  fi
}
trap nettoyer EXIT

sonder > "$FICHIER_SONDES" &
PID_SONDES=$!
ab -r -c "$CONCURRENCE" -t "$DUREE_TOTALE" "$URL" > "$FICHIER_AB" 2>&1 &
PID_AB=$!

sleep "$DELAI_AVANT_PANNE"
MOMENT_PANNE=$(date +%s%3N)
SERVEUR_ARRETE_PAR_LE_TEST=1
vagrant halt "$SERVEUR_ARRETE"
DUREE_HALT=$(( $(date +%s%3N) - MOMENT_PANNE ))

wait "$PID_AB" || true
PID_AB=""
kill "$PID_SONDES" 2> /dev/null || true
wait "$PID_SONDES" 2> /dev/null || true
PID_SONDES=""

# Sondes : nombre total, en erreur, début de la période dégradée après la panne (ms),
# durée entre la première et la dernière erreur (ms), code de la dernière sonde.
read -r SONDES_TOTAL SONDES_ERREUR DEBUT_APRES_PANNE DUREE_DEGRADEE DERNIER_CODE <<< "$(awk -v panne="$MOMENT_PANNE" '
  NF == 2 {
    total++
    dernier = $2
    if ($2 != 200) { erreurs++; if (debut == "") debut = $1; fin = $1 }
  }
  END {
    if (erreurs == 0) printf "%d 0 0 0 %s", total, dernier
    else printf "%d %d %d %d %s", total, erreurs, debut - panne, fin - debut, dernier
  }' "$FICHIER_SONDES")"

# ab : chiffres du résumé. Une requête perdue est une réponse non 2xx ou un échec de connexion,
# de réception ou une exception (les échecs « Length » sont déjà comptés parmi les non 2xx).
valeur() { grep -E "$1" "$FICHIER_AB" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | grep -oE '^[0-9]+(\.[0-9]+)?' || true; }
detail() { grep -oE "$1: [0-9]+" "$FICHIER_AB" | head -1 | grep -oE '[0-9]+' || true; }
REQUETES_TOTAL=$(valeur "^Complete requests")
NON_2XX=$(valeur "^Non-2xx responses")
ECHEC_CONNEXION=$(detail "Connect")
ECHEC_RECEPTION=$(detail "Receive")
EXCEPTIONS=$(detail "Exceptions")
DEBIT=$(valeur "^Requests per second")
PERDUES=$(( ${NON_2XX:-0} + ${ECHEC_CONNEXION:-0} + ${ECHEC_RECEPTION:-0} + ${EXCEPTIONS:-0} ))

if [ "$DERNIER_CODE" = "200" ] && [ "$DUREE_DEGRADEE" -le "$SEUIL_MS" ]; then
  VERDICT="conforme"
else
  VERDICT="NON conforme"
fi

{
  echo "date : $(date)"
  echo "commit : $(git rev-parse --short HEAD)"
  echo "NB_APP : $NB_APP"
  echo "adresse : $URL"
  echo "charge : ab, $CONCURRENCE connexions simultanées, $DUREE_TOTALE s"
  echo "panne : vagrant halt $SERVEUR_ARRETE après $DELAI_AVANT_PANNE s (la commande a duré $((DUREE_HALT / 1000)) s)"
  echo
  echo "requêtes traitées par ab : ${REQUETES_TOTAL:-inconnu}"
  echo "requêtes perdues (non 2xx, connexion, réception) : $PERDUES"
  echo "débit moyen : ${DEBIT:-inconnu} requêtes par seconde"
  echo
  echo "sondes (une toutes les 0,1 s) : $SONDES_ERREUR en erreur sur $SONDES_TOTAL"
  if [ "$SONDES_ERREUR" -gt 0 ]; then
    echo "première erreur : $((DEBUT_APRES_PANNE / 1000)),$(printf '%03d' $((DEBUT_APRES_PANNE % 1000))) s après le début de vagrant halt"
  fi
  echo "période dégradée : $DUREE_DEGRADEE ms (seuil : $SEUIL_MS ms)"
  echo "dernière sonde : $DERNIER_CODE"
  echo "verdict V2 : $VERDICT"
  echo
  echo "fichiers bruts : $FICHIER_AB, $FICHIER_SONDES"
} | tee "$FICHIER_MESURE"
