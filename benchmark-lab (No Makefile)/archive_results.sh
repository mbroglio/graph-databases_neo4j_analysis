#!/bin/bash
# Script di archiviazione dei risultati (nella directory relativa allo Scale Factor corrente)
# per prevenire la sovrascrittura dei file JSON generati dalle esecuzioni sequenziali.
#
# Utilizzo: ./archive_results.sh <cartella_scenario>
#
# Rilevamento automatico dello Scale Factor (SF):
#   - Conteggio dei nodi Person sull'istanza neo4j-benchmark (nodo singolo)
#   - In caso di fallimento (es. test cluster, scenario 3), viene interrogato il nodo neo4j-core1
#   - In caso di indisponibilità dei database, viene applicato SF0.1 come valore di default con avviso.

SCENARIO=$1
if [ -z "$SCENARIO" ]; then
    echo "Uso: $0 <scenario_dir>"
    exit 1
fi

# Determinazione dello Scale Factor (SF0.1 o SF1) basata sul numero di nodi (priorità a istanza singola)
COUNT=""
if docker inspect neo4j-benchmark > /dev/null 2>&1; then
    COUNT=$(docker exec neo4j-benchmark cypher-shell -u neo4j -p password \
        "MATCH (p:Person) RETURN count(p);" 2>/dev/null \
        | grep -E '^[0-9]+$' | head -1)
fi

if [ -z "$COUNT" ] || [ "$COUNT" = "0" ]; then
    # Istanza singola non disponibile. Rilevamento tramite nodo 1 del cluster (scenario 3)
    COUNT=$(docker exec neo4j-core1 cypher-shell -u neo4j -p password \
        "MATCH (p:Person) RETURN count(p);" 2>/dev/null \
        | grep -E '^[0-9]+$' | head -1)
fi

if [ -z "$COUNT" ]; then
    echo "[WARNING] Impossibile stabilire una connessione ai database. Impostazione fallback su SF0.1"
    COUNT=0
fi

if [ "$COUNT" -gt 5000 ]; then
    SCALE="SF1"
else
    SCALE="SF0.1"
fi

echo "Archiving results for $SCENARIO as $SCALE (${COUNT} Person)..."
ARCHIVE_DIR="$SCENARIO/archive_$SCALE"
mkdir -p "$ARCHIVE_DIR"

if [ -f "$SCENARIO/results.json" ]; then
    mv "$SCENARIO/results.json" "$ARCHIVE_DIR/results.json"
    echo "  Spostato: results.json"
fi

for svg in "$SCENARIO"/*.svg; do
    if [ -f "$svg" ]; then
        mv "$svg" "$ARCHIVE_DIR/"
        echo "  Spostato: $(basename "$svg")"
    fi
done

for txt in "$SCENARIO"/*.txt; do
    if [ -f "$txt" ]; then
        mv "$txt" "$ARCHIVE_DIR/"
        echo "  Spostato: $(basename "$txt")"
    fi
done

echo "Saved and cleaned up $SCENARIO -> $ARCHIVE_DIR"
