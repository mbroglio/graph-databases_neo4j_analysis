# Makefile per automatizzare l'esecuzione dei test per la tesina.
#
# IMPORTANTE: i container di Postgres e Neo4j devono essere già up
# (devono essere avviati tramite il Makefile in infrastructure/).
#
# Comandi principali:
#   make scenario1   – Esecuzione Scenario 1
#   make scenario2   – Esecuzione Scenario 2 (ACID)
#   make scenario3   – Avvio cluster Raft ed esecuzione Scenario 3
#   make scenario4   – Esecuzione Scenario 4
#
# Lo Scale Factor (SF) viene rilevato automaticamente e i risultati sono salvati nelle
# directory separate archive_SF0.1 o archive_SF1 per evitare sovrascritture.
#
# Per cambiare dataset:
#   cd ../infrastructure && make reset SF=1 (oppure 0.1)

.PHONY: help scenario1 scenario2 scenario3 scenario4 query-plans wait-db scenario3-teardown

help:
	@echo ""
	@echo "--- Comandi disponibili per i benchmark ---"
	@echo ""
	@echo "  make scenario1   Scenario 1: Potenza del Grafo"
	@echo "                   (Nota: la query a 4 hop su SF1 richiede tempi di calcolo estesi)"
	@echo ""
	@echo "  make scenario2   Scenario 2: Transazioni (ACID)"
	@echo ""
	@echo "  make scenario3   Scenario 3: Sistemi Distribuiti (CAP)"
	@echo "                   (Gestione automatica cluster 5 nodi)"
	@echo ""
	@echo "  make scenario4   Scenario 4: I punti deboli di Neo4j"
	@echo ""
	@echo "  make query-plans      Estrazione dei piani di esecuzione (EXPLAIN/PROFILE)"
	@echo "  make wait-db          Attesa della disponibilità dei database"
	@echo "  make scenario3-teardown  Terminazione del cluster e pulizia in caso di errore"
	@echo ""

# Scenario 1 - Potenza del Grafo
# (Multi-hop, Triangle Detection, Shortest Path)
# La query a 4 hop presenta tempi elevati; è mantenuta per evidenziare il degrado prestazionale.
scenario1:
	@echo "========================================================"
	@echo "  Scenario 1: La Potenza del Grafo"
	@echo "========================================================"
	python3 scenario1/scenario1_benchmark.py
	python3 scenario1/plot_scenario1.py
	./archive_results.sh scenario1

# Scenario 2 - Transazioni e Concorrenza
# (Read Committed, Lost Update, Deadlock). Durata stimata: circa 2 minuti.
scenario2: wait-db
	@echo "========================================================"
	@echo "  Scenario 2: Transazioni e Concorrenza"
	@echo "========================================================"
	python3 scenario2/scenario2_benchmark.py
	python3 scenario2/scenario2_wal.py
	./archive_results.sh scenario2

# Scenario 3 - Sistemi distribuiti
# Lancia il cluster Raft e testa fault tolerance (spengendo nodi) e causal consistency.
scenario3:
	@echo "========================================================"
	@echo "  Scenario 3: Sistemi Distribuiti / Teorema CAP"
	@echo "========================================================"
	bash scenario3/run_scenario3.sh
	./archive_results.sh scenario3

# Scenario 4 - Punti deboli di Neo4j
# (Aggregazioni globali, Bulk Insert, esplorazione di path non filtrati).
# È presente un timeout per prevenire OOM del container.
scenario4: wait-db
	@echo "========================================================"
	@echo "  Scenario 4: I Punti Deboli di Neo4j"
	@echo "========================================================"
	python3 scenario4/scenario4_benchmark.py
	./archive_results.sh scenario4

# Funzione helper per aspettare che i DB single instance tornino up
# (necessario dopo il test del cluster Raft)
wait-db:
	@echo "[wait-db] Verifico che i DB single-instance siano in esecuzione..."
	@if ! docker inspect neo4j-benchmark >/dev/null 2>&1; then \
		echo "[wait-db] ERRORE: container neo4j-benchmark non trovato."; \
		echo "         Esegui prima: cd ../infrastructure && make reset SF=<valore>"; \
		exit 1; \
	fi
	@echo "[wait-db] Attendo Neo4j single-instance (max 120s)..."
	@n=0; \
	until docker exec neo4j-benchmark cypher-shell -u neo4j -p password "RETURN 1" >/dev/null 2>&1; do \
		if [ $$n -ge 60 ]; then \
			echo "[wait-db] TIMEOUT: Neo4j non risponde dopo 120s."; \
			exit 1; \
		fi; \
		printf "."; \
		sleep 2; \
		n=$$((n+1)); \
	done; \
	echo ""
	@echo "[wait-db] Attendo PostgreSQL single-instance (max 60s)..."
	@n=0; \
	until docker exec postgres-benchmark pg_isready -U postgres >/dev/null 2>&1; do \
		if [ $$n -ge 30 ]; then \
			echo "[wait-db] TIMEOUT: PostgreSQL non risponde dopo 60s."; \
			exit 1; \
		fi; \
		printf "."; \
		sleep 2; \
		n=$$((n+1)); \
	done; \
	echo ""
	@echo "[wait-db] OK: Neo4j e PostgreSQL pronti."

# Helper per l'interruzione forzata del cluster in caso di anomalie
# e ripristino delle istanze singole
scenario3-teardown:
	@echo "[teardown] Abbatto il cluster Raft (se attivo)..."
	@docker compose -f ../infrastructure/docker-compose-cluster.yml down -v 2>/dev/null || true
	@SF=$$(docker inspect neo4j-benchmark \
		--format '{{ range .Mounts }}{{ if eq .Destination "/data" }}{{ .Name }}{{ end }}{{ end }}' 2>/dev/null \
		| grep -o 'sf[0-9.]*' | head -1 | sed 's/sf//'); \
	SF=$${SF:-0.1}; \
	echo "[teardown] Riavvio single-instance con SF=$${SF}..."; \
	SCALE_FACTOR="$${SF}" docker compose -f ../infrastructure/docker-compose.yml up -d 2>/dev/null || true
	@$(MAKE) wait-db

# Estrazione dei Query Plan (salva l'appendice)
query-plans:
	@echo "Collecting Query Plans (EXPLAIN / PROFILE)..."
	python3 collect_query_plans.py
