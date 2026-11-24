-- Requires successful core setup and DB RU 23.26.1+ graph-over-view capability.
SET SERVEROUTPUT ON
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
@@sql/05_optional_graph_from_duality.sql
PROMPT Optional graph-from-duality composition passed on this database.
