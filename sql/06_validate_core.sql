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
