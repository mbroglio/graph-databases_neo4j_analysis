#!/bin/bash

# ==============================================================================
# Script di Automazione - Scenario 3 (Sistemi Distribuiti e Teorema CAP)
# ==============================================================================
# 1. Pulizia ambiente e avvio del cluster Neo4j Enterprise (5 nodi)
# 2. Attesa formazione quorum Raft
# 3. Caricamento dataset LDBC (Person e KNOWS)
# 4. Esecuzione benchmark Python (Test 3.1, 3.2, 3.3)
# 5. Generazione grafici
# ==============================================================================

set -e # Interrompe lo script in caso di errore

# Imposta directory
cd "$(dirname "$0")/../../"

# Colori per l'output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}  AVVIO AUTOMATIZZATO SCENARIO 3 - NEO4J CLUSTER RAFT${NC}"
echo -e "${GREEN}======================================================================${NC}\n"

# Rileva scale factor
detect_scale_factor() {
    # Analizza volumi neo4j
    local vol
    vol=$(docker inspect neo4j-benchmark \
        --format '{{ range .Mounts }}{{ if eq .Destination "/data" }}{{ .Source }}{{ end }}{{ end }}' 2>/dev/null || true)
    if echo "$vol" | grep -qE "sf1($|[^0-9])"; then
        echo "1"
        return
    elif echo "$vol" | grep -q "sf0\.1"; then
        echo "0.1"
        return
    fi

    # Analizza volumi postgres
    local pg_vol
    pg_vol=$(docker inspect postgres-benchmark \
        --format '{{ range .Mounts }}{{ if eq .Destination "/var/lib/postgresql/data" }}{{ .Source }}{{ end }}{{ end }}' 2>/dev/null || true)
    if echo "$pg_vol" | grep -qE "sf1($|[^0-9])"; then
        echo "1"
        return
    elif echo "$pg_vol" | grep -q "sf0\.1"; then
        echo "0.1"
        return
    fi

    # Stima scale factor
    local n
    n=$(docker exec neo4j-benchmark cypher-shell -u neo4j -p password \
        "MATCH (p:Person) RETURN count(p) AS n;" 2>/dev/null | tail -1 | tr -d ' ' || true)
    if [ "${n:-0}" -gt 100000 ]; then
        echo "1"
    else
        echo "0.1"
    fi
}

SF_ACTIVE=$(detect_scale_factor)
echo -e "${YELLOW}[INFO] Scale Factor rilevato: SF=${SF_ACTIVE}${NC}"

# Definisce cleanup
function cleanup {
    echo -e "\n${YELLOW}[CLEANUP] Spegnimento cluster Raft e pulizia volumi...${NC}"
    docker compose -f infrastructure/docker-compose-cluster.yml down -v 2>/dev/null || true

    echo -e "${YELLOW}[CLEANUP] Riavvio istanze singole (SF=${SF_ACTIVE})...${NC}"
    SCALE_FACTOR="${SF_ACTIVE}" docker compose -f infrastructure/docker-compose.yml up -d 2>/dev/null || true

    echo -e "${YELLOW}[CLEANUP] Attendo che Neo4j single-instance sia pronto...${NC}"
    local retries=0
    until docker exec neo4j-benchmark cypher-shell -u neo4j -p password "RETURN 1" >/dev/null 2>&1; do
        if [ "$retries" -ge 60 ]; then
            echo -e "${RED}[WARN] Neo4j single-instance non risponde dopo 120s. Verifica manualmente.${NC}"
            return
        fi
        printf "."
        sleep 2
        retries=$((retries + 1))
    done
    echo -e "\n${GREEN}[CLEANUP OK] Neo4j single-instance pronto (SF=${SF_ACTIVE}).${NC}"

    echo -e "${YELLOW}[CLEANUP] Attendo che PostgreSQL single-instance sia pronto...${NC}"
    local pg_retries=0
    until docker exec postgres-benchmark pg_isready -U postgres >/dev/null 2>&1; do
        if [ "$pg_retries" -ge 30 ]; then
            echo -e "${RED}[WARN] PostgreSQL single-instance non risponde dopo 60s. Verifica manualmente.${NC}"
            return
        fi
        printf "."
        sleep 2
        pg_retries=$((pg_retries + 1))
    done
    echo -e "\n${GREEN}[CLEANUP OK] Tutti i DB single-instance pronti (SF=${SF_ACTIVE}).${NC}"
}
trap cleanup EXIT

