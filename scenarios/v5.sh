#!/usr/bin/env bash
# Scénario V5 : reconstruction complète de la plateforme (preuve de R1).
# À lancer depuis l'hôte, dans Git Bash : bash scenarios/v5.sh
# Résultat brut enregistré dans mesures/v5-AAAA-MM-JJ-HHMM.txt

set -u
cd "$(dirname "$0")/.." || exit 1     # racine du dépôt
export VAGRANT_NO_COLOR=1             # sortie sans codes de couleur

mkdir -p mesures
FICHIER="mesures/v5-$(date +%Y-%m-%d-%H%M).txt"

# --- 1. Contexte du test (noté avant de détruire quoi que ce soit) ---
if [ -f .vagrant/nb_app ]; then
  NB_APP=$(tr -d '[:space:]' < .vagrant/nb_app)
else
  NB_APP="inconnu (.vagrant/nb_app absent)"
fi
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "inconnu")
EXTENSIONS_ACTIVES=$(cat .vagrant/extensions 2>/dev/null)
if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
  MODIFS="oui (fichiers suivis modifiés localement)"
else
  MODIFS="non"
fi

{
  echo "=== Scénario V5 : reconstruction complète ==="
  echo "Date                      : $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Commit                    : $COMMIT"
  echo "Modifications locales     : $MODIFS"
  echo "NB_APP                    : $NB_APP"
echo "Extensions                : ${EXTENSIONS_ACTIVES:-aucune}"
  echo "Version de Vagrant        : $(vagrant --version)"
  echo
  echo "=== Sortie complète de Vagrant ==="
} > "$FICHIER"

# --- 2. Destruction puis reconstruction, durée totale mesurée ---
DEBUT=$(date +%s)

echo '$ vagrant destroy -f' | tee -a "$FICHIER"
vagrant destroy -f 2>&1 | tee -a "$FICHIER"
CODE_DESTROY=${PIPESTATUS[0]}

echo '$ vagrant up' | tee -a "$FICHIER"
vagrant up 2>&1 | tee -a "$FICHIER"
CODE_UP=${PIPESTATUS[0]}

FIN=$(date +%s)
DUREE=$((FIN - DEBUT))

# --- 3. La plateforme répond-elle ? (503 attendu tant que app/bdd sont vides) ---
CODE_HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://localhost:8080/sante)
: "${CODE_HTTP:=000}"

# --- 4. Résultat en fin de fichier ---
{
  echo
  echo "=== Résultat ==="
  echo "Code de sortie vagrant destroy : $CODE_DESTROY"
  echo "Code de sortie vagrant up      : $CODE_UP"
  echo "Durée totale (destroy + up)    : ${DUREE} s"
  echo "Code HTTP de /sante            : ${CODE_HTTP}"
} | tee -a "$FICHIER"

echo "Fichier enregistré : $FICHIER"
[ "$CODE_UP" -eq 0 ] || exit 1