-- Exact SQL panels from adb26ai-property-graphs-step-by-step.pdf.
-- Execute step by step; stop at the first error. Use a dedicated demo schema.
-- Do not run after another setup path has already created the same objects.

-- Step 00.2: Prepare the schema and client
SET SERVEROUTPUT ON
SET DEFINE OFF
SET AUTOCOMMIT OFF
SET LINESIZE 180
SET PAGESIZE 100
SET LONG 20000
SET LONGCHUNKSIZE 20000
