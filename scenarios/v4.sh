#!/usr/bin/env bash
# Scénario V4 : panne de la base primaire (R6)
# Éteint bdd1, vérifie que /sante répond un 503 propre (jamais une page blanche ni une erreur de
# connexion), lance scripts/bascule.sh puis mesure le temps jusqu'au retour du 200.
# Attendu : 503 non vide pendant toute la panne, promotion de bdd2, retour du 200 après la bascule.
# Usage : bash scenarios/v4.sh   (ADRESSE=http://192.168.58.10 bash scenarios/v4.sh pour passer par E1)
# Résultat brut enregistré dans mesures/v4-AAAA-MM-JJ-HHMMSS.txt (à ne pas commiter).
# Attention : ce scénario éteint bdd1 ; la remise en état est rappelée à la fin.

set -u
cd "$(dirname "$0")/.." || exit 1     # racine du dépôt
export VAGRANT_NO_COLOR=1

ADRESSE="${ADRESSE:-http://localhost:8080}"
OBSERVATION="${OBSERVATION:-10}"      # secondes d'observation du 503 avant la bascule
ATTENTE_MAX="${ATTENTE_MAX:-60}"      # secondes d'attente du retour du 200 après la bascule

mkdir -p mesures
FICHIER="mesures/v4-$(date +%Y-%m-%d-%H%M%S).txt"
JOURNAL_SONDE=$(mktemp)
CORPS_SONDE=$(mktemp)
PID_SONDE=""

nettoyer() {
  if [ -n "$PID_SONDE" ]; then kill "$PID_SONDE" 2>/dev/null; fi
  rm -f "$JOURNAL_SONDE" "$CORPS_SONDE"
}
trap nettoyer EXIT

journal() { echo "$@" | tee -a "$FICHIER"; }

# Heure en millisecondes (repli sur les secondes si date ne sait pas faire)
maintenant_ms() {
  local t
  t=$(date +%s%3N 2>/dev/null)
  case "$t" in
    ""|*[!0-9]*) t=$(( $(date +%s) * 1000 )) ;;
  esac
  echo "$t"
}

# Interroge /sante toutes les demi-secondes ; une ligne par sonde : heure_ms code taille_réponse
sonde() {
  local code taille
  while :; do
    : > "$CORPS_SONDE"
    code=$(curl -s -m 2 -o "$CORPS_SONDE" -w '%{http_code}' "$ADRESSE/sante" 2>/dev/null)
    taille=$(wc -c < "$CORPS_SONDE" | tr -d ' ')
    echo "$(maintenant_ms) ${code:-000} ${taille:-0}" >> "$JOURNAL_SONDE"
    sleep 0.5
  done
}

secondes() { awk -v d="$1" 'BEGIN { printf "%.1f", d / 1000 }'; }

# --- 1. Contexte du test ---
if [ -f .vagrant/nb_app ]; then
  NB_APP=$(tr -d '[:space:]' < .vagrant/nb_app)
else
  NB_APP="inconnu (.vagrant/nb_app absent)"
fi
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "inconnu")
EXTENSIONS_ACTIVES=$(cat .vagrant/extensions 2>/dev/null)
[ -n "$EXTENSIONS_ACTIVES" ] || EXTENSIONS_ACTIVES="aucune"
if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
  MODIFS="oui (fichiers suivis modifiés localement)"
else
  MODIFS="non"
fi

journal "=== Scénario V4 : panne de la base primaire ==="
journal "Date                      : $(date '+%Y-%m-%d %H:%M:%S')"
journal "Commit                    : $COMMIT"
journal "NB_APP                    : $NB_APP"
journal "Extensions actives        : $EXTENSIONS_ACTIVES"
journal "Modifications locales     : $MODIFS"
journal "Adresse testée            : $ADRESSE"
journal

# --- 2. État de départ : /sante doit renvoyer 200 ---
CODE_DEPART=$(curl -s -m 2 -o /dev/null -w '%{http_code}' "$ADRESSE/sante" 2>/dev/null)
journal "État de départ : /sante renvoie ${CODE_DEPART:-000} (attendu : 200)"
if [ "${CODE_DEPART:-000}" != "200" ]; then
  journal "verdict V4 : NON exécuté (la plateforme n'est pas dans son état normal au départ)"
  exit 1
fi

# --- 3. Panne : on éteint bdd1 en continuant d'interroger /sante ---
sonde &
PID_SONDE=$!

T_HALT_DEBUT=$(maintenant_ms)
journal "Arrêt de bdd1 (vagrant halt bdd1)..."
vagrant halt bdd1 > /dev/null 2>&1
T0=$(maintenant_ms)
journal "bdd1 est arrêtée (durée de l'arrêt : $(secondes $(( T0 - T_HALT_DEBUT ))) s) : début de la mesure (t = 0)"

journal "Observation du 503 pendant ${OBSERVATION} s..."
sleep "$OBSERVATION"

