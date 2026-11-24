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
