#!/usr/bin/env bash
# Scénario V6 : panne du répartiteur lb1 (extension E1)
# Interroge /info sur l'adresse virtuelle pendant vagrant halt lb1, puis mesure l'interruption.
# Attendu : le service reste joignable à la même adresse, avec une interruption de moins de 5 s.
# Usage : scenarios/v6.sh   (E1 doit être active : EXTENSIONS=e1)
# Résultat brut enregistré dans mesures/v6-AAAA-MM-JJ-HHMMSS.txt
set -u
cd "$(dirname "$0")/.." || exit 1
export VAGRANT_NO_COLOR=1

LIMITE_MS=5000          # interruption maximale tolérée (E1)
OBSERVATION=10          # secondes d'observation après l'arrêt de lb1
FICHIER="mesures/v6-$(date +%Y-%m-%d-%H%M%S).txt"
JOURNAL_SONDE=$(mktemp)
PID_SONDE=""
mkdir -p mesures

nettoyer() {
  if [ -n "$PID_SONDE" ]; then kill "$PID_SONDE" 2>/dev/null; fi
  rm -f "$JOURNAL_SONDE"
}
trap nettoyer EXIT

journal() { echo "$@" | tee -a "$FICHIER"; }
maintenant_ms() { date +%s%3N; }

# Adresse virtuelle lue dans la table des nœuds : rien n'est écrit en dur.
ADRESSE_VIRTUELLE=$(awk '/^ *vip:/ { print $2; exit }' config/noeuds.yml 2>/dev/null)
if [ -z "$ADRESSE_VIRTUELLE" ]; then
  echo "E1 n'est pas active : lancez d'abord EXTENSIONS=e1 vagrant up" >&2
  exit 1
fi
ADRESSE="http://${ADRESSE_VIRTUELLE}"

# Une sonde toutes les 0,2 s ; une ligne par sonde : heure_ms code
sonde() {
  while :; do
    code=$(curl -s -m 1 -o /dev/null -w '%{http_code}' "$ADRESSE/info" 2>/dev/null)
    echo "$(maintenant_ms) ${code:-000}" >> "$JOURNAL_SONDE"
    sleep 0.2
  done
}

journal "=== Scénario V6 : panne du répartiteur lb1 (E1) ==="
journal "date : $(date '+%Y-%m-%d %H:%M:%S')"
journal "commit : $(git rev-parse --short HEAD 2>/dev/null || echo inconnu)"
journal "NB_APP : $(cat .vagrant/nb_app 2>/dev/null || echo 2)"
journal "extensions : $(cat .vagrant/extensions 2>/dev/null)"
journal "adresse testée : $ADRESSE"
journal

CODE_DEPART=$(curl -s -m 2 -o /dev/null -w '%{http_code}' "$ADRESSE/info")
journal "état de départ : /info renvoie $CODE_DEPART (attendu : 200)"
if [ "$CODE_DEPART" != "200" ]; then
  journal "verdict V6 : NON exécuté (la plateforme n'est pas dans son état normal)"
  exit 1
fi

sonde &
PID_SONDE=$!
sleep 2
T_DEBUT=$(maintenant_ms)
journal "arrêt de lb1 (vagrant halt lb1)..."
vagrant halt lb1 > /dev/null 2>&1
journal "lb1 arrêté en $(( ($(maintenant_ms) - T_DEBUT) / 1000 )) s ; observation pendant ${OBSERVATION} s..."
sleep "$OBSERVATION"
kill "$PID_SONDE" 2>/dev/null
wait "$PID_SONDE" 2>/dev/null
PID_SONDE=""

# Interruption : temps entre la dernière réponse réussie avant la panne et la première après.
read -r NB_SONDES NB_ECHECS INTERRUPTION_MS RETABLI <<< "$(awk -v t0="$T_DEBUT" '
  {
    if ($2 == 200) {
      if (echecs_en_cours && dernier_succes != "") {
        duree = $1 - dernier_succes
        if (duree > maximum) maximum = duree
      }
      echecs_en_cours = 0
      dernier_succes = $1
      dernier_code = 200
    } else {
      if ($1 >= t0) echecs++
      echecs_en_cours = 1
      dernier_code = $2
    }
    if ($1 >= t0) n++
  }
  END { printf "%d %d %d %s", n, echecs, maximum, (dernier_code == 200 ? "oui" : "non") }
' "$JOURNAL_SONDE")"

PORTEUR=$(vagrant ssh lb2 -c "ip -4 addr show | grep -q '$ADRESSE_VIRTUELLE' && echo lb2" 2>/dev/null | tr -d '[:space:]')

if [ "$RETABLI" = "oui" ] && [ "$INTERRUPTION_MS" -lt "$LIMITE_MS" ]; then
  VERDICT="conforme"
else
  VERDICT="NON conforme"
fi

journal
journal "sondes depuis l'arrêt de lb1 : $NB_SONDES, dont $NB_ECHECS en échec"
journal "interruption maximale : $(awk -v d="$INTERRUPTION_MS" 'BEGIN { printf "%.1f", d / 1000 }') s (limite : 5 s)"
journal "service rétabli à la même adresse : $RETABLI"
journal "adresse virtuelle portée par : ${PORTEUR:-lb2 ne la porte pas}"
journal "verdict V6 : $VERDICT"
journal
journal "Remise en état : vagrant up lb1 (lb1 reprend l'adresse virtuelle)."
