-- Run after core, in a fresh own-schema session or after intentionally ending its transaction.
-- DB RU 23.26.2+ and working DBMS_OGA / DBMS_GAF access are required.
SET SERVEROUTPUT ON
SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 100
SET LONG 20000
WHENEVER SQLERROR EXIT SQL.SQLCODE
@@sql/07_algorithms.sql
PROMPT Part E completed. Optional duality projection algorithms: sql/08_algorithms_duality.sql
