-- Use an empty demo schema. No database credentials are included in this kit.
-- 26ai is the product name; VERSION_FULL may still begin with 23.
SELECT product, version, version_full FROM product_component_version;
SELECT USER AS current_schema FROM dual;
-- Only creation privileges are needed for this demo's own-schema objects.
-- The owner can query and drop its own property graphs without extra grants.
SELECT privilege FROM session_privs
WHERE privilege IN ('CREATE SESSION','CREATE TABLE','CREATE VIEW',
                    'CREATE SYNONYM','CREATE PROPERTY GRAPH')
ORDER BY privilege;

-- Fail before setup if any pre-existing object uses this demo's namespace.
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM user_objects
  WHERE UPPER(object_name) LIKE 'PGD\_%' ESCAPE '\';
  IF n <> 0 THEN
    RAISE_APPLICATION_ERROR(-20000,
      'PGD_ objects already exist. Use a fresh schema or review 99_cleanup.sql.');
  END IF;
END;
/
