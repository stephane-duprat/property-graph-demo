-- Exact SQL panels from adb26ai-property-graphs-step-by-step.pdf.
-- Execute step by step; stop at the first error. Use a dedicated demo schema.
-- Do not run after another setup path has already created the same objects.

-- Step 01.1: Check the instance before creating objects
SELECT product, version, version_full FROM product_component_version;

-- Step 01.2: Check the instance before creating objects
SELECT USER AS connected_user,
       SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS current_schema
FROM dual;

-- Step 01.3: Check the instance before creating objects
SELECT privilege FROM session_privs
WHERE privilege IN ('CREATE SESSION','CREATE TABLE','CREATE VIEW',
                    'CREATE SYNONYM','CREATE PROPERTY GRAPH')
ORDER BY privilege;

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM user_objects
  WHERE UPPER(object_name) LIKE 'PGD\_%' ESCAPE '\';
  IF n <> 0 THEN
    RAISE_APPLICATION_ERROR(-20000,
      'PGD_ objects already exist. Use a fresh schema or review 99_cleanup.sql.');
  END IF;
END;
/

-- Step A1.1: Create entities and directed relationships
CREATE TABLE pgd_person (
  person_id NUMBER CONSTRAINT pgd_person_pk PRIMARY KEY,
  person_name VARCHAR2(50) NOT NULL,
  city VARCHAR2(50) NOT NULL
);

CREATE TABLE pgd_knows (
  edge_id NUMBER CONSTRAINT pgd_knows_pk PRIMARY KEY,
  src_id NUMBER NOT NULL,
  dst_id NUMBER NOT NULL,
  since_year NUMBER(4) NOT NULL,
  CONSTRAINT pgd_knows_src_fk FOREIGN KEY (src_id) REFERENCES pgd_person(person_id),
  CONSTRAINT pgd_knows_dst_fk FOREIGN KEY (dst_id) REFERENCES pgd_person(person_id)
);

CREATE INDEX pgd_knows_src_ix ON pgd_knows(src_id);

CREATE INDEX pgd_knows_dst_ix ON pgd_knows(dst_id);

-- Step A2.1: Load a small network you can reason about
INSERT INTO pgd_person VALUES (1, 'Alice', 'Madrid');
INSERT INTO pgd_person VALUES (2, 'Bob', 'Barcelona');
INSERT INTO pgd_person VALUES (3, 'Carla', 'Madrid');
INSERT INTO pgd_person VALUES (4, 'Diego', 'Valencia');
INSERT INTO pgd_person VALUES (5, 'Elena', 'Bilbao');
INSERT INTO pgd_knows VALUES (101, 1, 2, 2020);
INSERT INTO pgd_knows VALUES (102, 1, 3, 2021);
INSERT INTO pgd_knows VALUES (103, 2, 4, 2022);
INSERT INTO pgd_knows VALUES (104, 3, 4, 2023);
INSERT INTO pgd_knows VALUES (105, 4, 1, 2024);
INSERT INTO pgd_knows VALUES (106, 2, 5, 2022);
INSERT INTO pgd_knows VALUES (107, 5, 3, 2024);
COMMIT;

-- Step A2.2: Load a small network you can reason about
SELECT * FROM pgd_person ORDER BY person_id;

SELECT * FROM pgd_knows ORDER BY edge_id;

-- Step A3.1: Map those rows into a property graph
CREATE PROPERTY GRAPH pgd_rel_graph
  VERTEX TABLES (
    pgd_person AS people KEY (person_id)
      LABEL person PROPERTIES (person_id, person_name AS name, city)
  )
  EDGE TABLES (
    pgd_knows AS links KEY (edge_id)
      SOURCE KEY (src_id) REFERENCES people (person_id)
      DESTINATION KEY (dst_id) REFERENCES people (person_id)
      LABEL knows PROPERTIES (edge_id, since_year)
  )
  OPTIONS (ENFORCED MODE);

-- Step A4.1: Follow one edge, then two edges
SELECT neighbor, since_year
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (a IS person)-[e IS knows]->(b IS person)
  WHERE a.person_id = 1
  COLUMNS (b.name AS neighbor, e.since_year AS since_year)
)
ORDER BY neighbor;

-- Step A4.2: Follow one edge, then two edges
SELECT start_name, via_name, target_name
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (a IS person)-[e1 IS knows]->(b IS person)
                     -[e2 IS knows]->(c IS person)
  WHERE a.person_id = 1
  COLUMNS (a.name AS start_name, b.name AS via_name,
           c.name AS target_name)
)
ORDER BY via_name, target_name;

-- Step A5.1: Compare with joins and count the routes
SELECT a.person_name AS start_name, b.person_name AS via_name,
       c.person_name AS target_name
