-- Combined SQL/PLSQL for Database Actions > SQL > Run Script.
-- Stop at the first error; use a fresh demo schema.

-- Use an empty demo schema. No database credentials are included in this kit.
-- 26ai is the product name; VERSION_FULL may still begin with 23.
SELECT product, version, version_full FROM product_component_version;
SELECT USER AS current_schema FROM dual;
-- Only creation privileges are needed for this demo's own-schema objects.
-- The owner can query and drop its own property graphs without extra grants.
SELECT privilege FROM session_privs
WHERE privilege IN ('CREATE SESSION','CREATE TABLE','CREATE VIEW',
                    'CREATE SYNONYM','CREATE PROPERTY GRAPH')
ORDER BY privilege;

-- Fail before setup if any pre-existing object uses this demo's namespace.
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


-- Part A. One person row becomes one vertex; one knows row becomes one directed edge.
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

SELECT * FROM pgd_person ORDER BY person_id;
SELECT * FROM pgd_knows ORDER BY edge_id;


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


-- Part B. Actual JSON COLLECTION TABLEs, with scalar virtual columns for graph keys.
-- Keys are COLUMN NAMES, not JSON path expressions in the graph KEY clause.
-- These expression columns are invisible; refer to them explicitly.
CREATE JSON COLLECTION TABLE pgd_j_person (
  person_id AS (JSON_VALUE(data, '$._id' RETURNING NUMBER ERROR ON ERROR))
);
CREATE JSON COLLECTION TABLE pgd_j_knows (
  edge_id AS (JSON_VALUE(data, '$._id' RETURNING NUMBER ERROR ON ERROR)),
  src_id AS (JSON_VALUE(data, '$.src' RETURNING NUMBER ERROR ON ERROR)),
  dst_id AS (JSON_VALUE(data, '$.dst' RETURNING NUMBER ERROR ON ERROR))
);

-- A separate illustrative dataset, seeded independently of the relational tables.
-- No synchronization is configured between Part A and Part B.
INSERT INTO pgd_j_person (data) VALUES (JSON('{"_id":1,"name":"Alice","city":"Madrid"}'));
INSERT INTO pgd_j_person (data) VALUES (JSON('{"_id":2,"name":"Bob","city":"Barcelona"}'));
INSERT INTO pgd_j_person (data) VALUES (JSON('{"_id":3,"name":"Carla","city":"Madrid"}'));
INSERT INTO pgd_j_person (data) VALUES (JSON('{"_id":4,"name":"Diego","city":"Valencia"}'));
INSERT INTO pgd_j_person (data) VALUES (JSON('{"_id":5,"name":"Elena","city":"Bilbao"}'));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":101,"src":1,"dst":2,"since":2020}'));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":102,"src":1,"dst":3,"since":2021}'));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":103,"src":2,"dst":4,"since":2022}'));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":104,"src":3,"dst":4,"since":2023}'));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":105,"src":4,"dst":1,"since":2024}'));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":106,"src":2,"dst":5,"since":2022}'));
INSERT INTO pgd_j_knows (data) VALUES (JSON('{"_id":107,"src":5,"dst":3,"since":2024}'));
COMMIT;

-- TRUSTED mode is a promise made by the modeler. Verify the promise.
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM (
    SELECT person_id FROM pgd_j_person
    GROUP BY person_id HAVING person_id IS NULL OR COUNT(*) > 1
  );
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20011, 'Null or duplicate person keys'); END IF;
  SELECT COUNT(*) INTO n FROM (
    SELECT edge_id FROM pgd_j_knows
    GROUP BY edge_id HAVING edge_id IS NULL OR COUNT(*) > 1
  );
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20012, 'Null or duplicate edge keys'); END IF;
  SELECT COUNT(*) INTO n FROM pgd_j_knows e
  WHERE e.src_id IS NULL OR e.dst_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM pgd_j_person p WHERE p.person_id=e.src_id)
     OR NOT EXISTS (SELECT 1 FROM pgd_j_person p WHERE p.person_id=e.dst_id);
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20013, 'Missing edge endpoints'); END IF;
  DBMS_OUTPUT.PUT_LINE('PASS: projected keys and endpoints are valid');
END;
/

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
      LABEL knows PROPERTIES (edge_id, JSON_VALUE(data, '$.since' RETURNING NUMBER) AS since_year)
  )
  OPTIONS (TRUSTED MODE);

-- B1. Same labels and properties, so only the graph name changes.
SELECT start_name, via_name, target_name
FROM GRAPH_TABLE (pgd_json_graph
  MATCH (a IS person)-[e1 IS knows]->(b IS person)
                     -[e2 IS knows]->(c IS person)
  WHERE a.person_id = 1
  COLUMNS (a.name AS start_name, b.name AS via_name,
           c.name AS target_name)
)
ORDER BY via_name, target_name;

-- B2. Show a document and the scalar key available to the graph.
SELECT person_id, JSON_SERIALIZE(data RETURNING CLOB PRETTY) AS document
FROM pgd_j_person WHERE person_id = 4;

