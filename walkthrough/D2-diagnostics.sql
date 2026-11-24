-- Optional, read-only diagnostics if the D2 workaround still fails.
-- Run each statement separately as the original demo owner.
-- Enable DBMS_OUTPUT in the client; retain the complete output and errors.

SELECT product, version, version_full
FROM product_component_version;

SELECT SYS_CONTEXT('USERENV', 'SESSION_USER') AS session_user_name,
       SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS current_schema_name
FROM dual;

-- Expected: five people. Retain any JSON processing error.
SELECT person_id, person_name, city
FROM pgd_dv_person_v
ORDER BY person_id;

-- Expected: seven edges. This explicitly evaluates both endpoint columns.
SELECT edge_id, src_id, dst_id, since_year
FROM pgd_dv_knows_v
ORDER BY edge_id;

-- Optional reproducer of the original endpoint query. Expected count: 0.
-- This may reproduce ORA-40444; it is not the replacement validator.
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM pgd_dv_knows_v e
  WHERE e.src_id IS NULL OR e.dst_id IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pgd_dv_person_v p WHERE p.person_id = e.src_id)
     OR NOT EXISTS (
       SELECT 1 FROM pgd_dv_person_v p WHERE p.person_id = e.dst_id);
  DBMS_OUTPUT.PUT_LINE('Original query: invalid endpoints = ' || n);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_STACK);
    DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    RAISE;
END;
/
