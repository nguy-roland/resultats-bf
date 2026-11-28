#!/usr/bin/env bash
# Scénario V1 : répartition de la charge (R3)
# Lance 20 appels à /info et compte les réponses de chaque serveur applicatif.
# Attendu : tous les appN répondent, avec un écart à la moyenne de 20 % au plus.
# Usage : scenarios/v1.sh   (ADRESSE=http://192.168.58.10 scenarios/v1.sh pour passer par E1)
set -euo pipefail
cd "$(dirname "$0")/.."

ADRESSE="${ADRESSE:-http://localhost:8080}"
NOMBRE_APPELS=20
NB_APP=$(cat .vagrant/nb_app 2>/dev/null || echo 2)
FICHIER_MESURE="mesures/v1-$(date +%F-%H%M%S).txt"

# Attente : tous les serveurs applicatifs doivent être en service avant la mesure (15 s au plus).
# Un serveur tout juste redémarré n'est remis en service qu'après deux sondes réussies.
for tentative in $(seq 1 15); do
  SERVEURS_VUS=$(for appel in $(seq 1 $(( NB_APP * 2 ))); do curl -s -f -m 2 "$ADRESSE/info"; echo; done | grep -v "^$" | sort -u | wc -l)
  [ "$SERVEURS_VUS" -ge "$NB_APP" ] && break
  sleep 1
done

# Un appel en erreur est compté comme ERREUR plutôt que d'être perdu.
REPARTITION=$(for appel in $(seq 1 "$NOMBRE_APPELS"); do
  curl -s -f -m 2 "$ADRESSE/info" || echo -n "ERREUR"
  echo
done | grep -v "^$" | sort | uniq -c)

SERVEURS_AYANT_REPONDU=$(echo "$REPARTITION" | grep -vc "ERREUR" || true)
ECART_MAXIMAL=$(echo "$REPARTITION" | awk -v total="$NOMBRE_APPELS" -v serveurs="$NB_APP" '
  $2 != "ERREUR" {
    moyenne = total / serveurs
    ecart = ($1 - moyenne) / moyenne * 100
    if (ecart < 0) ecart = -ecart
    if (ecart > maximum) maximum = ecart
  }
  END { printf "%.0f", maximum }')

if [ "$SERVEURS_AYANT_REPONDU" -eq "$NB_APP" ] && [ "$ECART_MAXIMAL" -le 20 ]; then
  VERDICT="conforme"
else
  VERDICT="NON conforme"
fi

{
  echo "date : $(date)"
  echo "commit : $(git rev-parse --short HEAD)"
  echo "NB_APP : $NB_APP"
  echo "adresse : $ADRESSE"
  echo
  echo "$REPARTITION"
  echo
  echo "serveurs ayant répondu : $SERVEURS_AYANT_REPONDU sur $NB_APP"
  echo "écart maximal à la moyenne : $ECART_MAXIMAL %"
  echo "verdict V1 : $VERDICT"
} | tee "$FICHIER_MESURE"
