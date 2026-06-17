#!/bin/bash
set -e

# Define paths
LAB_DIR=$(pwd)
SCALE_FACTOR="${SCALE_FACTOR:-0.1}"

echo "Inizio caricamento dati (SF${SCALE_FACTOR})"

export RAW_DATA_DIR="$LAB_DIR/out-sf${SCALE_FACTOR}/graphs/csv/raw/composite-projected-fk"
NEO4J_TARGET_DIR="$LAB_DIR/data/neo4j-sf${SCALE_FACTOR}"
POSTGRES_TARGET_DIR="$LAB_DIR/data/postgres-sf${SCALE_FACTOR}"
LDBC_PG_SCRIPTS="$LAB_DIR/ldbc_snb_interactive_impls/postgres/scripts"

# Creazione directory dati
mkdir -p "$NEO4J_TARGET_DIR"
mkdir -p "$POSTGRES_TARGET_DIR"

echo "Patching header CSV per Neo4j..."
RAW_DATA_DIR="$RAW_DATA_DIR" python3 patch_headers.py
echo "Patch degli header completata."

echo "Importazione in Neo4j..."
# Cartella degli header sulla nostra macchina
HEADER_DIR_HOST="$(dirname "$RAW_DATA_DIR")/headers"

# Variabili per neo4j-admin
NODE_ARGS=""
REL_ARGS=""

# Generazione argomenti tramite script Python per superare i limiti di bash
ARGS=$(python3 -c "
import os
raw_dir = '$RAW_DATA_DIR'
header_dir = '/headers'
import_dir = '/import'

nodes = []
rels = []

for sub in ['dynamic', 'static']:
    d = os.path.join(raw_dir, sub)
    if not os.path.exists(d): continue
    for name in os.listdir(d):
        if '_' in name:
            label = name.split('_')[1].upper() # Simplified label
            if 'knows' in name.lower(): label = 'KNOWS'
            elif 'likes' in name.lower(): label = 'LIKES'
            elif 'hascreator' in name.lower(): label = 'HAS_CREATOR'
            elif 'hastag' in name.lower(): label = 'HAS_TAG'
            elif 'islocatedin' in name.lower(): label = 'IS_LOCATED_IN'
            elif 'containerof' in name.lower(): label = 'CONTAINER_OF'
            elif 'hasmember' in name.lower(): label = 'HAS_MEMBER'
            elif 'hasmoderator' in name.lower(): label = 'HAS_MODERATOR'
            elif 'hasinterest' in name.lower(): label = 'HAS_INTEREST'
            elif 'studyat' in name.lower(): label = 'STUDY_AT'
            elif 'workat' in name.lower(): label = 'WORK_AT'
            elif 'replyof' in name.lower(): label = 'REPLY_OF'
            elif 'ispartof' in name.lower(): label = 'IS_PART_OF'
            elif 'hastype' in name.lower(): label = 'HAS_TYPE'
            elif 'issubclassof' in name.lower(): label = 'IS_SUBCLASS_OF'
            
            rels.append(f'--relationships={label}={header_dir}/{name}-header.csv,{import_dir}/{sub}/{name}/.*\.csv')
        else:
            label = name
            nodes.append(f'--nodes={label}={header_dir}/{name}-header.csv,{import_dir}/{sub}/{name}/.*\.csv')

print(' '.join(nodes + rels))
")

docker run --rm \
  -v "$NEO4J_TARGET_DIR":/data \
  -v "$RAW_DATA_DIR":/import \
  -v "$HEADER_DIR_HOST":/headers \
  -e NEO4J_server_memory_heap_max__size=1G \
  neo4j:5.20.0-community \
  neo4j-admin database import full neo4j \
  --delimiter='|' \
  --array-delimiter=';' \
  --multiline-fields=true \
  --overwrite-destination=true \
  --skip-duplicate-nodes=true \
  --skip-bad-relationships=true \
  --bad-tolerance=10000000 \
  $ARGS

echo "Importazione in Postgres..."
PG_CSV_DIR="$LAB_DIR/data/postgres-csv-formatted"
mkdir -p "$PG_CSV_DIR"

echo "Preparazione CSV per Postgres..."
python3 postgres_prep.py

cd "$LDBC_PG_SCRIPTS"

# Pulizia vecchia directory dati Postgres
echo "Pulizia directory Postgres..."
docker run --rm \
  -v "$(dirname "$POSTGRES_TARGET_DIR")":/pgdata \
  ubuntu \
  rm -rf "/pgdata/$(basename "$POSTGRES_TARGET_DIR")"
mkdir -p "$POSTGRES_TARGET_DIR"

# Ripristino di vars.sh al valore di default
git checkout -- vars.sh

# Iniezione dei percorsi customizzati
echo "export POSTGRES_CSV_DIR=\"$PG_CSV_DIR/\"" >> vars.sh
echo "export POSTGRES_DATA_DIR=\"$POSTGRES_TARGET_DIR\"" >> vars.sh

# Esecuzione degli script di avvio LDBC
./start.sh
./load-in-one-step.sh
./stop.sh

echo "============================================="
echo "✅ Completato. Database generati con successo."
echo "============================================="
cd "$LAB_DIR"