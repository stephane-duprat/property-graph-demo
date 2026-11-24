-- Revised 24 November 2026: replacement for PDF step D2.1 only.
-- Run after D1, as the original demo owner. Existing views are reused.
-- Proposed ORA-40444 workaround; target ADB execution is not yet verified.
-- Enable DBMS_OUTPUT in the client. No DDL, DML, COMMIT or ROLLBACK.
-- Continue to D3 only if the PASS message is returned.

-- Step D2.1: Validate the projected keys
DECLARE
  n NUMBER;
  TYPE id_list IS TABLE OF NUMBER;
  person_ids id_list;
BEGIN
  SELECT COUNT(*) INTO n FROM (
    SELECT person_id FROM pgd_dv_person_v
    GROUP BY person_id HAVING person_id IS NULL OR COUNT(*) > 1
  );
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20011, 'Null or duplicate person keys'); END
    IF;
  SELECT COUNT(*) INTO n FROM (
    SELECT edge_id FROM pgd_dv_knows_v
    GROUP BY edge_id HAVING edge_id IS NULL OR COUNT(*) > 1
  );
  IF n <> 0 THEN RAISE_APPLICATION_ERROR(-20012, 'Null or duplicate edge keys'); END
    IF;
  SELECT person_id BULK COLLECT INTO person_ids FROM pgd_dv_person_v;
  FOR e IN (SELECT edge_id, src_id, dst_id FROM pgd_dv_knows_v) LOOP
    IF e.src_id IS NULL OR e.dst_id IS NULL
       OR person_ids.COUNT = 0
       OR e.src_id NOT MEMBER OF person_ids
       OR e.dst_id NOT MEMBER OF person_ids THEN
      RAISE_APPLICATION_ERROR(-20013,
        'Missing endpoint on edge ' || e.edge_id);
    END IF;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('PASS: projected keys and endpoints are valid');
END;
/