FROM pgd_person a
JOIN pgd_knows e1 ON e1.src_id = a.person_id
JOIN pgd_person b ON b.person_id = e1.dst_id
JOIN pgd_knows e2 ON e2.src_id = b.person_id
JOIN pgd_person c ON c.person_id = e2.dst_id
WHERE a.person_id = 1
ORDER BY via_name, target_name;

-- Step A5.2: Compare with joins and count the routes
SELECT target_name, COUNT(*) AS route_count
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (a IS person)-[e1 IS knows]->(b IS person)-[e2 IS knows]->(c IS person)
  WHERE a.person_id = 1
  COLUMNS (c.name AS target_name)
)
GROUP BY target_name
ORDER BY target_name;

-- Step A6.1: Close a cycle and observe a live row update
SELECT start_name, via_name, third_name
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (a IS person)-[e1 IS knows]->(b IS person)
                     -[e2 IS knows]->(c IS person)-[e3 IS knows]->(a)
  WHERE a.person_id = 1 AND b.person_id <> a.person_id
        AND c.person_id <> a.person_id AND b.person_id <> c.person_id
  COLUMNS (a.name AS start_name, b.name AS via_name, c.name AS third_name)
)
ORDER BY via_name;

-- Step A6.2: Close a cycle and observe a live row update
SAVEPOINT pgd_before_rel_update;
UPDATE pgd_person SET city = 'Sevilla' WHERE person_id = 4;
SELECT person_id, person_name, city
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (p IS person)
  COLUMNS (p.person_id AS person_id, p.name AS person_name, p.city AS city)
)
ORDER BY person_id;
ROLLBACK TO pgd_before_rel_update;

-- Step B1.1: Expose scalar identities from stored documents
CREATE JSON COLLECTION TABLE pgd_j_person (
  person_id AS (JSON_VALUE(data, '$._id' RETURNING NUMBER ERROR ON ERROR))
);

CREATE JSON COLLECTION TABLE pgd_j_knows (
  edge_id AS (JSON_VALUE(data, '$._id' RETURNING NUMBER ERROR ON ERROR)),
  src_id AS (JSON_VALUE(data, '$.src' RETURNING NUMBER ERROR ON ERROR)),
  dst_id AS (JSON_VALUE(data, '$.dst' RETURNING NUMBER ERROR ON ERROR))
);

-- Step B2.1: Insert the same network as JSON documents
INSERT INTO pgd_j_person (data) VALUES (JSON(
  '{"_id":1,"name":"Alice","city":"Madrid"}'));
INSERT INTO pgd_j_person (data) VALUES (JSON(
  '{"_id":2,"name":"Bob","city":"Barcelona"}'));
INSERT INTO pgd_j_person (data) VALUES (JSON(
  '{"_id":3,"name":"Carla","city":"Madrid"}'));
INSERT INTO pgd_j_person (data) VALUES (JSON(
  '{"_id":4,"name":"Diego","city":"Valencia"}'));
INSERT INTO pgd_j_person (data) VALUES (JSON(
  '{"_id":5,"name":"Elena","city":"Bilbao"}'));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":101,"src":1,"dst":2,"since":2020}'
  ));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":102,"src":1,"dst":3,"since":2021}'
  ));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":103,"src":2,"dst":4,"since":2022}'
  ));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":104,"src":3,"dst":4,"since":2023}'
  ));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":105,"src":4,"dst":1,"since":2024}'
  ));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":106,"src":2,"dst":5,"since":2022}'
  ));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":107,"src":5,"dst":3,"since":2024}'
  ));
COMMIT;

-- Step B3.1: Validate the identities and endpoints
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM (
    SELECT person_id FROM pgd_j_person
    GROUP BY person_id HAVING person_id IS NULL OR COUNT(*) > 1
  );
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20011, 'Null or duplicate person keys'); END
    IF;
  SELECT COUNT(*) INTO n FROM (
    SELECT edge_id FROM pgd_j_knows
    GROUP BY edge_id HAVING edge_id IS NULL OR COUNT(*) > 1
  );
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20012, 'Null or duplicate edge keys'); END
    IF;
  SELECT COUNT(*) INTO n FROM pgd_j_knows e
  WHERE e.src_id IS NULL OR e.dst_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM pgd_j_person p WHERE p.person_id=e.src_id)
     OR NOT EXISTS (SELECT 1 FROM pgd_j_person p WHERE p.person_id=e.dst_id);
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20013, 'Missing edge endpoints'); END IF;
  DBMS_OUTPUT.PUT_LINE('PASS: projected keys and endpoints are valid');
END;
/

