-- Part E. DBMS_OGA algorithms in SQL/PGQ. Run AFTER the core demo.
-- Documentation boundary: database RU 23.26.2+; verify on your ADB-S instance.
-- Run as the owner of the PGD_ objects, with CURRENT_SCHEMA unchanged.
-- Use a fresh session, or explicitly finish your existing transaction first.
-- Earlier ROLLBACK TO savepoint demonstrations may leave a transaction open.
-- Do NOT run algorithms between the core demo's UPDATE and ROLLBACK statements.
-- This file creates/replaces only PGD_COST_GRAPH (metadata over existing rows).
-- No table data is changed. DDL commits, so reject an open transaction up front.

DECLARE
BEGIN
  IF DBMS_TRANSACTION.LOCAL_TRANSACTION_ID(FALSE) IS NOT NULL THEN
    RAISE_APPLICATION_ERROR(-20030,
      'Open transaction: use a fresh demo session, or intentionally COMMIT/ROLLBACK before Part E.');
  END IF;
END;
/

SELECT product, version_full FROM product_component_version;
SELECT owner, object_name, status FROM all_objects
WHERE owner = 'SYS' AND object_type = 'PACKAGE'
  AND object_name IN ('DBMS_OGA', 'DBMS_GAF')
ORDER BY object_name;

-- EXECUTE on SYS.DBMS_OGA and SYS.DBMS_GAF is granted to PUBLIC by default.
-- If access was revoked, have an authorized administrator check package access.
-- Package visibility alone does not prove that GRAPH_TABLE supports GAF syntax.
-- The first query below is the actual feature/privilege execution check.

-- E1. Global PageRank: importance based on the directed link structure.
-- Arguments: max_iter, tolerance, damping_factor, normalize.
-- All vertices have outgoing edges in this baseline; TRUE also handles dangling ones.
SELECT person_id, person_name, ROUND(score, 6) AS pagerank_score
FROM GRAPH_TABLE (
  DBMS_OGA.PAGERANK(
    pgd_rel_graph,
    PROPERTY(VERTEX OUTPUT pr_score),
    1000, 1e-10, 0.85d, TRUE
  )
  MATCH (p IS person)
  COLUMNS (p.person_id AS person_id, p.name AS person_name,
           p.pr_score AS score)
)
ORDER BY score DESC, person_id;

-- E2. Combine algorithm output with a relationship pattern.
-- PageRank is computed over the INPUT GRAPH. MATCH/WHERE selects result vertices.
-- This is NOT PageRank recomputed on just the two-hop neighborhood.
-- DISTINCT collapses Diego's two matching routes to one scored destination.
SELECT DISTINCT target_name, ROUND(score, 6) AS pagerank_score
FROM GRAPH_TABLE (
  DBMS_OGA.PAGERANK(
    pgd_rel_graph, PROPERTY(VERTEX OUTPUT pr_score),
    1000, 1e-10, 0.85d, TRUE
  )
  MATCH (a IS person)-[e1 IS knows]->(b IS person)
                     -[e2 IS knows]->(c IS person)
  WHERE a.person_id = 1
  COLUMNS (c.name AS target_name, c.pr_score AS score)
)
ORDER BY pagerank_score DESC, target_name;

-- E3. Personalized PageRank, biased toward Alice (person_id = 1).
-- Inspect the actual identifiers first. PEOPLE is the graph element alias from DDL;
-- it is neither the PERSON label nor the PGD_PERSON source-table name.
SELECT person_id, JSON_SERIALIZE(vertex_identifier RETURNING VARCHAR2(4000)) AS vertex_identifier
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (p IS person)
  WHERE p.person_id IN (1, 3)
  COLUMNS (p.person_id AS person_id, VERTEX_ID(p) AS vertex_identifier)
)
ORDER BY person_id;

