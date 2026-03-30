# BATMAN-Adv ELP Impact Analysis

Mini projet étudiant pour simuler un réseau MANET avec Docker et BATMAN-Adv.

## Objectif

Créer 3 noeuds (`node1`, `node2`, `node3`) en conteneurs, activer `bat0`, puis tester:
- la connectivité (`ping`)
- le débit (`iperf3`)
- la capture du trafic BATMAN/ELP (`tcpdump`)

## Fichiers du projet

- `docker-compose.yml`: topologie Docker (3 noeuds privileged)
- `scripts/setup_batman.sh`: automatisation (setup + tests de base)
- `monitoring/`: Prometheus, Grafana, cAdvisor, InfluxDB, Telegraf (metriques)

## Prerequis

- Un hote Linux avec Docker et Docker Compose
- Module noyau `batman-adv` disponible
- Acces `sudo` pour charger le module

### Important

- **macOS (Darwin)**: non supporte en natif pour `batman-adv`
- **Windows**: possible via WSL2/VM Linux si le module `batman-adv` est disponible

## Lancement rapide

**Tout-en-un (recommande):** demarre Docker Compose (attente des services sains si disponible), installe les outils dans les noeuds, assigne les IP de test, lance `iperf3 -s` sur `node2`.

```bash
git clone https://github.com/mostafaguellil/batman-adv-elp-impact-analysis.git
cd batman-adv-elp-impact-analysis
./scripts/start_lab.sh
```

Puis ouvrir **Grafana** sur `http://localhost:3000` (`admin` / `admin`), le dashboard **MANET Overview** est deja provisionne; **InfluxDB** sur `http://localhost:8086` (`admin` / `adminadmin`).

**Etape par etape (ancien flux):**

```bash
./scripts/setup_batman.sh
```

Modes disponibles:

- `./scripts/setup_batman.sh auto` (defaut): Linux -> BATMAN-Adv, macOS -> fallback Docker
- `./scripts/setup_batman.sh batman`: force le mode BATMAN-Adv (Linux uniquement)
- `./scripts/setup_batman.sh fallback`: test rapide Docker (connectivite/iperf/tcpdump) sans module batman-adv
- `./scripts/setup_batman.sh auto --skip-compose`: ne relance pas Compose (utilise par `start_lab.sh` apres `docker compose up`)

## Verification manuelle

### 1) Etat des conteneurs

```bash
docker compose ps
```

### 1-bis) Grafana / Prometheus / InfluxDB

```bash
docker compose up -d grafana prometheus cadvisor influxdb telegraf
```

- Grafana: `http://localhost:3000` (login par defaut: `admin` / `admin`)
- Prometheus: `http://localhost:9090`
- cAdvisor: `http://localhost:8080`
- InfluxDB UI / API: `http://localhost:8086` (compte init: `admin` / `adminadmin`, org `manet`, bucket `metrics`)

Le dashboard `MANET Overview` et les datasources Prometheus + InfluxDB (Flux) sont provisionnes automatiquement.

Telegraf envoie les metriques scrapees (`cAdvisor`, `Prometheus`) vers le bucket InfluxDB `metrics` (ideal pour analyses longues ou export). Token admin de demo (a changer en production): `manet-dev-admin-token-change-me`.

### 2) Verification bat0

```bash
docker exec node1 bash -lc "batctl if && ip -4 addr show bat0"
docker exec node2 bash -lc "batctl if && ip -4 addr show bat0"
docker exec node3 bash -lc "batctl if && ip -4 addr show bat0"
```

### 3) Ping entre noeuds

```bash
docker exec node1 bash -lc "ping -c 3 10.0.0.2"
docker exec node1 bash -lc "ping -c 3 10.0.0.3"
```

### 4) Observation BATMAN-Adv

```bash
docker exec node1 bash -lc "batctl n"
docker exec node1 bash -lc "batctl o"
```

### 5) Test iperf3

Terminal 1:
```bash
docker exec -it node2 bash -lc "iperf3 -s"
```

Terminal 2:
```bash
docker exec node1 bash -lc "iperf3 -c 10.0.0.2 -t 10"
```

### 6) Capture trafic BATMAN/ELP

```bash
docker exec -it node1 bash -lc "tcpdump -i eth0 -nn -vv ether proto 0x4305"
```

## Nettoyage

```bash
docker compose down
```

## Erreurs courantes

- **Grafana sans courbes**: choisir la datasource **Prometheus**, intervalle **Last 15 minutes** (ou plus), rafraichir; verifier `http://localhost:9090/targets` (job `cadvisor` up). Apres modification des dashboards provisionnes, redemarrer Grafana: `docker compose restart grafana`. Sur Docker Desktop, cAdvisor n a pas toujours les etiquettes `name` des conteneurs: le dashboard **MANET Overview** utilise les IDs cgroup `/docker/<hash>` (legende longue mais donnees presentes).
- `Current host: Darwin`: execute sur macOS, passer sur Linux/VM Linux
- `modprobe: command not found`: `kmod` manquant sur l hote Linux
- `Module batman-adv not found`: noyau Linux sans support `batman-adv`
- `docker compose is not available`: installer le plugin Docker Compose sur la VM Linux
- `sudo requires a password`: executer `sudo -v` puis relancer le script
- `Cannot connect to Docker daemon`: demarrer Docker Desktop/Engine puis relancer
