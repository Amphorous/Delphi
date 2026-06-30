# Delphi - Deployment Hub

This repo contains the Eureka service registry and the Docker Compose orchestration for the entire RemuriaForHSR platform.

## Prerequisites

- Docker and Docker Compose installed on the host machine
- Access to GHCR (GitHub Container Registry) — the images are private

## Database Topology

Databases run as containers on **orexis** (the always-on host), not on a separate database server:

| Database | Orexis (primary) | Philia (secondary) |
|----------|-------------------|---------------------|
| MongoDB | `mongo-orexis`, priority 2, plus `mongo-arbiter` (vote-only) | `mongo-philia`, priority 1 — joins dynamically via `rs.add()` when reachable |
| Neo4j | `neo4j-orexis` | `neo4j-philia` — **cold-standby only**, restored from scheduled dumps (`neo4j/dump.sh`); Neo4j Community has no clustering, so this is not automatic failover |
| Redis/Valkey | `redis-orexis` | `redis-philia` — read-only replica (`replicaof`), no Sentinel/failover (it's a cache, not a system of record) |

Bring up the DB containers alongside the app stack on orexis. The replica set is initiated with **only orexis + the arbiter** - it does not wait for or require philia to be reachable, so this works the same whether philia is on or off:
```bash
docker compose -f docker-compose.yml -f docker-compose.db.yml up -d
```

Optionally, when philia is powered on, bring up its secondary/standby containers (see "First-time setup on Philia" below for the full sequence). `mongo-rs-join` connects to orexis's primary and adds philia to the replica set (idempotent - safe to run every time philia comes back online):
```bash
docker compose -f docker-compose.db.philia.yml --env-file .env.philia up -d
```

MongoDB keeps a write majority (orexis + arbiter = 2 of 3 votes) even when philia is off — this is why orexis stays primary regardless of philia's availability. If orexis's Neo4j container is ever lost, restore the latest dump on philia and repoint `SPRING_DATA_NEO4J_URI` at it manually; this is a recovery procedure, not a seamless failover.

## First-time setup

### 1. Clone

```bash
git clone https://github.com/Amphorous/Delphi.git
cd Delphi
```

### 2. Authenticate with GHCR

Create a GitHub Personal Access Token at: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic). Give it `read:packages` scope.

```bash
echo "YOUR_PAT_HERE" | docker login ghcr.io -u Amphorous --password-stdin
```

### 3. Configure environment

```bash
cp .env.example .env
nano .env
```

Fill in all `CHANGE_ME` values:

| Variable | Description |
|----------|-------------|
| `SPRING_DATA_NEO4J_AUTHENTICATION_PASSWORD` | Neo4j password on Philia |
| `SPRING_SECURITY_OAUTH2_CLIENT_REGISTRATION_DISCORD_CLIENT_ID` | Discord OAuth app client ID |
| `SPRING_SECURITY_OAUTH2_CLIENT_REGISTRATION_DISCORD_CLIENT_SECRET` | Discord OAuth app client secret |
| `APPLICATION_SECURITY_USER_KEY_SECRET` | HMAC key for pseudonymous user IDs |
| `APPLICATION_SECURITY_GATEWAY_SIGNING_SECRET` | HMAC key for inter-service signing (must match in Aquila and Celestia) |
| `APPLICATION_FRONTEND_URL_HSR` | Public URL of the frontend (e.g., `https://yourdomain.com` or `http://localhost:3000`) |

Database hosts default to the orexis-local containers (`mongo-orexis`, `neo4j-orexis`, `redis-orexis`) defined in `docker-compose.db.yml` — see "Database Topology" above.

### 4. Pull and start

```bash
docker compose -f docker-compose.yml -f docker-compose.db.yml pull
docker compose -f docker-compose.yml -f docker-compose.db.yml up -d
```

## Verifying

```bash
# Check all containers are running
docker compose ps

# Eureka dashboard (should show DELTA-ME13, AQUILA, TRANSLATOR registered)
# Open http://<host>:8761 in a browser

# Admin panel (Spring Boot Admin - per-instance log tabs, IntelliJ-style formatting)
# Open http://<host>:8090 in a browser

# Check logs for a specific service
docker compose logs eureka
docker compose logs celestia
docker compose logs aquila
docker compose logs translator
docker compose logs frontend

# Follow logs in real-time
docker compose logs -f celestia
```