-- The JSON_OBJECT below constructs that identity for this OWN-SCHEMA demo.
-- For other schemas/graphs, use the exact owner, graph, alias and key from VERTEX_ID.
SELECT person_id, person_name, ROUND(score, 6) AS alice_score
FROM GRAPH_TABLE (
  DBMS_OGA.PERSONALIZED_PAGERANK(
    pgd_rel_graph,
    PROPERTY(VERTEX OUTPUT ppr_score),
    JSON_OBJECT(
      'GRAPH_OWNER' VALUE SYS_CONTEXT('USERENV', 'SESSION_USER'),
      'GRAPH_NAME' VALUE 'PGD_REL_GRAPH',
      'ELEM_TABLE' VALUE 'PEOPLE',
      'KEY_VALUE' VALUE JSON_OBJECT('PERSON_ID' VALUE 1)
      RETURNING JSON
    ),
    1000, 1e-10, 0.85d, TRUE
  )
  MATCH (p IS person)
  COLUMNS (p.person_id AS person_id, p.name AS person_name,
           p.ppr_score AS score)
)
ORDER BY score DESC, person_id;

-- E4. Personalized PageRank for a SET: Alice and Carla.
-- Both seeds carry equal preference. The parameter is a JSON ARRAY of full vertex IDs.
SELECT person_id, person_name, ROUND(score, 6) AS seed_set_score
FROM GRAPH_TABLE (
  DBMS_OGA.PERSONALIZED_PAGERANK_SET(
    pgd_rel_graph,
    PROPERTY(VERTEX OUTPUT set_score),
    JSON_ARRAY(
      JSON_OBJECT(
        'GRAPH_OWNER' VALUE SYS_CONTEXT('USERENV', 'SESSION_USER'),
        'GRAPH_NAME' VALUE 'PGD_REL_GRAPH',
        'ELEM_TABLE' VALUE 'PEOPLE',
        'KEY_VALUE' VALUE JSON_OBJECT('PERSON_ID' VALUE 1)
        RETURNING JSON
      ),
      JSON_OBJECT(
        'GRAPH_OWNER' VALUE SYS_CONTEXT('USERENV', 'SESSION_USER'),
        'GRAPH_NAME' VALUE 'PGD_REL_GRAPH',
        'ELEM_TABLE' VALUE 'PEOPLE',
        'KEY_VALUE' VALUE JSON_OBJECT('PERSON_ID' VALUE 3)
        RETURNING JSON
      )
      RETURNING JSON
    ),
    1000, 1e-10, 0.85d, TRUE
  )
  MATCH (p IS person)
  COLUMNS (p.person_id AS person_id, p.name AS person_name,
           p.set_score AS score)
)
ORDER BY score DESC, person_id;

-- E5. Weakly connected components. Directions are ignored for connectivity.
-- Baseline expectation: one component with all five people.
-- Component numbers are opaque and may change between executions.
SELECT component_id, COUNT(*) AS people_count,
       LISTAGG(person_name, ', ') WITHIN GROUP (ORDER BY person_name) AS members
FROM GRAPH_TABLE (
  DBMS_OGA.WCC(
    pgd_rel_graph, PROPERTY(VERTEX OUTPUT component_id)
  )
  MATCH (p IS person)
  COLUMNS (p.name AS person_name, p.component_id AS component_id)
)
GROUP BY component_id
ORDER BY people_count DESC, members;

-- E6. A second graph mapping exposes costs WITHOUT copying or updating table rows.
-- Fictional effort: Alice->Carla costs 9; Alice->Bob->Elena->Carla costs 3.
-- SINCE_YEAR is a date-like attribute, not a meaningful traversal cost.
CREATE OR REPLACE PROPERTY GRAPH pgd_cost_graph
  VERTEX TABLES (
    pgd_person AS people KEY (person_id)
      LABEL person PROPERTIES (person_id, person_name AS name, city)
  )
  EDGE TABLES (
    pgd_knows AS links KEY (edge_id)
      SOURCE KEY (src_id) REFERENCES people (person_id)
      DESTINATION KEY (dst_id) REFERENCES people (person_id)
      LABEL knows PROPERTIES (
        edge_id, since_year,
        1 AS hop_cost,
        CASE edge_id
          WHEN 101 THEN 1 WHEN 102 THEN 9 WHEN 103 THEN 2
          WHEN 104 THEN 1 WHEN 105 THEN 1 WHEN 106 THEN 1
          WHEN 107 THEN 1 ELSE 1
        END AS effort
      )
  )
  OPTIONS (ENFORCED MODE);

-- E6a. Every edge costs 1: Bellman-Ford returns minimum directed hop distances.
-- Expected by person_id: Alice=0, Bob=1, Carla=1, Diego=2, Elena=2.
-- The input property is an EXPRESSION, so DEFAULT ON NULL is required here.
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
ORDER BY person_id;

