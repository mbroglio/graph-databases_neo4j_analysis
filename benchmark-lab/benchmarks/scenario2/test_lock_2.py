from neo4j import GraphDatabase
import threading, time

driver = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password"))

def reader():
    with driver.session() as s:
        tx = s.begin_transaction()
        tx.run("MATCH (p:Person {id: 1}) SET p._dummy_ = true").consume()
        print("Reader: Lock acquired")
        time.sleep(3)
        print("Reader: Committing")
        tx.commit()

def writer():
    time.sleep(0.5)
    print("Writer: Attempting to modify")
    t0 = time.time()
    with driver.session() as s:
        s.run("MATCH (p:Person {id: 1}) CREATE (p)-[:KNOWS]->(:Person {id: -999, _phantom_: true})")
    print(f"Writer: Done in {time.time()-t0:.2f}s")
    # cleanup
    with driver.session() as s:
        s.run("MATCH (p:Person {id: -999}) DETACH DELETE p")

t1 = threading.Thread(target=reader)
t2 = threading.Thread(target=writer)
t1.start()
t2.start()
t1.join()
t2.join()
