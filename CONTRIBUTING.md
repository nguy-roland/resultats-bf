# Contribuer

## Mise en place

```bash
git clone git@github.com:nguy-roland/resultats-bf.git
cd resultats-bf
git config user.name "Prénom NOM"   # ton vrai nom : l'historique est évalué
```

## Règles

- On ne pousse jamais directement sur main : une branche par tâche, puis une pull request.
- Nom de branche : `<rôle>/<tâche>`, par exemple `donnees/replication` ou `app/sonde-sante`.
- Message de commit : `type: description`, avec feat, fix, docs, test ou chore.
- Un script doit pouvoir être rejoué : `vagrant provision` deux fois de suite ne change rien et n'échoue pas (R2).
- Aucun mot de passe dans le code, seulement les variables du `.env` (R7). Toute nouvelle variable s'ajoute aussi dans `.env.exemple`.
- Les services écoutent sur 0.0.0.0, jamais sur 127.0.0.1.

## Avant d'ouvrir une pull request

```bash
vagrant destroy -f <machine> && vagrant up <machine>   # fonctionne sur une VM neuve
vagrant provision <machine>                           # rejouer ne change rien
```

Indique dans la description de la pull request les commandes lancées et leur résultat.

## Revue

Chaque pull request est relue et fusionnée par l'architecte (voir `.github/CODEOWNERS`).
