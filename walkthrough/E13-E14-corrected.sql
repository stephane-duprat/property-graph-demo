-- Revised 24 November 2026. Run as the graph owner after step E7.1.
-- Existing demo objects are reused. No DDL, data changes or cleanup.
-- Enable DBMS_OUTPUT in your client to see the PASS messages.
-- Revision reviewed locally; live Oracle execution remains to be verified.

-- Step E13.1
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM (
    SELECT person_id, person_name, min_hops
    FROM GRAPH_TABLE (
      DBMS_OGA.BELLMAN_FORD(
        pgd_cost_graph,
        JSON_OBJECT(
          'GRAPH_OWNER' VALUE SYS_CONTEXT('USERENV', 'SESSION_USER'),
          'GRAPH_NAME' VALUE 'PGD_COST_GRAPH',
          'ELEM_TABLE' VALUE 'PEOPLE',
          'KEY_VALUE' VALUE JSON_OBJECT('PERSON_ID' VALUE 1)
          RETURNING JSON
        ),
        PROPERTY(EDGE INPUT hop_cost DEFAULT ON NULL 1),
        PROPERTY(VERTEX OUTPUT min_hops)
      )
      MATCH (p IS person)
      COLUMNS (p.person_id AS person_id, p.name AS person_name,
               p.min_hops AS min_hops)
    )
  )
  WHERE min_hops = CASE person_id WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 3 THEN 1 WHEN 4
    THEN 2 WHEN 5 THEN 2 END;
  IF n <> 5 THEN
    RAISE_APPLICATION_ERROR(-20033, 'Bellman-Ford: unexpected min_hops results');
  END IF;
  DBMS_OUTPUT.PUT_LINE('PASS: Hop distances');
END;
/

-- Step E14.1
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM (
    SELECT person_id, person_name, min_effort
    FROM GRAPH_TABLE (
      DBMS_OGA.BELLMAN_FORD(
        pgd_cost_graph,
        JSON_OBJECT(
          'GRAPH_OWNER' VALUE SYS_CONTEXT('USERENV', 'SESSION_USER'),
          'GRAPH_NAME' VALUE 'PGD_COST_GRAPH',
          'ELEM_TABLE' VALUE 'PEOPLE',
          'KEY_VALUE' VALUE JSON_OBJECT('PERSON_ID' VALUE 1)
          RETURNING JSON
        ),
        PROPERTY(EDGE INPUT effort DEFAULT ON NULL 1),
        PROPERTY(VERTEX OUTPUT min_effort)
      )
      MATCH (p IS person)
      COLUMNS (p.person_id AS person_id, p.name AS person_name,
               p.min_effort AS min_effort)
    )
  )
  WHERE min_effort = CASE person_id WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 3 THEN 3 WHEN 4
    THEN 3 WHEN 5 THEN 2 END;
  IF n <> 5 THEN
    RAISE_APPLICATION_ERROR(-20034, 'Bellman-Ford: unexpected min_effort results');
  END IF;
  DBMS_OUTPUT.PUT_LINE('PASS: Effort distances');
END;
/
