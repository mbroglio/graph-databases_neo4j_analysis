import os
import subprocess
import time
from neo4j import GraphDatabase

def wait_for_neo4j():
    for _ in range(60):
        try:
            d = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password"))
            with d.session() as s:
                s.run("RETURN 1")
            d.close()
            return True
        except Exception:
            time.sleep(1)
    return False

def test_wal():
    print("=== TEST WAL e CRASH RECOVERY ===")
    driver = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password"))
    
    # Inizializza dati
    with driver.session() as s:
        s.run("MATCH (p:Person) REMOVE p.wal_test")
        
    print("[1] Avvio transazione massiva (non confermata)...")
    try:
        with driver.session() as s:
            tx = s.begin_transaction()
            tx.run("MATCH (p:Person) SET p.wal_test = 'in_progress'")
            # Mantiene attiva la transazione e simula failure
            print("[2] Esecuzione DOCKER KILL (simulazione crash del server) durante transazione attiva...")
            subprocess.run(["docker", "kill", "neo4j-benchmark"], check=True)
            # Attende spegnimento container
            time.sleep(2)
            # Impossibile eseguire commit
    except Exception as e:
        print(f"  [!] Connessione interrotta attesa: {e}")
        
    print("[3] Esecuzione DOCKER START (Recovery phase)...")
    subprocess.run(["docker", "start", "neo4j-benchmark"], check=True)
    
    print("[4] Attesa disponibilità database...")
    wait_for_neo4j()
    
    # Esegue verifica
    print("[5] Verifica integrità dati (Atomicity / Rollback via WAL)...")
    driver = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password"))
    with driver.session() as s:
        res = s.run("MATCH (p:Person {wal_test: 'in_progress'}) RETURN count(p) as c").single()
        c = res["c"]
        if c == 0:
            print("  ✅ OK: WAL ha effettuato correttamente il rollback delle modifiche in sospeso! (0 nodi spuri)")
        else:
            print(f"  ❌ ERRORE: Trovati {c} nodi con dati parziali!")
            
    # Esegue pulizia
    with driver.session() as s:
        s.run("MATCH (p:Person) REMOVE p.wal_test")

test_wal()