# --- 4. Bascule ---
journal "Bascule (scripts/bascule.sh)..."
T_BASC_DEBUT=$(maintenant_ms)
SORTIE_BASCULE=$(bash scripts/bascule.sh 2>&1)
CODE_BASCULE=$?
T_BASC_FIN=$(maintenant_ms)
DUREE_BASCULE=$(secondes $(( T_BASC_FIN - T_BASC_DEBUT )))
journal "Bascule terminée (code ${CODE_BASCULE}, ${DUREE_BASCULE} s mesurées depuis l'hôte)"

# --- 5. Attente du retour du 200 ---
journal "Attente du retour du 200 (${ATTENTE_MAX} s au plus)..."
T200=""
MAX_ITER=$(( ATTENTE_MAX * 2 ))
i=0
while [ "$i" -lt "$MAX_ITER" ]; do
  T200=$(awk -v d="$T_BASC_DEBUT" '$2 == 200 && $3 > 0 && $1 >= d { print $1; exit }' "$JOURNAL_SONDE")
  if [ -n "$T200" ]; then break; fi
  sleep 0.5
  i=$(( i + 1 ))
done
sleep 2                                # quelques sondes de plus pour voir le 200 se maintenir
kill "$PID_SONDE" 2>/dev/null
wait "$PID_SONDE" 2>/dev/null
PID_SONDE=""

# --- 6. Analyse : toutes les sondes entre l'arrêt de bdd1 et le retour du 200 doivent être des 503 non vides ---
if [ -n "$T200" ]; then FIN_FENETRE="$T200"; else FIN_FENETRE=9999999999999; fi
ANALYSE=$(awk -v t0="$T0" -v fin="$FIN_FENETRE" '
  $1 >= t0 && $1 < fin {
    n++
    if ($2 == 503 && $3 > 0) ok++
    else { mauvais++; clef = $2; if ($3 == 0) clef = clef " (vide)"; d[clef]++ }
  }
  END {
    detail = ""
    for (k in d) detail = detail (detail == "" ? "" : ", ") k " x" d[k]
    printf "%d %d %d %s", n, ok, mauvais, detail
  }' "$JOURNAL_SONDE")
read -r N_SONDES N_503 N_ANOMALIES DETAIL_ANOMALIES <<< "$ANALYSE"

journal
journal "--- Chronologie des réponses de /sante (t = 0 : bdd1 arrêtée) ---"
awk -v t0="$T0" '
  {
    rel = ($1 - t0) / 1000
    etat = $2
    if ($2 == "000") etat = "000 (erreur de connexion)"
    else if ($3 == 0) etat = $2 " (réponse vide)"
    if (etat != cour) {
      if (cour != "") printf "  de %+.1f s à %+.1f s : %s (%d sondes)\n", debut, dernier, cour, n
      cour = etat; debut = rel; n = 0
    }
    dernier = rel; n++
  }
  END { if (cour != "") printf "  de %+.1f s à %+.1f s : %s (%d sondes)\n", debut, dernier, cour, n }
' "$JOURNAL_SONDE" | tee -a "$FICHIER"

journal
journal "--- Sortie de scripts/bascule.sh ---"
echo "$SORTIE_BASCULE" | sed 's/^/  /' | tee -a "$FICHIER"

# --- 7. Résultats et verdict ---
if [ "${N_SONDES:-0}" -gt 0 ] && [ "${N_ANOMALIES:-0}" -eq 0 ]; then
  PARTIE_503="conforme"
else
  PARTIE_503="NON conforme"
fi
if [ "$CODE_BASCULE" -eq 0 ]; then PROMOTION="conforme"; else PROMOTION="NON conforme"; fi

if [ -n "$T200" ]; then
  TEMPS_TOTAL="$(secondes $(( T200 - T0 ))) s"
else
  TEMPS_TOTAL="non observé en ${ATTENTE_MAX} s après la bascule"
fi

if [ "$PARTIE_503" = "conforme" ] && [ "$PROMOTION" = "conforme" ] && [ -n "$T200" ]; then
  VERDICT="conforme"
elif [ "$PARTIE_503" = "conforme" ] && [ "$PROMOTION" = "conforme" ]; then
  VERDICT="partiel (503 et promotion conformes, retour du 200 non observé)"
else
  VERDICT="NON conforme"
fi

journal
journal "--- Résultats ---"
journal "sondes entre l'arrêt de bdd1 et le retour du 200 : ${N_SONDES:-0}"
journal "dont 503 avec une réponse non vide            : ${N_503:-0}"
journal "anomalies (page blanche, erreur de connexion, autre code) : ${N_ANOMALIES:-0} ${DETAIL_ANOMALIES:-}"
journal "partie 503                                    : $PARTIE_503"
journal "promotion de bdd2 (bascule.sh)                : $PROMOTION"
journal "durée de la bascule (depuis l'hôte)           : ${DUREE_BASCULE} s"
journal "temps total entre l'arrêt de bdd1 et le 200   : $TEMPS_TOTAL"
journal "verdict V4 : $VERDICT"
journal
journal "Remise en état : supprimer config/primaire, recréer bdd1 et bdd2 (vagrant destroy -f bdd1 bdd2,"
journal "puis vagrant up bdd1 bdd2) et laisser les serveurs applicatifs relire leur configuration."
journal "Mesure enregistrée dans $FICHIER (à ne pas commiter)."

[ "$VERDICT" = "conforme" ]
