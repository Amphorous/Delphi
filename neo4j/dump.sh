#!/usr/bin/env bash
# Dumps orexis's Neo4j database and copies it to philia's cold-standby dump
# directory, so neo4j-philia can be restored on demand if orexis's Neo4j
# container is ever lost. Run via orexis's own crontab (e.g. nightly) -
# intentionally not a microservice, this is a one-shot maintenance task.
#
# Usage: dump.sh <philia-lan-host>
set -euo pipefail

PHILIA_HOST="${1:?Usage: dump.sh <philia-lan-host>}"
DUMP_DIR="$(dirname "$0")/dumps"
mkdir -p "$DUMP_DIR"

docker compose -f docker-compose.yml -f docker-compose.db.yml stop neo4j-orexis
docker compose -f docker-compose.yml -f docker-compose.db.yml run --rm \
  -v "$DUMP_DIR:/dumps" \
  neo4j-orexis neo4j-admin database dump neo4j --to-path=/dumps
docker compose -f docker-compose.yml -f docker-compose.db.yml start neo4j-orexis

scp "$DUMP_DIR"/neo4j.dump "${PHILIA_HOST}:$(dirname "$0")/dumps/neo4j.dump"