-- B3. A JSON document update appears immediately in the JSON-backed graph.
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
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_json_graph
    MATCH (p IS person)
    WHERE p.person_id = 4 AND p.city = 'Sevilla'
    COLUMNS (p.person_id AS id));
  IF n <> 1 THEN RAISE_APPLICATION_ERROR(-20021, 'pgd_json_graph: city update not visible'); END IF;
  DBMS_OUTPUT.PUT_LINE('PASS pgd_json_graph: Diego city is Sevilla');
END;
/

-- Part A is independent: Diego remains in Valencia there.
SELECT person_name, city FROM pgd_person WHERE person_id = 4;
ROLLBACK TO pgd_before_json_update;


-- Part C. A document API and a graph over the SAME normalized tables.
-- No copying and no graph-on-view support needed for this recommended arrangement.
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

SELECT JSON_SERIALIZE(data RETURNING CLOB PRETTY) AS alice_document
FROM pgd_people_dv
WHERE JSON_VALUE(data, '$._id' RETURNING NUMBER) = 1;
-- Alice's outgoing array represents edges 101 and 102. Array order is unspecified.
-- Oracle also adds _metadata; its ETAG/SCN values are not fixed demo outputs.

-- C1. Update JSON, then read relational data and the ORIGINAL relational graph.
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

-- Both show Diego in Sevilla. The duality view writes the base row.
ROLLBACK TO pgd_before_duality_update;

-- C2. Update relationally, then read JSON. This also changes the graph topology.
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
-- JSON now contains edge 108; graph neighbors are Bob, Carla, Elena.
ROLLBACK TO pgd_before_edge_insert;
-- Restored: 5 vertices, 7 edges. No DDL occurs between SAVEPOINT and ROLLBACK.


-- Core assertions: errors are raised if expected results do not hold.
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_rel_graph MATCH (p IS person) COLUMNS (p.person_id AS id));
  IF n <> 5 THEN RAISE_APPLICATION_ERROR(-20001, 'pgd_rel_graph: expected 5 vertices'); END IF;
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_rel_graph MATCH (a IS person)-[e IS knows]->(b IS person) COLUMNS (e.edge_id AS id));
  IF n <> 7 THEN RAISE_APPLICATION_ERROR(-20002, 'pgd_rel_graph: expected 7 edges'); END IF;
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_rel_graph
    MATCH (a IS person)-[e1 IS knows]->(b IS person)-[e2 IS knows]->(c IS person)
    WHERE a.person_id = 1
    COLUMNS (b.person_id AS via_id, c.person_id AS target_id)
  );
  IF n <> 3 THEN RAISE_APPLICATION_ERROR(-20003, 'pgd_rel_graph: expected 3 two-hop matches'); END IF;
  DBMS_OUTPUT.PUT_LINE('PASS pgd_rel_graph: 5 vertices, 7 edges, 3 two-hop matches');
END;
/

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_json_graph MATCH (p IS person) COLUMNS (p.person_id AS id));
  IF n <> 5 THEN RAISE_APPLICATION_ERROR(-20001, 'pgd_json_graph: expected 5 vertices'); END IF;
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_json_graph MATCH (a IS person)-[e IS knows]->(b IS person) COLUMNS (e.edge_id AS id));
  IF n <> 7 THEN RAISE_APPLICATION_ERROR(-20002, 'pgd_json_graph: expected 7 edges'); END IF;
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_json_graph
    MATCH (a IS person)-[e1 IS knows]->(b IS person)-[e2 IS knows]->(c IS person)
    WHERE a.person_id = 1
    COLUMNS (b.person_id AS via_id, c.person_id AS target_id)
  );
  IF n <> 3 THEN RAISE_APPLICATION_ERROR(-20003, 'pgd_json_graph: expected 3 two-hop matches'); END IF;
  DBMS_OUTPUT.PUT_LINE('PASS pgd_json_graph: 5 vertices, 7 edges, 3 two-hop matches');
END;
/

-- Compare the full set of two-hop routes with explicitly expected rows.
-- Counts above additionally catch accidental duplicates of an expected route.
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
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20004, 'Two-hop route values differ'); END IF;

  SELECT COUNT(*) INTO n FROM pgd_person WHERE person_id = 4 AND city = 'Valencia';
  IF n <> 1 THEN RAISE_APPLICATION_ERROR(-20005, 'Relational demo rollback failed'); END IF;
  SELECT COUNT(*) INTO n FROM pgd_j_person
  WHERE person_id = 4 AND JSON_VALUE(data, '$.city') = 'Valencia';
  IF n <> 1 THEN RAISE_APPLICATION_ERROR(-20006, 'JSON demo rollback failed'); END IF;
  SELECT COUNT(*) INTO n FROM pgd_people_dv;
  IF n <> 5 THEN RAISE_APPLICATION_ERROR(-20007, 'Expected five duality documents'); END IF;
  DBMS_OUTPUT.PUT_LINE('PASS: expected routes and restored initial state');
END;
/

-- Metadata lets you verify which objects each graph actually references.
SELECT graph_name, element_name, element_kind, object_name
FROM user_pg_elements
WHERE graph_name IN ('PGD_REL_GRAPH','PGD_JSON_GRAPH','PGD_DV_GRAPH')
ORDER BY graph_name, element_kind, element_name;

SELECT 'CORE DEMO COMPLETED' AS status FROM dual;
