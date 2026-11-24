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