echo -e "${YELLOW}[0/6] Sospensione istanze singole...${NC}"
docker compose -f infrastructure/docker-compose.yml stop 2>/dev/null || true

# Avvia cluster
echo -e "${YELLOW}[1/6] Pulizia volumi precedenti e avvio cluster...${NC}"
docker compose -f infrastructure/docker-compose-cluster.yml down -v
NEO4J_ACCEPT_LICENSE_AGREEMENT=yes docker compose -f infrastructure/docker-compose-cluster.yml up -d

# Attende quorum
echo -e "\n${YELLOW}[2/6] Attesa formazione del quorum Raft...${NC}"
MAX_RETRIES=30
RETRY_COUNT=0
until docker exec neo4j-core1 cypher-shell -u neo4j -p password "RETURN 1" >/dev/null 2>&1; do
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo -e "${RED}[ERR] Timeout raggiunto. Il cluster non ha formato il quorum.${NC}"
        exit 1
    fi
    echo -n "."
    sleep 5
    RETRY_COUNT=$((RETRY_COUNT+1))
done
echo -e "\n${GREEN}[OK] Cluster pronto e quorum raggiunto!${NC}"

# Attende sincronizzazione
sleep 10

# Alloca topologia
echo -e "\n${YELLOW}[3/6] Allocazione topologia database neo4j (3 PRIMARY, 2 SECONDARY)...${NC}"
# Estrae ID server
docker exec neo4j-core1 cypher-shell -d system -u neo4j -p password "SHOW SERVERS YIELD name RETURN name" > temp_servers.txt

# Abilita server
tail -n +2 temp_servers.txt | tr -d '"' | while read srv_id; do
    if [ ! -z "$srv_id" ]; then
        docker exec neo4j-core1 cypher-shell -d system -u neo4j -p password "ENABLE SERVER '$srv_id';"
    fi
done
rm -f temp_servers.txt

echo -e "  Attesa allocazione topologia..."
RETRY_COUNT=0
until docker exec neo4j-core1 cypher-shell -d system -u neo4j -p password "ALTER DATABASE neo4j SET TOPOLOGY 3 PRIMARIES 2 SECONDARIES WAIT;" 2>/dev/null; do
    if [ $RETRY_COUNT -ge 30 ]; then
        echo -e "\n${RED}[ERR] Timeout allocazione topologia.${NC}"
        exit 1
    fi
    echo -n "."
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT+1))
done
echo -e "\n${GREEN}[OK] Topologia allocata correttamente!${NC}"

echo -e "\n${YELLOW}Attesa elezione Leader per database neo4j...${NC}"
RETRY_COUNT=0
until docker exec neo4j-core1 cypher-shell -d system -u neo4j -p password "SHOW DATABASES YIELD name, writer WHERE name='neo4j' AND writer=TRUE RETURN 1" | grep -q "1"; do
    if [ $RETRY_COUNT -ge 30 ]; then
        echo -e "${RED}[ERR] Nessun Leader eletto dopo l'allocazione della topologia.${NC}"
        exit 1
    fi
    echo -n "."
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT+1))
done
echo -e "\n${GREEN}[OK] Leader eletto e pronto per le scritture!${NC}"

