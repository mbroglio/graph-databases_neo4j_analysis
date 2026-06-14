from neo4j import GraphDatabase
import time

driver = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password"))

def test_indexes():
    # 1. Trova un nome comune per la ricerca
    name_to_search = "Smith"
    
    # 2. Drop index se esiste
    try:
        with driver.session() as s:
            s.run("DROP INDEX person_lastName IF EXISTS")
    except Exception:
        pass
        
    time.sleep(2)
    
    # 3. Misura senza indice (Full Scan)
    print("Test senza indice (O(N)):")
    t0 = time.perf_counter()
    with driver.session() as s:
        res = s.run("MATCH (p:Person {lastName: $name}) RETURN count(p) as c", name=name_to_search).single()
    t1 = time.perf_counter()
    print(f"  Count: {res['c']} - Time: {(t1-t0)*1000:.2f} ms")
    
    # 4. Crea indice
    print("\nCreazione indice (O(log N))...")
    with driver.session() as s:
        s.run("CREATE INDEX person_lastName IF NOT EXISTS FOR (p:Person) ON (p.lastName)")
    
    # Aspetta che l'indice sia online
    time.sleep(5)
    
    # 5. Misura con indice
    print("\nTest con indice (O(log N)):")
    t0 = time.perf_counter()
    with driver.session() as s:
        res = s.run("MATCH (p:Person {lastName: $name}) RETURN count(p) as c", name=name_to_search).single()
    t1 = time.perf_counter()
    print(f"  Count: {res['c']} - Time: {(t1-t0)*1000:.2f} ms")
    
    # Cleanup
    with driver.session() as s:
        s.run("DROP INDEX person_lastName IF EXISTS")

test_indexes()
