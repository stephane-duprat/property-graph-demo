-- Optional: requires successful Parts D and E, with no uncommitted graph changes.
-- Part C already uses PGD_REL_GRAPH, so E1-E5 cover the shared-table duality design.
-- These queries additionally test the Part D document-projection composition.
-- No graph load or data copy is required. Verify this composition on your target.

SELECT person_id, person_name, ROUND(score, 6) AS pagerank_score
FROM GRAPH_TABLE (
  DBMS_OGA.PAGERANK(
    pgd_dv_graph,
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
    pgd_dv_graph, PROPERTY(VERTEX OUTPUT component_id)
  )
  MATCH (p IS person)
  COLUMNS (p.name AS person_name, p.component_id AS component_id)
)
GROUP BY component_id
ORDER BY people_count DESC, members;
