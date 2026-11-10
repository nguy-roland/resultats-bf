# Contribuer

## Mise en place

```bash
git clone git@github.com:nguy-roland/resultats-bf.git
cd resultats-bf
git config user.name "NOM Prénom"   # ton vrai nom : l'historique est évalué
```

## Règles

- On ne pousse jamais directement sur main : une branche par tâche, puis une pull request.
- Nom de branche : `<rôle>/<tâche>`, par exemple `donnees/replication` ou `app/sonde-sante`.
- Message de commit : `type: description`, avec feat, fix, docs, test ou chore.
- Un script doit pouvoir être rejoué : `vagrant provision` deux fois de suite ne change rien et n'échoue pas (R2).
- Aucun mot de passe dans le code, seulement les variables du `.env` (R7). Toute nouvelle variable s'ajoute aussi dans `.env.exemple`.
- Les services écoutent sur 0.0.0.0, jamais sur 127.0.0.1.



## Exemples de déroulement

Ingénieur applicatif :

```bash
git switch main && git pull              # partir de la dernière version
git switch -c app/service-http           # créer sa branche
# modifier, tester, puis :
git add app/ scripts/app.sh
git commit -m "feat: ajoute le service HTTP"
git push -u origin app/service-http
```

Ingénieur données :

```bash
git switch main && git pull              # partir de la dernière version
git switch -c donnees/postgresql         # créer sa branche
# modifier, tester, puis :
git add scripts/bdd.sh
git commit -m "feat: installe PostgreSQL sur bdd1"
git push -u origin donnees/postgresql
```

Ingénieur essais :

```bash
git switch main && git pull              # partir de la dernière version
git switch -c essais/scenario-v1         # créer sa branche
# modifier, tester, puis :
git add scenarios/v1.sh
git commit -m "test: ajoute le scénario V1"
git push -u origin essais/scenario-v1
```

Sur GitHub, ouvrir ensuite une pull request de la branche vers main. Après la fusion, revenir sur main avec `git switch main && git pull`.


## Avant d'ouvrir une pull request

```bash
vagrant destroy -f <machine> && vagrant up <machine>   # fonctionne sur une VM neuve
vagrant provision <machine>                           # rejouer ne change rien
```

Indique dans la description de la pull request les commandes lancées et leur résultat.

## Revue

Chaque pull request est relue et fusionnée par l'architecte (voir `.github/CODEOWNERS`).
