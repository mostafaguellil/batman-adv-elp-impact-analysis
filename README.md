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

## Prerequis

- Un hote Linux avec Docker et Docker Compose
- Module noyau `batman-adv` disponible
- Acces `sudo` pour charger le module

### Important

- **macOS (Darwin)**: non supporte en natif pour `batman-adv`
- **Windows**: possible via WSL2/VM Linux si le module `batman-adv` est disponible

## Lancement rapide

```bash
git clone https://github.com/mostafaguellil/batman-adv-elp-impact-analysis.git
cd batman-adv-elp-impact-analysis
./scripts/setup_batman.sh
```

Modes disponibles:

- `./scripts/setup_batman.sh auto` (defaut): Linux -> BATMAN-Adv, macOS -> fallback Docker
- `./scripts/setup_batman.sh batman`: force le mode BATMAN-Adv (Linux uniquement)
- `./scripts/setup_batman.sh fallback`: test rapide Docker (connectivite/iperf/tcpdump) sans module batman-adv

## Verification manuelle

### 1) Etat des conteneurs

```bash
docker compose ps
```

### 1-bis) Grafana / Prometheus

```bash
docker compose up -d grafana prometheus cadvisor
```

- Grafana: `http://localhost:3000` (login par defaut: `admin` / `admin`)
- Prometheus: `http://localhost:9090`
- cAdvisor: `http://localhost:8080`

Le dashboard `MANET Overview` et la datasource Prometheus sont provisionnes automatiquement.

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

- `Current host: Darwin`: execute sur macOS, passer sur Linux/VM Linux
- `modprobe: command not found`: `kmod` manquant sur l hote Linux
- `Module batman-adv not found`: noyau Linux sans support `batman-adv`
- `docker compose is not available`: installer le plugin Docker Compose sur la VM Linux
- `sudo requires a password`: executer `sudo -v` puis relancer le script
- `Cannot connect to Docker daemon`: demarrer Docker Desktop/Engine puis relancer