-- E6b. Weighted shortest distances: Alice=0, Bob=1, Carla=3, Diego=3, Elena=2.
-- Carla's cheapest route has 3 edges, although the minimum hop count is 1.
-- BELLMAN_FORD returns distances, not the traversed vertices/edges.
-- Oracle's implementation rejects negative/NULL weights; unreachable = +infinity.
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
ORDER BY person_id;

-- E7. Algorithms consume the SQL graph, regardless of its relational/JSON sources.
-- On the unchanged Part B sample, these agree with the relational graph results.
SELECT person_id, person_name, ROUND(score, 6) AS pagerank_score
FROM GRAPH_TABLE (
  DBMS_OGA.PAGERANK(
    pgd_json_graph,
    PROPERTY(VERTEX OUTPUT pr_score),
    1000, 1e-10, 0.85d, TRUE
  )
  MATCH (p IS person)
  COLUMNS (p.person_id AS person_id, p.name AS person_name,
           p.pr_score AS score)
)
ORDER BY score DESC, person_id;

SELECT component_id, COUNT(*) AS people_count,
       LISTAGG(person_name, ', ') WITHIN GROUP (ORDER BY person_name) AS members
FROM GRAPH_TABLE (
  DBMS_OGA.WCC(
    pgd_json_graph, PROPERTY(VERTEX OUTPUT component_id)
  )
  MATCH (p IS person)
  COLUMNS (p.name AS person_name, p.component_id AS component_id)
)
GROUP BY component_id
ORDER BY people_count DESC, members;

-- E8. Small database-side checks. These are executed only on your target instance.
-- A different topology may legitimately change these baseline expectations.
DECLARE
  n NUMBER;
  n_components NUMBER;
  total_score BINARY_DOUBLE;
  lowest_score BINARY_DOUBLE;
BEGIN
  SELECT COUNT(*), COUNT(DISTINCT component_id)
  INTO n, n_components
  FROM GRAPH_TABLE (
    DBMS_OGA.WCC(pgd_rel_graph, PROPERTY(VERTEX OUTPUT component_id))
    MATCH (p IS person)
    COLUMNS (p.component_id AS component_id)
  );
  IF n <> 5 OR n_components <> 1 THEN
    RAISE_APPLICATION_ERROR(-20031, 'WCC: expected five vertices in one component');
  END IF;

  SELECT COUNT(*), SUM(score), MIN(score)
  INTO n, total_score, lowest_score
  FROM GRAPH_TABLE (
    DBMS_OGA.PAGERANK(pgd_rel_graph, PROPERTY(VERTEX OUTPUT pr_score),
                      1000, 1e-10, 0.85d, TRUE)
    MATCH (p IS person)
    COLUMNS (p.pr_score AS score)
  );
  IF n <> 5 OR total_score IS NULL OR ABS(total_score - 1) > 1e-8
     OR lowest_score IS NULL OR lowest_score <= 0 THEN
    RAISE_APPLICATION_ERROR(-20032, 'PageRank: expected five positive scores totaling approximately one');
  END IF;

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
  WHERE min_hops = CASE person_id WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 3 THEN 1 WHEN 4 THEN 2 WHEN 5 THEN 2 END;
  IF n <> 5 THEN
    RAISE_APPLICATION_ERROR(-20033, 'Bellman-Ford: unexpected min_hops results');
  END IF;

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
  WHERE min_effort = CASE person_id WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 3 THEN 3 WHEN 4 THEN 3 WHEN 5 THEN 2 END;
  IF n <> 5 THEN
    RAISE_APPLICATION_ERROR(-20034, 'Bellman-Ford: unexpected min_effort results');
  END IF;

  DBMS_OUTPUT.PUT_LINE('PASS algorithms: normalized PageRank, WCC membership, hop and effort distances');
END;
/

-- pr_score, ppr_score, set_score, component_id, min_hops and min_effort were
-- temporary properties of their respective GRAPH_TABLE calls. They were NOT
-- added to PGD_REL_GRAPH, PGD_JSON_GRAPH, PGD_COST_GRAPH, or the source tables.
SELECT 'ALGORITHM DEMO COMPLETED' AS status FROM dual;