## First-time setup on Philia

On philia (a separate clone of this repo from orexis's):

```bash
git clone https://github.com/Amphorous/Delphi.git
cd Delphi
cp .env.philia.example .env.philia
nano .env.philia    # fill in OREXIS_LAN_HOST, PHILIA_LAN_HOST, and the shared secrets (must match orexis's .env)
```

### DB standby (Mongo secondary, Redis replica, Neo4j cold-standby)

Bring these up every time philia is on - they keep the replica set redundant. `mongo-rs-join` is idempotent (safe to run every time):

```bash
docker compose -f docker-compose.db.philia.yml --env-file .env.philia pull
docker compose -f docker-compose.db.philia.yml --env-file .env.philia up -d
docker compose -f docker-compose.db.philia.yml --env-file .env.philia logs mongo-rs-join
```

You should see `philia added to replica set.` (or `philia is already a member, skipping.` on subsequent runs). Confirm from orexis:

```bash
docker compose exec mongo-orexis mongosh --eval "rs.status()"
```

`mongo-philia` should show up as `SECONDARY`.

Stop the DB standby containers:

```bash
docker compose -f docker-compose.db.philia.yml --env-file .env.philia down
```

### Extra load-bearing app instances (celestia, aquila, translator)

Separate, deliberate step - only run this when you actually want philia contributing extra request-handling capacity. These register with orexis's Eureka under the same service names, so Aquila's existing `lb://` routing load-balances across orexis's instances and philia's automatically — no gateway changes needed.

```bash
docker login ghcr.io -u Amphorous --password-stdin   # private images, needed here too
docker compose -f docker-compose.philia.yml --env-file .env.philia pull
docker compose -f docker-compose.philia.yml --env-file .env.philia up -d
```

These instances use a shortened Eureka lease (~15-20s eviction) so Aquila stops routing to them quickly if philia disappears ungracefully; its existing Retry + CircuitBreaker filters absorb the brief window before that.

Stop them:

```bash
docker compose -f docker-compose.philia.yml --env-file .env.philia down
```

## Updating

After new images are pushed to GHCR (via GitHub Actions on push to main):

```bash
docker compose pull
docker compose up -d
```

Only containers with new images will restart.

## Stopping

```bash
# Stop all containers (keeps data/config)
docker compose down

# Stop a single service
docker compose stop celestia
```

## Restarting a single service

```bash
docker compose restart celestia
```

## Manual asset refresh (Celestia)

Trigger a hot-reload of game metadata without restarting:

```bash
docker compose exec celestia curl -X POST localhost:8081/admin/meta/refresh
```

## Rollback to a specific version

Edit `docker-compose.yml` and change the image tag:

```yaml
# Before
image: ghcr.io/amphorous/celestia:latest

# After (rollback to version 1.0.0)
image: ghcr.io/amphorous/celestia:1.0.0
```

Then:

```bash
docker compose up -d
```

## Port mappings

| Service | Container port | Host port | URL |
|---------|---------------|-----------|-----|
| Frontend (nginx) | 80 | 3000 | `http://<host>:3000` |
| Eureka dashboard | 8761 | 8761 | `http://<host>:8761` |
| Aquila (gateway) | 8080 | not exposed | internal only |
| Celestia (backend) | 8081 | not exposed | internal only |
| Translator | 8082 | not exposed | internal only |

## Troubleshooting

**Container keeps restarting:**
```bash
docker compose logs <service-name>
```

**Eureka shows no registered services:**
Wait 30-60 seconds after startup — services register asynchronously. Check individual service logs for connection errors to Eureka or databases.

**Frontend loads but API calls fail:**
Check that Aquila is registered in Eureka and can reach the backend services. Verify `.env` has correct database hosts.

**Database connection refused:**
Verify the DB containers from `docker-compose.db.yml` are healthy: `docker compose ps mongo-orexis neo4j-orexis redis-orexis`.
