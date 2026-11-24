-- Exact SQL panels from adb26ai-property-graphs-step-by-step.pdf.
-- Execute step by step; stop at the first error. Use a dedicated demo schema.
-- Do not run after another setup path has already created the same objects.
-- OPTIONAL: follow the prerequisites and run-role guidance in the PDF.

-- Step 00.1: Prepare the schema and client
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW,
      CREATE SYNONYM, CREATE PROPERTY GRAPH TO PG_DEMO;
ALTER USER PG_DEMO QUOTA 50M ON DATA;
