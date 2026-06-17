from neo4j import GraphDatabase
import threading, time

driver = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password"))

target_id = 933
# Verifica nodo target

def reader():
    results = {}
    with driver.session() as s:
        tx = s.begin_transaction()
        tx.run("MATCH (p:Person {id: $pid}) SET p._dummy_ = true", pid=target_id).consume()
        res1 = tx.run("MATCH (p:Person {id: $pid})-[:KNOWS]->(f) RETURN count(f) AS c", pid=target_id).single()
        c1 = res1["c"] if res1 else 0
        time.sleep(1)
        res2 = tx.run("MATCH (p:Person {id: $pid})-[:KNOWS]->(f) RETURN count(f) AS c", pid=target_id).single()
        c2 = res2["c"] if res2 else 0
        tx.run("MATCH (p:Person {id: $pid}) REMOVE p._dummy_", pid=target_id).consume()
        tx.commit()
        print(f"Reader: c1={c1}, c2={c2}")

def writer():
    time.sleep(0.1)
    with driver.session() as s:
        s.run("MATCH (p:Person {id: $pid}) CREATE (p)-[:KNOWS]->(:Person {id: -999, _phantom_: true})", pid=target_id)
    print("Writer finished")
    
    with driver.session() as s:
        s.run("MATCH (p:Person {id: -999}) DETACH DELETE p")

t1 = threading.Thread(target=reader)
t2 = threading.Thread(target=writer)
t1.start()
t2.start()
t1.join()
t2.join()
