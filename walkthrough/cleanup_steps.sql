-- Exact SQL panels from adb26ai-property-graphs-step-by-step.pdf.
-- Execute step by step; stop at the first error. Use a dedicated demo schema.
-- Do not run after another setup path has already created the same objects.
-- OPTIONAL: follow the prerequisites and run-role guidance in the PDF.

-- Step CLEAN.1: Remove the demo only when you are finished
DECLARE
  n NUMBER;
  PROCEDURE drop_object(p_type VARCHAR2, p_name VARCHAR2) IS
  BEGIN
    SELECT COUNT(*) INTO n FROM user_objects
    WHERE object_name = p_name AND object_type = p_type;
    IF n > 0 THEN
      EXECUTE IMMEDIATE 'DROP ' || p_type || ' ' || p_name;
      DBMS_OUTPUT.PUT_LINE('Dropped ' || p_type || ' ' || p_name);
    END IF;
  END;
BEGIN
  drop_object('PROPERTY GRAPH','PGD_COST_GRAPH');
  drop_object('PROPERTY GRAPH','PGD_DV_GRAPH');
  drop_object('PROPERTY GRAPH','PGD_JSON_GRAPH');
  drop_object('PROPERTY GRAPH','PGD_REL_GRAPH');
  drop_object('VIEW','PGD_DV_KNOWS_V');
  drop_object('VIEW','PGD_DV_PERSON_V');
  drop_object('VIEW','PGD_PEOPLE_DV');
  drop_object('TABLE','PGD_J_KNOWS');
  drop_object('TABLE','PGD_J_PERSON');
  drop_object('TABLE','PGD_KNOWS');
  drop_object('TABLE','PGD_PERSON');
  FOR r IN (SELECT synonym_name FROM user_synonyms
            WHERE UPPER(synonym_name) IN ('PGD_PEOPLE_DV','PGD_J_PERSON','PGD_J_KNOWS'
              )) LOOP
    EXECUTE IMMEDIATE 'DROP SYNONYM "' || REPLACE(r.synonym_name, '"', '""') || '"';
  END LOOP;
END;
/