-- Step B4.1: Create the graph and reuse the two-hop query
CREATE PROPERTY GRAPH pgd_json_graph
  VERTEX TABLES (
    pgd_j_person AS people KEY (person_id)
      LABEL person PROPERTIES (person_id,
        JSON_VALUE(data, '$.name' RETURNING VARCHAR2(50)) AS name,
        JSON_VALUE(data, '$.city' RETURNING VARCHAR2(50)) AS city)
  )
  EDGE TABLES (
    pgd_j_knows AS links KEY (edge_id)
      SOURCE KEY (src_id) REFERENCES people (person_id)
      DESTINATION KEY (dst_id) REFERENCES people (person_id)
      LABEL knows PROPERTIES (edge_id, JSON_VALUE(data, '$.since' RETURNING NUMBER) AS
        since_year)
  )
  OPTIONS (TRUSTED MODE);

-- Step B4.2: Create the graph and reuse the two-hop query
SELECT start_name, via_name, target_name
FROM GRAPH_TABLE (pgd_json_graph
  MATCH (a IS person)-[e1 IS knows]->(b IS person)
                     -[e2 IS knows]->(c IS person)
  WHERE a.person_id = 1
  COLUMNS (a.name AS start_name, b.name AS via_name,
           c.name AS target_name)
)
ORDER BY via_name, target_name;

-- Step B5.1: Change a document and inspect both models
SELECT person_id, JSON_SERIALIZE(data RETURNING CLOB PRETTY) AS document
FROM pgd_j_person WHERE person_id = 4;

-- Step B5.2: Change a document and inspect both models
SAVEPOINT pgd_before_json_update;
UPDATE pgd_j_person
SET data = JSON_TRANSFORM(data, SET '$.city' = 'Sevilla')
WHERE person_id = 4;
SELECT person_id, person_name, city
FROM GRAPH_TABLE (pgd_json_graph
  MATCH (p IS person)
  COLUMNS (p.person_id AS person_id, p.name AS person_name, p.city AS city)
)
ORDER BY person_id;
SELECT person_name, city FROM pgd_person WHERE person_id = 4;
ROLLBACK TO pgd_before_json_update;

-- Step C1.1: Add a document interface to the relational tables
CREATE JSON RELATIONAL DUALITY VIEW pgd_people_dv AS
SELECT JSON {
  '_id' : p.person_id,
  'name' : p.person_name,
  'city' : p.city,
  'outgoing' : (
    SELECT JSON_ARRAYAGG(
      JSON {'edge_id' : e.edge_id, 'to' : e.dst_id, 'since' : e.since_year}
      RETURNING JSON)
    FROM pgd_knows e WITH INSERT UPDATE DELETE
    WHERE e.src_id = p.person_id
  )
}
FROM pgd_person p WITH INSERT UPDATE DELETE;

-- Step C1.2: Add a document interface to the relational tables
SELECT JSON_SERIALIZE(data RETURNING CLOB PRETTY) AS alice_document
FROM pgd_people_dv
WHERE JSON_VALUE(data, '$._id' RETURNING NUMBER) = 1;

-- Step C2.1: Write JSON, then read the table and graph
SAVEPOINT pgd_before_duality_update;
UPDATE pgd_people_dv
SET data = JSON_TRANSFORM(data, SET '$.city' = 'Sevilla')
WHERE JSON_VALUE(data, '$._id' RETURNING NUMBER) = 4;
SELECT person_id, person_name, city FROM pgd_person WHERE person_id = 4;
SELECT person_id, person_name, city
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (p IS person)
  COLUMNS (p.person_id AS person_id, p.name AS person_name, p.city AS city)
)
ORDER BY person_id;

-- Step C2.2: Write JSON, then read the table and graph
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_rel_graph
    MATCH (p IS person)
    WHERE p.person_id = 4 AND p.city = 'Sevilla'
    COLUMNS (p.person_id AS id));
  IF n <> 1 THEN RAISE_APPLICATION_ERROR(-20021,
    'pgd_rel_graph: city update not visible'); END IF;
  DBMS_OUTPUT.PUT_LINE('PASS pgd_rel_graph: Diego city is Sevilla');
END;
/

ROLLBACK TO pgd_before_duality_update;

-- Step C3.1: Write a relational edge and observe both interfaces
SAVEPOINT pgd_before_edge_insert;
INSERT INTO pgd_knows VALUES (108, 1, 5, 2026);
SELECT JSON_SERIALIZE(data RETURNING CLOB PRETTY) AS alice_document
FROM pgd_people_dv
WHERE JSON_VALUE(data, '$._id' RETURNING NUMBER) = 1;
SELECT neighbor
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (a IS person)-[e IS knows]->(b IS person)
  WHERE a.person_id = 1
  COLUMNS (b.name AS neighbor)
)
ORDER BY neighbor;
ROLLBACK TO pgd_before_edge_insert;

