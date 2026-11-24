-- Exact SQL panels from adb26ai-property-graphs-step-by-step.pdf.
-- Execute step by step; stop at the first error. Use a dedicated demo schema.
-- Do not run after another setup path has already created the same objects.
-- Requires completed core, DB RU 23.26.2+, and no open demo transaction.

-- Step E0.1: Check algorithm availability and transaction state
DECLARE
BEGIN
  IF DBMS_TRANSACTION.LOCAL_TRANSACTION_ID(FALSE) IS NOT NULL THEN
    RAISE_APPLICATION_ERROR(-20030,
      'Open transaction: finish it deliberately or use a fresh session.');
  END IF;
END;
/

-- Step E0.2: Check algorithm availability and transaction state
SELECT product, version_full FROM product_component_version;

SELECT owner, object_name, status FROM all_objects
WHERE owner = 'SYS' AND object_type = 'PACKAGE'
  AND object_name IN ('DBMS_OGA', 'DBMS_GAF')
ORDER BY object_name;

-- Step E1.1: Rank the whole graph with PageRank
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

-- Step E2.1: Combine a computed score with a graph pattern
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

-- Step E3.1: Inspect the full identities of seed vertices
SELECT person_id, JSON_SERIALIZE(vertex_identifier RETURNING VARCHAR2(4000)) AS
  vertex_identifier
FROM GRAPH_TABLE (pgd_rel_graph
  MATCH (p IS person)
  WHERE p.person_id IN (1, 3)
  COLUMNS (p.person_id AS person_id, VERTEX_ID(p) AS vertex_identifier)
)
ORDER BY person_id;

-- Step E4.1: Personalize PageRank for Alice
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

-- Step E5.1: Personalize PageRank for Alice and Carla
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

-- Step E6.1: Find weakly connected components
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

-- Step E7.1: Expose two different edge-cost properties
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

-- Step E8.1: Compute the minimum number of outgoing hops
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

-- Step E9.1: Compute the minimum total effort
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

-- Step E10.1: Run algorithms on the JSON-backed graph
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

-- Step E11.1: Check component membership
DECLARE
  n NUMBER;
  n_components NUMBER;
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
  DBMS_OUTPUT.PUT_LINE('PASS: WCC membership');
END;
/

-- Step E12.1: Check score normalization
DECLARE
  n NUMBER;
  total_score BINARY_DOUBLE;
  lowest_score BINARY_DOUBLE;
BEGIN
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
    RAISE_APPLICATION_ERROR(-20032,
      'PageRank: expected five positive scores totaling approximately one');
  END IF;
  DBMS_OUTPUT.PUT_LINE('PASS: PageRank normalization');
END;
/

-- Step E13.1: Check the hop-distance vector
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

-- Step E14.1: Check the effort-distance vector
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

-- Step E14.2: Check the effort-distance vector
SELECT 'ALGORITHM DEMO COMPLETED' AS status FROM dual;
