# Makefile per l'infrastruttura (gestione del ciclo di vita dei database)
#
# COME SI USA:
#
#   Per generare i file CSV con i dati:
#     make generate SF=0.1      – genera i dati (SF=0.1)
#     make generate SF=1        – genera i dati (SF=1)
#
#   Per caricare i CSV dentro Neo4j e Postgres:
#     make build SF=0.1         
#     make build SF=1           
#
#   Avvio/stop:
#     make up SF=0.1            – avvia i container
#     make down                 – termina i container
#
#   Combo utili:
#     make reset SF=0.1         – fa down + build + up (per alternare tra i dataset)
#
#   Inizializzazione ambiente:
#     make setup                – per installare le dipendenze

.PHONY: help setup generate build up down clean deep-clean reset

# ---------------------------------------------------------------------------
# Variabili – override con SF=<valore> da riga di comando
# ---------------------------------------------------------------------------
SF           ?= 0.1
DATA_DIR      = out-sf$(SF)
LAB_DATA_DIR  = data

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
help:
	@echo ""
	@echo "--- Makefile per gestire i DB e i dati ---"
	@echo ""
	@echo "  make generate SF=0.1   Genera CSV piccoli"
	@echo "  make generate SF=1     Genera CSV (SF=1, richiede tempo)"
	@echo ""
	@echo "  make build SF=0.1      Importa SF 0.1 nei DB"
	@echo "  make build SF=1        Importa SF 1 nei DB"
	@echo ""
	@echo "  make up SF=0.1         Avvia i container"
	@echo "  make down              Termina i container"
	@echo ""
	@echo "  make reset SF=0.1      Ricostruzione completa ambiente (down, build, up)"
	@echo ""
	@echo "  make setup             Installazione dipendenze di sistema"
	@echo ""

# Installazione iniziale per preparare la VM o il PC
setup:
	@echo "Installing system dependencies..."
	sudo apt update && sudo apt install -y docker.io docker-compose-v2 git python3 python3-pip
	sudo apt install -y python3-pandas
	pip3 install --user psycopg || pip3 install --user psycopg --break-system-packages
	sudo systemctl enable --now docker
	sudo usermod -aG docker $$USER
	@if [ ! -d "ldbc_snb_interactive_impls" ]; then \
		echo "Cloning ldbc_snb_interactive_impls..."; \
		git clone https://github.com/ldbc/ldbc_snb_interactive_impls.git; \
	fi

# Generazione del dataset LDBC in formato CSV.
# Omette la sovrascrittura se la directory esiste.
generate:
	@echo "============================================================"
	@echo "  Generazione dataset SF $(SF)"
	@echo "============================================================"
	@if [ -d "$(DATA_DIR)/graphs" ]; then \
		echo "[SKIP] $(DATA_DIR)/ già presente. Cancellalo per rigenerare."; \
	else \
		echo "Avvio generazione (può richiedere fino a 30min per SF 1)..."; \
		MEMORY=8g; \
		if [ "$(SF)" = "1" ]; then MEMORY=12g; fi; \
		docker run --rm -v $(PWD)/$(DATA_DIR):/out ldbc/datagen-standalone:latest \
			--memory $$MEMORY -y -- \
			--scale-factor $(SF) \
			--mode raw \
			--format csv \
			--explode-edges \
			--output-dir /out; \
		docker run --rm -v $(PWD):/app ubuntu chown -R 1000:1000 /app/$(DATA_DIR); \
		echo "[OK] Dataset SF $(SF) generato in $(PWD)/$(DATA_DIR)"; \
	fi

# Importazione dei CSV nei volumi Docker
# (tramite script di caricamento batch)
build:
	@echo "============================================================"
	@echo "  Build database SF $(SF)"
	@echo "============================================================"
	@if [ ! -d "$(DATA_DIR)/graphs" ]; then \
		echo "[ERR] Dataset non trovato: $(DATA_DIR)/graphs"; \
		echo "      Esegui prima: make generate SF=$(SF)"; \
		exit 1; \
	fi
	chmod +x build-databases.sh
	SCALE_FACTOR=$(SF) bash ./build-databases.sh

# Avvio dei container tramite docker-compose
# Esegue down preliminare per evitare conflitti di porta
up:
	@echo "============================================================"
	@echo "  Avvio container SF $(SF)"
	@echo "============================================================"
	@echo "[1/4] Fermo container attualmente attivi (se presenti)..."
	-docker compose -f docker-compose.yml down 2>/dev/null || true
	@echo "[2/4] Avvio container con volume SF $(SF)..."
	SCALE_FACTOR=$(SF) docker compose -f docker-compose.yml up -d
	@echo "[3/4] Attendo che Neo4j sia pronto..."
	@until docker exec neo4j-benchmark cypher-shell -u neo4j -p password "RETURN 1" > /dev/null 2>&1; do \
		printf "."; sleep 2; \
	done
	@echo ""
	@echo "[4/4] Applico constraint e indici Neo4j..."
	cat neo4j_setup.cypher | docker exec -i neo4j-benchmark cypher-shell -u neo4j -p password
	@echo "[OK] Container pronti. Verifica contenuto:"
	@docker exec neo4j-benchmark cypher-shell -u neo4j -p password \
		"MATCH (p:Person) RETURN count(p) AS n_persons;" 2>/dev/null

# Sospensione database con persistenza dati
down:
	@echo "Stopping databases..."
	-SCALE_FACTOR=$(SF) docker compose -f docker-compose.yml down 2>/dev/null || true

# Terminazione completa e rimozione dei volumi Docker
clean: down
	@echo "Removing Docker volumes for SF $(SF)..."
	docker run --rm -v $(PWD):/app ubuntu rm -rf /app/$(LAB_DATA_DIR)
	@echo "Done. I CSV grezzi in $(DATA_DIR)/ sono stati mantenuti."

# Rimozione completa (include volumi e CSV generati)
deep-clean: clean
	@echo "Removing raw CSV data for SF $(SF)..."
	docker run --rm -v $(PWD):/app ubuntu rm -rf /app/$(DATA_DIR)

# Ripristino completo dell'ambiente (down, build, up).
# Consigliato per il cambio di Scale Factor.
reset: down build up
	@echo ""
	@echo "============================================================"
	@echo "  [OK] Ambiente pronto per SF $(SF)"
	@echo "============================================================"
