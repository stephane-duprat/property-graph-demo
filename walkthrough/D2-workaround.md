# D2.1: ORA-40444 during endpoint validation

Revision: 24 November 2026. Status: proposed workaround; not run on Oracle here.

## What the reported line identifies

In the previous PDF's D2.1 block, line 16 starts this statement:

```sql
SELECT COUNT(*) INTO n FROM pgd_dv_knows_v e
WHERE e.src_id IS NULL OR e.dst_id IS NULL
   OR NOT EXISTS (
     SELECT 1 FROM pgd_dv_person_v p WHERE p.person_id = e.src_id)
   OR NOT EXISTS (
     SELECT 1 FROM pgd_dv_person_v p WHERE p.person_id = e.dst_id);
```

This validates source and destination vertices before D3 creates the graph.
Both views derive their rows from JSON in `PGD_PEOPLE_DV`. Oracle's
`ORA-40444` identifies a JSON processing failure; `ORA-06512` identifies the
PL/SQL location. Those messages alone do not establish malformed source data,
unsupported graph-on-view functionality, or a particular Oracle defect.
If the block was reformatted, use the actual line numbering of the submitted
block rather than assuming that its line 16 matches the PDF.

The two earlier key checks completed if the submitted block is unchanged.
However, successful aggregate checks alone do not prove that every projected
endpoint can be evaluated successfully. The standalone D1.2 selects remain
useful diagnostics.

## Run the replacement

1. Keep the existing D1 views and the restored demo data. Use the original demo
   owner and avoid concurrent edits to this small teaching dataset.
2. Enable DBMS_OUTPUT in your client. Run `D2-workaround.sql` as a script, or
   copy its complete anonymous block. Do not rerun setup or cleanup.
3. Expected output: `PASS: projected keys and endpoints are valid`.
4. Continue with D3 only after this succeeds. A passing validation does not
   substitute for executing the graph creation and graph queries on your ADB.

The block retains the null/duplicate person-key and edge-key checks. It then
loads the projected person IDs into a local numeric collection with
`BULK COLLECT`. A cursor reads projected edges, and PL/SQL `MEMBER OF` verifies
that both endpoints occur in the collected IDs. Explicit null and empty-list
checks avoid treating an unknown membership result as a valid endpoint.

This separates the two projection reads and removes their correlated
`NOT EXISTS` predicates from the endpoint check. It requires no new objects,
privileges, DML, commit, or rollback. The graph continues to use the original
views. Memory use and linear membership checks are appropriate for the five
people and seven edges in this demo; this is not a production-scale validator
or an atomic validation across concurrent source changes.

The changed query shape is a workaround to test. No Oracle bug number, affected
RU range, or successful live outcome has been established. The original SQL is
not inherently invalid simply because this execution reported ORA-40444.

## If it still fails

Run the statements in `D2-diagnostics.sql` individually and retain the complete
output, including the first error, `VERSION_FULL`, and both projection queries.
The last diagnostic reproduces the old endpoint query with error-stack output.
If either standalone projection fails, changing only the endpoint-validation
logic is insufficient; the projection itself needs investigation.

The shared-table design in Part C remains available: the duality view and
`PGD_REL_GRAPH` use the same relational tables. Keep Part D optional while
diagnosing the document-projection composition on the target instance.

## Oracle references

- [ORA-40444: JSON processing error](https://docs.oracle.com/en/database/oracle/oracle-database/21/errmg/ORA-40001.html)
- [ORA-06512: exception location](https://docs.oracle.com/en/error-help/db/ora-06512/)
- [BULK COLLECT](https://docs.oracle.com/en/database/oracle/oracle-database/26/lnpls/bulk-sql-and-bulk-binding.html)
- [PL/SQL collection comparisons](https://docs.oracle.com/en/database/oracle/oracle-database/26/lnpls/collection-comparisons.html)
- [MEMBER condition and null/empty behavior](https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/Multiset-Conditions.html)
