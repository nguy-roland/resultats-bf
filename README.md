# RÉSULTATS-BF

Plateforme de consultation des résultats d'examens par matricule, entièrement décrite en code avec Vagrant et VirtualBox. Groupe 3.

## Prérequis

- VirtualBox (version à préciser)
- Vagrant (version à préciser)
- 8 Go de RAM minimum

## Démarrage

```bash
git clone https://github.com/nguy-roland/resultats-bf.git
cd resultats-bf
vagrant up
```

Le service répond ensuite sur http://localhost:8080.

## Architecture

Réseau privé : 192.168.58.0/24.

| Machine     | Rôle                           | Adresse         |
|-------------|--------------------------------|-----------------|
| bdd1        | Base primaire PostgreSQL       | 192.168.58.31   |
| bdd2        | Réplique en flux               | 192.168.58.32   |
| app1 … appN | Serveurs applicatifs sans état | 192.168.58.21 … |
| lb1         | Répartiteur de charge          | 192.168.58.11   |

Le nombre de serveurs applicatifs se règle avec `NB_APP` (2 par défaut) : `NB_APP=4 vagrant up`.

## Arborescence

| Dossier    | Contenu                                        |
|------------|------------------------------------------------|
| app/       | Service HTTP                                   |
| config/    | Modèles de configuration                       |
| scripts/   | Provisionnement, un script par rôle de machine |
| scenarios/ | Scénarios de validation V1 à V6                |
| mesures/   | Résultats bruts des scénarios                  |
| docs/      | Dossier d'architecture et journal de bord      |

## Équipe

| Membre                      | Rôle                              |
|-----------------------------|-----------------------------------|
| ZONGO Naboswende Guy-Roland | Architecte réseau et répartition  |
| …                           | Ingénieur applicatif              |
| …                           | Ingénieur données                 |
| …                           | Ingénieur essais et observabilité |
