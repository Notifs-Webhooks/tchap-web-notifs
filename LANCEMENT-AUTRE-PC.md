# Lancer Tchap sur un autre PC Linux

## Prérequis

- Docker avec le plugin `docker compose`
- Python 3
- `curl`
- connexion Internet au premier lancement pour télécharger l'image Synapse

## Démarrage

Depuis le dossier extrait :

```bash
chmod +x run-tchap.sh scripts/*.sh
TCHAP_PUBLIC_HOST="$(hostname -I | awk '{print $1}')" ./run-tchap.sh
```

Le script initialise automatiquement Matrix et les comptes Alice/Bob lors du
premier lancement. Tchap reste attaché au terminal ; arrêter le serveur web avec
`Ctrl+C`. Matrix continue dans Docker.

Pour un usage uniquement sur le PC local :

```bash
TCHAP_PUBLIC_HOST=127.0.0.1 ./run-tchap.sh
```

## Accès et comptes

- Tchap : `http://ADRESSE_IP_DU_PC:8082`
- Matrix : `http://ADRESSE_IP_DU_PC:8008`
- Identifiants : voir `local-users.txt`

## Arrêt de Matrix

```bash
./run-tchap.sh matrix-stop
```

Les données Matrix sont conservées dans `.tchap-matrix/`.
