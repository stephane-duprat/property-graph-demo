-- Connect using your normal ADB SQLcl connection first, then @run_core.sql.
-- SQLcl / SQL*Plus wrapper: fail fast; never performs cleanup automatically.
SET SERVEROUTPUT ON
SET DEFINE OFF
SET LINESIZE 180
SET PAGESIZE 100
SET LONG 20000
SET LONGCHUNKSIZE 20000
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
@@sql/00_preflight.sql
@@sql/01_relational.sql
@@sql/02_graph_queries.sql
@@sql/03_json_collections.sql
@@sql/04_duality_shared_tables.sql
@@sql/06_validate_core.sql
PROMPT Core demo finished. Optional Part D: @run_optional.sql
