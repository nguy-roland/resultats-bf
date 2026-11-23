"""Service HTTP RÉSULTATS-BF : aucun état local, la base est la seule source de vérité.

Application WSGI, lancée par gunicorn (server:application).
Configuration par variables d'environnement : DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD.
"""
import json
import os
import socket
import sys
from urllib.parse import parse_qs

import psycopg2

STATUTS = {200: "200 OK", 400: "400 Bad Request", 404: "404 Not Found",
           503: "503 Service Unavailable"}
COLONNES = ("matricule", "nom", "serie", "moyenne", "admis")


def connexion():
    # Une connexion par requête : rien n'est conservé entre deux appels. Une base absente
    # au démarrage (ou revenue plus tard) n'exige donc ni redémarrage ni logique de reprise.
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", ""),
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ.get("DB_NAME", ""),
        user=os.environ.get("DB_USER", ""),
        password=os.environ.get("DB_PASSWORD", ""),
        connect_timeout=2,  # /sante doit répondre vite pour que le répartiteur écarte le serveur
        options="-c statement_timeout=3000",
    )


def interroger(sql, params=()):
    conn = connexion()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()
    finally:
        conn.close()


def repondre(start, code, corps, type_mime="application/json"):
    if not isinstance(corps, str):
        corps = json.dumps(corps, ensure_ascii=False, default=float)  # Decimal -> float
    donnees = (corps + "\n").encode("utf-8")
    start(STATUTS[code], [("Content-Type", type_mime + "; charset=utf-8"),
                          ("Content-Length", str(len(donnees)))])
    return [donnees]


def application(environ, start):
    chemin = environ.get("PATH_INFO", "/")
    try:
        if chemin == "/info":
            return repondre(start, 200, socket.gethostname(), "text/plain")
        if chemin == "/sante":
            # Vraie requête sur la vraie table : 200 seulement si la base est prête.
            interroger("SELECT 1 FROM resultats LIMIT 1")
            return repondre(start, 200, {"statut": "ok"})
        if chemin == "/resultat":
            valeurs = parse_qs(environ.get("QUERY_STRING", "")).get("matricule", [""])
            matricule = valeurs[0].strip()
            if not matricule:
                return repondre(start, 400, {"erreur": "paramètre matricule manquant"})
            ligne = interroger("SELECT matricule, nom, serie, moyenne, admis "
                               "FROM resultats WHERE matricule = %s", (matricule,))
            if ligne is None:
                return repondre(start, 404, {"erreur": "matricule introuvable"})
            return repondre(start, 200, dict(zip(COLONNES, ligne)))
        return repondre(start, 404, {"erreur": "route inconnue"})
    except psycopg2.DataError:  # matricule mal formé pour le type de la colonne
        return repondre(start, 404, {"erreur": "matricule introuvable"})
    except psycopg2.Error as erreur:  # base absente, injoignable, ou table pas encore créée
        # La cause réelle va dans le journal (journalctl -u resultats-bf), jamais dans la réponse.
        print(f"{chemin} : {type(erreur).__name__} : {str(erreur).strip()}", file=sys.stderr, flush=True)
        return repondre(start, 503, {"erreur": "base indisponible"})