-- Step C3.2: Write a relational edge and observe both interfaces
ROLLBACK;

-- Step V1.1: Verify the relational graph structure
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_rel_graph MATCH (p IS person) COLUMNS
    (p.person_id AS id));
  IF n <> 5 THEN RAISE_APPLICATION_ERROR(-20001, 'pgd_rel_graph: expected 5 vertices'
    ); END IF;
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_rel_graph MATCH (a IS person)-[e IS
    knows]->(b IS person) COLUMNS (e.edge_id AS id));
  IF n <> 7 THEN RAISE_APPLICATION_ERROR(-20002, 'pgd_rel_graph: expected 7 edges');
    END IF;
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_rel_graph
    MATCH (a IS person)-[e1 IS knows]->(b IS person)-[e2 IS knows]->(c IS person)
    WHERE a.person_id = 1
    COLUMNS (b.person_id AS via_id, c.person_id AS target_id)
  );
  IF n <> 3 THEN RAISE_APPLICATION_ERROR(-20003,
    'pgd_rel_graph: expected 3 two-hop matches'); END IF;
  DBMS_OUTPUT.PUT_LINE('PASS pgd_rel_graph: 5 vertices, 7 edges, 3 two-hop matches');
END;
/

-- Step V2.1: Verify the JSON graph structure
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_json_graph MATCH (p IS person) COLUMNS
    (p.person_id AS id));
  IF n <> 5 THEN RAISE_APPLICATION_ERROR(-20001, 'pgd_json_graph: expected 5 vertices'
    ); END IF;
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_json_graph MATCH (a IS person)-[e IS
    knows]->(b IS person) COLUMNS (e.edge_id AS id));
  IF n <> 7 THEN RAISE_APPLICATION_ERROR(-20002, 'pgd_json_graph: expected 7 edges');
    END IF;
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_json_graph
    MATCH (a IS person)-[e1 IS knows]->(b IS person)-[e2 IS knows]->(c IS person)
    WHERE a.person_id = 1
    COLUMNS (b.person_id AS via_id, c.person_id AS target_id)
  );
  IF n <> 3 THEN RAISE_APPLICATION_ERROR(-20003,
    'pgd_json_graph: expected 3 two-hop matches'); END IF;
  DBMS_OUTPUT.PUT_LINE('PASS pgd_json_graph: 5 vertices, 7 edges, 3 two-hop matches');
END;
/

-- Step V3.1: Verify route values and the restored baseline
DECLARE
  n NUMBER;
BEGIN
  WITH actual AS (
    SELECT via_id, target_id FROM GRAPH_TABLE (pgd_rel_graph
      MATCH (a IS person)-[e1 IS knows]->(b IS person)-[e2 IS knows]->(c IS person)
      WHERE a.person_id = 1
      COLUMNS (b.person_id AS via_id, c.person_id AS target_id))
  ), expected AS (
    SELECT 2 AS via_id, 4 AS target_id FROM dual UNION ALL
    SELECT 2, 5 FROM dual UNION ALL SELECT 3, 4 FROM dual
  ), missing_rows AS (SELECT * FROM expected MINUS SELECT * FROM actual),
     unexpected_rows AS (SELECT * FROM actual MINUS SELECT * FROM expected)
  SELECT (SELECT COUNT(*) FROM missing_rows) +
         (SELECT COUNT(*) FROM unexpected_rows) INTO n FROM dual;
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20004, 'Two-hop route values differ'); END
    IF;

  SELECT COUNT(*) INTO n FROM pgd_person WHERE person_id = 4 AND city = 'Valencia';
  IF n <> 1 THEN RAISE_APPLICATION_ERROR(-20005, 'Relational demo rollback failed');
    END IF;
  SELECT COUNT(*) INTO n FROM pgd_j_person
  WHERE person_id = 4 AND JSON_VALUE(data, '$.city') = 'Valencia';
  IF n <> 1 THEN RAISE_APPLICATION_ERROR(-20006, 'JSON demo rollback failed'); END IF;
  SELECT COUNT(*) INTO n FROM pgd_people_dv;
  IF n <> 5 THEN RAISE_APPLICATION_ERROR(-20007, 'Expected five duality documents');
    END IF;
  DBMS_OUTPUT.PUT_LINE('PASS: expected routes and restored initial state');
END;
/

-- Step V4.1: Inspect what each graph actually reads
SELECT graph_name, element_name, element_kind, object_name
FROM user_pg_elements
WHERE graph_name IN ('PGD_REL_GRAPH','PGD_JSON_GRAPH','PGD_DV_GRAPH')
ORDER BY graph_name, element_kind, element_name;

SELECT 'CORE DEMO COMPLETED' AS status FROM dual;
