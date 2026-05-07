"""
Kuzu Graph Database — Demo Example
===================================
This script demonstrates the core features of Kuzu, an embeddable
property-graph database. It creates an in-memory database, defines
a schema, loads sample data, and runs several Cypher queries.

Run:
    uv run example.py

Prerequisites:
    make python-install   (builds C++ and installs the kuzu Python package)
"""

import shutil
import os
import kuzu

DB_PATH = "example_db"

def main():
    # Clean up any previous run
    if os.path.exists(DB_PATH):
        shutil.rmtree(DB_PATH)

    # ── Create database and connection ──────────────────────────────
    db = kuzu.Database(DB_PATH)
    conn = kuzu.Connection(db)
    print("✓ Created Kuzu database at ./%s\n" % DB_PATH)

    # ── Define schema ───────────────────────────────────────────────
    conn.execute("CREATE NODE TABLE User(name STRING, age INT64, PRIMARY KEY (name))")
    conn.execute("CREATE NODE TABLE City(name STRING, population INT64, PRIMARY KEY (name))")
    conn.execute("CREATE REL TABLE Follows(FROM User TO User, since INT64)")
    conn.execute("CREATE REL TABLE LivesIn(FROM User TO City)")
    print("✓ Schema created (User, City, Follows, LivesIn)\n")

    # ── Load data from the bundled demo CSV files ───────────────────
    csv_dir = os.path.join(os.path.dirname(__file__), "dataset", "demo-db", "csv")
    conn.execute('COPY User FROM "%s/user.csv"' % csv_dir)
    conn.execute('COPY City FROM "%s/city.csv"' % csv_dir)
    conn.execute('COPY Follows FROM "%s/follows.csv"' % csv_dir)
    conn.execute('COPY LivesIn FROM "%s/lives-in.csv"' % csv_dir)
    print("✓ Loaded demo data from %s\n" % csv_dir)

    # ── Query 1: List all users ─────────────────────────────────────
    print("─── All Users ───────────────────────────────────────────")
    result = conn.execute("MATCH (u:User) RETURN u.name AS name, u.age AS age ORDER BY u.name")
    while result.has_next():
        row = result.get_next()
        print("  %s (age %d)" % (row[0], row[1]))
    print()

    # ── Query 2: Who follows whom? ──────────────────────────────────
    print("─── Follow Relationships ────────────────────────────────")
    result = conn.execute(
        "MATCH (a:User)-[f:Follows]->(b:User) "
        "RETURN a.name AS follower, b.name AS followee, f.since AS since "
        "ORDER BY f.since"
    )
    while result.has_next():
        row = result.get_next()
        print("  %s → %s (since %d)" % (row[0], row[1], row[2]))
    print()

    # ── Query 3: Where does everyone live? ──────────────────────────
    print("─── Residence ───────────────────────────────────────────")
    result = conn.execute(
        "MATCH (u:User)-[:LivesIn]->(c:City) "
        "RETURN u.name AS person, c.name AS city, c.population AS pop "
        "ORDER BY u.name"
    )
    while result.has_next():
        row = result.get_next()
        print("  %s lives in %s (pop. %s)" % (row[0], row[1], f"{row[2]:,}"))
    print()

    # ── Query 4: 2-hop path — who do the followers of Adam follow? ──
    print("─── 2-Hop Follows from Adam ─────────────────────────────")
    result = conn.execute(
        "MATCH (a:User)-[:Follows]->(b:User)-[:Follows]->(c:User) "
        "WHERE a.name = 'Adam' "
        "RETURN a.name AS start, b.name AS mid, c.name AS dest"
    )
    while result.has_next():
        row = result.get_next()
        print("  %s → %s → %s" % (row[0], row[1], row[2]))
    print()

    # ── Query 5: Shortest path ──────────────────────────────────────
    print("─── Shortest Path: Adam → Noura ─────────────────────────")
    result = conn.execute(
        "MATCH p = (a:User)-[:Follows* SHORTEST 1..10]->(b:User) "
        "WHERE a.name = 'Adam' AND b.name = 'Noura' "
        "RETURN nodes(p), length(p) AS hops"
    )
    while result.has_next():
        row = result.get_next()
        nodes = row[0]
        hops = row[1]
        path_names = " → ".join(n["name"] for n in nodes)
        print("  Path (%d hops): %s" % (hops, path_names))
    print()

    # ── Cleanup ─────────────────────────────────────────────────────
    if os.path.isdir(DB_PATH):
        shutil.rmtree(DB_PATH)
    elif os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    print("✓ Cleaned up %s. Done!" % DB_PATH)


if __name__ == "__main__":
    main()
