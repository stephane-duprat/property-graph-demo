-- A1. Direct outgoing neighbors of Alice: Bob and Carla.
SELECT neighbor, since_year
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (a IS person)-[e IS knows]->(b IS person)
  WHERE a.person_id = 1
  COLUMNS (b.name AS neighbor, e.since_year AS since_year)
)
ORDER BY neighbor;

-- A2. Exactly two directed edges. Expect THREE path matches, TWO distinct destinations.
SELECT start_name, via_name, target_name
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (a IS person)-[e1 IS knows]->(b IS person)
                     -[e2 IS knows]->(c IS person)
  WHERE a.person_id = 1
  COLUMNS (a.name AS start_name, b.name AS via_name,
           c.name AS target_name)
)
ORDER BY via_name, target_name;

-- A3. The same question expressed using ordinary joins.
SELECT a.person_name AS start_name, b.person_name AS via_name,
       c.person_name AS target_name
FROM pgd_person a
JOIN pgd_knows e1 ON e1.src_id = a.person_id
JOIN pgd_person b ON b.person_id = e1.dst_id
JOIN pgd_knows e2 ON e2.src_id = b.person_id
JOIN pgd_person c ON c.person_id = e2.dst_id
WHERE a.person_id = 1
ORDER BY via_name, target_name;

-- A4. SQL can aggregate the rows returned by GRAPH_TABLE.
SELECT target_name, COUNT(*) AS route_count
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (a IS person)-[e1 IS knows]->(b IS person)-[e2 IS knows]->(c IS person)
  WHERE a.person_id = 1
  COLUMNS (c.name AS target_name)
)
GROUP BY target_name
ORDER BY target_name;
-- Diego: 2; Elena: 1. No shortest-path claim is implied.

-- A5. Three-edge cycles anchored on Alice: Alice-Bob-Diego-Alice and
-- Alice-Carla-Diego-Alice. Reusing a binds the end to the start vertex.
SELECT start_name, via_name, third_name
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (a IS person)-[e1 IS knows]->(b IS person)
                     -[e2 IS knows]->(c IS person)-[e3 IS knows]->(a)
  WHERE a.person_id = 1 AND b.person_id <> a.person_id
        AND c.person_id <> a.person_id AND b.person_id <> c.person_id
  COLUMNS (a.name AS start_name, b.name AS via_name, c.name AS third_name)
)
ORDER BY via_name;

-- A6. A SQL property graph reads source rows. This DML needs no graph rebuild.
SAVEPOINT pgd_before_rel_update;
UPDATE pgd_person SET city = 'Sevilla' WHERE person_id = 4;
SELECT person_id, person_name, city
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (p IS person)
  COLUMNS (p.person_id AS person_id, p.name AS person_name, p.city AS city)
)
ORDER BY person_id;
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_rel_graph
    MATCH (p IS person)
    WHERE p.person_id = 4 AND p.city = 'Sevilla'
    COLUMNS (p.person_id AS id));
  IF n <> 1 THEN RAISE_APPLICATION_ERROR(-20021, 'pgd_rel_graph: city update not visible'); END IF;
  DBMS_OUTPUT.PUT_LINE('PASS pgd_rel_graph: Diego city is Sevilla');
END;
/

-- Diego now has city Sevilla in this session. Other sessions see it after COMMIT.
ROLLBACK TO pgd_before_rel_update;
-- The demo restores Valencia before moving on.
