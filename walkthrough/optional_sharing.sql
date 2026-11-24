-- Exact SQL panels from adb26ai-property-graphs-step-by-step.pdf.
-- Execute step by step; stop at the first error. Use a dedicated demo schema.
-- Do not run after another setup path has already created the same objects.
-- OPTIONAL: follow the prerequisites and run-role guidance in the PDF.

-- Step SHARE.1: Grant access to a particular graph
GRANT READ ON PROPERTY GRAPH pgd_rel_graph TO PG_READER;

-- Step SHARE.2: Grant access to a particular graph
SELECT name
FROM system_privilege_map
WHERE name LIKE '%PROPERTY GRAPH'
ORDER BY name;