# Copia CSV
echo -e "\n${YELLOW}[4/6] Preparazione directory e copia dataset CSV nei nodi Core...${NC}"
for core in neo4j-core1 neo4j-core2 neo4j-core3; do
    docker exec $core bash -c "mkdir -p /var/lib/neo4j/import/dynamic /var/lib/neo4j/import/static"
    docker cp infrastructure/data/postgres-csv-formatted/dynamic/. $core:/var/lib/neo4j/import/dynamic/
    docker cp infrastructure/data/postgres-csv-formatted/static/. $core:/var/lib/neo4j/import/static/
done
echo -e "${GREEN}[OK] File copiati con successo.${NC}"

# Carica dati
echo -e "\n${YELLOW}[4/6] Caricamento nodi Person e relazioni KNOWS (LOAD CSV)...${NC}"
docker exec neo4j-core1 cypher-shell -u neo4j -p password '
CREATE CONSTRAINT person_id IF NOT EXISTS FOR (p:Person) REQUIRE p.id IS UNIQUE;
LOAD CSV WITH HEADERS FROM "file:///dynamic/person_0_0.csv" AS row FIELDTERMINATOR "|"
CALL {
  WITH row
  MERGE (p:Person {id: toInteger(row.`:ID`)})
  SET p.firstName=row.firstName, p.lastName=row.lastName,
      p.gender=row.gender, p.birthday=row.birthday,
      p.creationDate=row.creationDate, p.locationIP=row.locationIP
} IN TRANSACTIONS OF 1000 ROWS;
'

docker exec neo4j-core1 cypher-shell -u neo4j -p password '
LOAD CSV WITH HEADERS FROM "file:///dynamic/person_knows_person_0_0.csv" AS row FIELDTERMINATOR "|"
CALL {
  WITH row
  MATCH (a:Person {id: toInteger(row.`:START_ID`)}), (b:Person {id: toInteger(row.`:END_ID`)})
  MERGE (a)-[:KNOWS {creationDate: row.creationDate}]->(b)
} IN TRANSACTIONS OF 5000 ROWS;
'

# Verifica caricamento
echo -e "\n${YELLOW}Verifica dati caricati:${NC}"
docker exec neo4j-core1 cypher-shell -u neo4j -p password '
MATCH (p:Person) RETURN count(p) AS n_persons;
'
docker exec neo4j-core1 cypher-shell -u neo4j -p password '
MATCH ()-[r:KNOWS]->() RETURN count(r) AS n_knows;
'

# Esegue benchmark
echo -e "\n${YELLOW}[5/6] Esecuzione benchmark Scenario 3...${NC}"
echo -e "      (Log esportato in benchmarks/scenario3/benchmark_output.txt)\n"
docker run --rm \
  --network neo4j-cluster-net \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/app -w /app \
  -e IN_DOCKER=1 \
  -e NEO4J_CLUSTER_URI=neo4j://neo4j-core1:7687 \
  python:3.11 \
  bash -c "pip install --quiet neo4j docker && python benchmarks/scenario3/scenario3_benchmark.py 2>&1 | tee benchmarks/scenario3/benchmark_output.txt"

# Genera grafici
echo -e "\n${YELLOW}[6/6] Generazione grafici SVG...${NC}"
docker run --rm \
  -v $(pwd):/app -w /app \
  python:3.11 \
  bash -c "pip install --quiet matplotlib && python benchmarks/scenario3/plot_scenario3.py 2>&1 | tee benchmarks/scenario3/plot_output.txt"

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${GREEN}  SCENARIO 3 COMPLETATO CON SUCCESSO!${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "I risultati sono disponibili in:"
echo -e " - Dati grezzi:    ${YELLOW}benchmarks/scenario3/results.json${NC}"
echo -e " - Log console:    ${YELLOW}benchmarks/scenario3/benchmark_output.txt${NC}"
echo -e " - Grafico:        ${YELLOW}benchmarks/scenario3/fault_tolerance_timeline.svg${NC}"
