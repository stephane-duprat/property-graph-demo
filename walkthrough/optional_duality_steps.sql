-- Exact SQL panels from adb26ai-property-graphs-step-by-step.pdf.
-- Execute step by step; stop at the first error. Use a dedicated demo schema.
-- Do not run after another setup path has already created the same objects.
-- OPTIONAL: follow the prerequisites and run-role guidance in the PDF.

-- Step D1.1: Project documents into relational vertex and edge rows
CREATE VIEW pgd_dv_person_v AS
SELECT j.person_id, j.person_name, j.city
FROM pgd_people_dv d,
     JSON_TABLE(d.data, '$' ERROR ON ERROR
       COLUMNS (
         person_id NUMBER PATH '$._id',
         person_name VARCHAR2(50) PATH '$.name',
         city VARCHAR2(50) PATH '$.city'
       )) j;

CREATE VIEW pgd_dv_knows_v AS
SELECT JSON_VALUE(d.data, '$._id' RETURNING NUMBER ERROR ON ERROR) AS src_id,
       j.edge_id, j.dst_id, j.since_year
FROM pgd_people_dv d,
     JSON_TABLE(d.data, '$.outgoing[*]' ERROR ON ERROR
       COLUMNS (
         edge_id NUMBER PATH '$.edge_id',
         dst_id NUMBER PATH '$.to',
         since_year NUMBER PATH '$.since'
       )) j;

-- Step D1.2: Project documents into relational vertex and edge rows
SELECT * FROM pgd_dv_person_v ORDER BY person_id;
SELECT * FROM pgd_dv_knows_v ORDER BY edge_id;

-- Step D2.1: Validate the projected keys
DECLARE
  n NUMBER;
  TYPE id_list IS TABLE OF NUMBER;
  person_ids id_list;
BEGIN
  SELECT COUNT(*) INTO n FROM (
    SELECT person_id FROM pgd_dv_person_v
    GROUP BY person_id HAVING person_id IS NULL OR COUNT(*) > 1
  );
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20011, 'Null or duplicate person keys'); END
    IF;
  SELECT COUNT(*) INTO n FROM (
    SELECT edge_id FROM pgd_dv_knows_v
    GROUP BY edge_id HAVING edge_id IS NULL OR COUNT(*) > 1
  );
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20012, 'Null or duplicate edge keys'); END
    IF;
  SELECT person_id BULK COLLECT INTO person_ids FROM pgd_dv_person_v;
  FOR e IN (SELECT edge_id, src_id, dst_id FROM pgd_dv_knows_v) LOOP
    IF e.src_id IS NULL OR e.dst_id IS NULL
       OR person_ids.COUNT = 0
       OR e.src_id NOT MEMBER OF person_ids
       OR e.dst_id NOT MEMBER OF person_ids THEN
      RAISE_APPLICATION_ERROR(-20013,
        'Missing endpoint on edge ' || e.edge_id);
    END IF;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('PASS: projected keys and endpoints are valid');
END;
/

-- Step D3.1: Create and query the graph over those views
CREATE PROPERTY GRAPH pgd_dv_graph
  VERTEX TABLES (
    pgd_dv_person_v AS people KEY (person_id)
      LABEL person PROPERTIES (person_id, person_name AS name, city)
  )
  EDGE TABLES (
    pgd_dv_knows_v AS links KEY (edge_id)
      SOURCE KEY (src_id) REFERENCES people (person_id)
      DESTINATION KEY (dst_id) REFERENCES people (person_id)
      LABEL knows PROPERTIES (edge_id, since_year)
  )
  OPTIONS (TRUSTED MODE);

SELECT start_name, via_name, target_name
FROM GRAPH_TABLE (pgd_dv_graph
  MATCH (a IS person)-[e1 IS knows]->(b IS person)
                     -[e2 IS knows]->(c IS person)
  WHERE a.person_id = 1
  COLUMNS (a.name AS start_name, b.name AS via_name,
           c.name AS target_name)
)
ORDER BY via_name, target_name;

-- Step D4.1: Verify the optional graph and update shared data
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_dv_graph MATCH (p IS person) COLUMNS
    (p.person_id AS id));
  IF n <> 5 THEN RAISE_APPLICATION_ERROR(-20001, 'pgd_dv_graph: expected 5 vertices');
    END IF;
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_dv_graph MATCH (a IS person)-[e IS
    knows]->(b IS person) COLUMNS (e.edge_id AS id));
  IF n <> 7 THEN RAISE_APPLICATION_ERROR(-20002, 'pgd_dv_graph: expected 7 edges');
    END IF;
  SELECT COUNT(*) INTO n FROM GRAPH_TABLE (pgd_dv_graph
    MATCH (a IS person)-[e1 IS knows]->(b IS person)-[e2 IS knows]->(c IS person)
    WHERE a.person_id = 1
    COLUMNS (b.person_id AS via_id, c.person_id AS target_id)
  );
  IF n <> 3 THEN RAISE_APPLICATION_ERROR(-20003,
    'pgd_dv_graph: expected 3 two-hop matches'); END IF;
  DBMS_OUTPUT.PUT_LINE('PASS pgd_dv_graph: 5 vertices, 7 edges, 3 two-hop matches');
END;
/

-- Step D4.2: Verify the optional graph and update shared data
SAVEPOINT pgd_before_optional_update;
UPDATE pgd_people_dv
SET data = JSON_TRANSFORM(data, SET '$.city' = 'Sevilla')
WHERE JSON_VALUE(data, '$._id' RETURNING NUMBER) = 4;
SELECT person_id, person_name, city
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (p IS person)
  COLUMNS (p.person_id AS person_id, p.name AS person_name, p.city AS city)
)
ORDER BY person_id;
SELECT person_id, person_name, city
FROM GRAPH_TABLE (pgd_dv_graph
  MATCH (p IS person)
  COLUMNS (p.person_id AS person_id, p.name AS person_name, p.city AS city)
)
ORDER BY person_id;
ROLLBACK TO pgd_before_optional_update;

-- Step D4.3: Verify the optional graph and update shared data
ROLLBACK;
